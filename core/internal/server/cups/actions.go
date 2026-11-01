package cups

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"os/exec"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/pkg/ipp"
)

func isAuthError(err error) bool {
	if err == nil {
		return false
	}

	if httpErr, ok := errors.AsType[ipp.HTTPError](err); ok {
		return httpErr.Code == 401 || httpErr.Code == 403
	}

	if ippErr, ok := errors.AsType[ipp.IPPError](err); ok {
		return ippErr.Status == ipp.StatusErrorForbidden ||
			ippErr.Status == ipp.StatusErrorNotAuthenticated ||
			ippErr.Status == ipp.StatusErrorNotAuthorized
	}

	return false
}

func (m *Manager) GetPrinters() ([]Printer, error) {
	attributes := []string{
		ipp.AttributePrinterName,
		ipp.AttributePrinterUriSupported,
		ipp.AttributePrinterState,
		ipp.AttributePrinterStateReasons,
		ipp.AttributePrinterLocation,
		ipp.AttributePrinterInfo,
		ipp.AttributePrinterMakeAndModel,
		ipp.AttributePrinterIsAcceptingJobs,
	}

	printerAttrs, err := m.client.GetPrinters(attributes)
	if err != nil {
		if isNoPrintersError(err) {
			return []Printer{}, nil
		}
		return nil, err
	}

	printers := make([]Printer, 0, len(printerAttrs))
	for _, attrs := range printerAttrs {
		printer := Printer{
			Name:        getStringAttr(attrs, ipp.AttributePrinterName),
			URI:         getStringAttr(attrs, ipp.AttributePrinterUriSupported),
			State:       parsePrinterState(attrs),
			StateReason: getStringAttr(attrs, ipp.AttributePrinterStateReasons),
			Location:    getStringAttr(attrs, ipp.AttributePrinterLocation),
			Info:        getStringAttr(attrs, ipp.AttributePrinterInfo),
			MakeModel:   getStringAttr(attrs, ipp.AttributePrinterMakeAndModel),
			Accepting:   getBoolAttr(attrs, ipp.AttributePrinterIsAcceptingJobs),
		}

		if printer.Name != "" {
			printers = append(printers, printer)
		}
	}

	return printers, nil
}

func (m *Manager) GetJobs(printerName string, whichJobs string) ([]Job, error) {
	attributes := []string{
		ipp.AttributeJobID,
		ipp.AttributeJobName,
		ipp.AttributeJobState,
		ipp.AttributeJobPrinterURI,
		ipp.AttributeJobOriginatingUserName,
		ipp.AttributeJobKilobyteOctets,
		"time-at-creation",
	}

	jobAttrs, err := m.client.GetJobs(printerName, "", whichJobs, false, 0, 0, attributes)
	if err != nil {
		return nil, err
	}

	jobs := make([]Job, 0, len(jobAttrs))
	for _, attrs := range jobAttrs {
		job := Job{
			ID:    getIntAttr(attrs, ipp.AttributeJobID),
			Name:  getStringAttr(attrs, ipp.AttributeJobName),
			State: parseJobState(attrs),
			User:  getStringAttr(attrs, ipp.AttributeJobOriginatingUserName),
			Size:  getIntAttr(attrs, ipp.AttributeJobKilobyteOctets) * 1024,
		}

		if uri := getStringAttr(attrs, ipp.AttributeJobPrinterURI); uri != "" {
			parts := strings.Split(uri, "/")
			if len(parts) > 0 {
				job.Printer = parts[len(parts)-1]
			}
		}

		if ts := getIntAttr(attrs, "time-at-creation"); ts > 0 {
			job.TimeCreated = time.Unix(int64(ts), 0)
		}

		if job.ID != 0 {
			jobs = append(jobs, job)
		}
	}

	return jobs, nil
}

func (m *Manager) CancelJob(jobID int) error {
	err := m.client.CancelJob(jobID, false)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.JobCancelPurge(jobID, false)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) PausePrinter(printerName string) error {
	err := m.client.PausePrinter(printerName)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.PrinterSetEnabled(printerName, false)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) ResumePrinter(printerName string) error {
	err := m.client.ResumePrinter(printerName)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.PrinterSetEnabled(printerName, true)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) PurgeJobs(printerName string) error {
	err := m.client.CancelAllJob(printerName, true)
	if err == nil {
		m.RefreshState()
	}
	return err
}

func resolveIPFromURI(uri string) string {
	parsed, err := url.Parse(uri)
	if err != nil {
		return ""
	}
	host := parsed.Hostname()
	if host == "" {
		return ""
	}
	if ip := net.ParseIP(host); ip != nil {
		return ip.String()
	}
	addrs, err := net.LookupIP(host)
	if err != nil || len(addrs) == 0 {
		return ""
	}
	for _, addr := range addrs {
		if v4 := addr.To4(); v4 != nil {
			return v4.String()
		}
	}
	return addrs[0].String()
}

func (m *Manager) GetDevices() ([]Device, error) {
	if m.pkHelper != nil {
		devices, err := m.pkHelper.DevicesGet(10, 0, nil, nil)
		if err != nil {
			return nil, err
		}
		for i := range devices {
			if devices[i].Class == "network" {
				devices[i].IP = resolveIPFromURI(devices[i].URI)
			}
		}
		return devices, nil
	}

	deviceAttrs, err := m.client.GetDevices()
	if err != nil {
		return nil, err
	}

	devices := make([]Device, 0, len(deviceAttrs))
	for uri, attrs := range deviceAttrs {
		device := Device{
			URI:       uri,
			Class:     getStringAttr(attrs, "device-class"),
			Info:      getStringAttr(attrs, "device-info"),
			MakeModel: getStringAttr(attrs, "device-make-and-model"),
			ID:        getStringAttr(attrs, "device-id"),
			Location:  getStringAttr(attrs, "device-location"),
		}
		if device.Class == "network" {
			device.IP = resolveIPFromURI(uri)
		}
		devices = append(devices, device)
	}

	return devices, nil
}

func (m *Manager) GetPPDs() ([]PPD, error) {
	ppdAttrs, err := m.client.GetPPDs()
	if err != nil {
		return nil, err
	}

	ppds := make([]PPD, 0, len(ppdAttrs))
	for name, attrs := range ppdAttrs {
		ppd := PPD{
			Name:            name,
			NaturalLanguage: getStringAttr(attrs, "ppd-natural-language"),
			MakeModel:       getStringAttr(attrs, ipp.AttributePPDMakeAndModel),
			DeviceID:        getStringAttr(attrs, "ppd-device-id"),
			Product:         getStringAttr(attrs, "ppd-product"),
			PSVersion:       getStringAttr(attrs, "ppd-psversion"),
			Type:            getStringAttr(attrs, "ppd-type"),
		}
		ppds = append(ppds, ppd)
	}

	return ppds, nil
}

func (m *Manager) GetClasses() ([]PrinterClass, error) {
	attributes := []string{
		ipp.AttributePrinterName,
		ipp.AttributePrinterUriSupported,
		ipp.AttributePrinterState,
		ipp.AttributeMemberURIs,
		ipp.AttributeMemberNames,
		ipp.AttributePrinterLocation,
		ipp.AttributePrinterInfo,
	}

	classAttrs, err := m.client.GetClasses(attributes)
	if err != nil {
		return nil, err
	}

	classes := make([]PrinterClass, 0, len(classAttrs))
	for _, attrs := range classAttrs {
		class := PrinterClass{
			Name:     getStringAttr(attrs, ipp.AttributePrinterName),
			URI:      getStringAttr(attrs, ipp.AttributePrinterUriSupported),
			State:    parsePrinterState(attrs),
			Location: getStringAttr(attrs, ipp.AttributePrinterLocation),
			Info:     getStringAttr(attrs, ipp.AttributePrinterInfo),
			Members:  getStringSliceAttr(attrs, ipp.AttributeMemberNames),
		}
		classes = append(classes, class)
	}

	return classes, nil
}

func createPrinterViaLpadmin(name, deviceURI, ppd, information, location string) error {
	args := []string{"-p", name, "-E", "-v", deviceURI, "-m", ppd}
	if information != "" {
		args = append(args, "-D", information)
	}
	if location != "" {
		args = append(args, "-L", location)
	}
	out, err := exec.Command("lpadmin", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("lpadmin failed: %s: %w", strings.TrimSpace(string(out)), err)
	}
	return nil
}

func deletePrinterViaLpadmin(name string) error {
	out, err := exec.Command("lpadmin", "-x", name).CombinedOutput()
	if err != nil {
		return fmt.Errorf("lpadmin failed: %s: %w", strings.TrimSpace(string(out)), err)
	}
	return nil
}

func (m *Manager) CreatePrinter(name, deviceURI, ppd string, shared bool, errorPolicy, information, location string) error {
	usedPkHelper := false

	err := m.client.CreatePrinter(name, deviceURI, ppd, shared, errorPolicy, information, location)
	if isAuthError(err) && m.pkHelper != nil {
		if err = m.pkHelper.PrinterAdd(name, deviceURI, ppd, information, location); err != nil {
			// pkHelper failed (e.g., no polkit agent), try lpadmin as last resort.
			// lpadmin -E enables the printer, so no further setup needed.
			if lpadminErr := createPrinterViaLpadmin(name, deviceURI, ppd, information, location); lpadminErr != nil {
				return err
			}
			m.RefreshState()
			return nil
		}
		usedPkHelper = true
	} else if err != nil {
		return err
	}

	if usedPkHelper {
		m.pkHelper.PrinterSetEnabled(name, true)        //nolint:errcheck
		m.pkHelper.PrinterSetAcceptJobs(name, true, "") //nolint:errcheck
	} else {
		if err := m.client.ResumePrinter(name); isAuthError(err) && m.pkHelper != nil {
			m.pkHelper.PrinterSetEnabled(name, true) //nolint:errcheck
		}
		if err := m.client.AcceptJobs(name); isAuthError(err) && m.pkHelper != nil {
			m.pkHelper.PrinterSetAcceptJobs(name, true, "") //nolint:errcheck
		}
	}

	m.RefreshState()
	return nil
}

func (m *Manager) DeletePrinter(printerName string) error {
	err := m.client.DeletePrinter(printerName)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.PrinterDelete(printerName)
		if err != nil {
			// pkHelper failed, try lpadmin as last resort
			if lpadminErr := deletePrinterViaLpadmin(printerName); lpadminErr == nil {
				err = nil
			}
		}
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) AcceptJobs(printerName string) error {
	err := m.client.AcceptJobs(printerName)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.PrinterSetAcceptJobs(printerName, true, "")
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) RejectJobs(printerName string) error {
	err := m.client.RejectJobs(printerName)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.PrinterSetAcceptJobs(printerName, false, "")
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) SetPrinterShared(printerName string, shared bool) error {
	err := m.client.SetPrinterIsShared(printerName, shared)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.PrinterSetShared(printerName, shared)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) SetPrinterLocation(printerName, location string) error {
	err := m.client.SetPrinterLocation(printerName, location)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.PrinterSetLocation(printerName, location)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) SetPrinterInfo(printerName, info string) error {
	err := m.client.SetPrinterInformation(printerName, info)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.PrinterSetInfo(printerName, info)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) MoveJob(jobID int, destPrinter string) error {
	err := m.client.MoveJob(jobID, destPrinter)
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) PrintTestPage(printerName string) (int, error) {
	jobID, err := m.client.PrintTestPage(printerName, strings.NewReader(config.TestPage), len(config.TestPage))
	if err == nil {
		m.RefreshState()
	}
	return jobID, err
}

func (m *Manager) AddPrinterToClass(className, printerName string) error {
	err := m.client.AddPrinterToClass(className, printerName)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.ClassAddPrinter(className, printerName)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) RemovePrinterFromClass(className, printerName string) error {
	err := m.client.DeletePrinterFromClass(className, printerName)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.ClassDeletePrinter(className, printerName)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) DeleteClass(className string) error {
	err := m.client.DeleteClass(className)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.ClassDelete(className)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) RestartJob(jobID int) error {
	err := m.client.RestartJob(jobID)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.JobRestart(jobID)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}

func (m *Manager) HoldJob(jobID int, holdUntil string) error {
	err := m.client.HoldJobUntil(jobID, holdUntil)
	if isAuthError(err) && m.pkHelper != nil {
		err = m.pkHelper.JobSetHoldUntil(jobID, holdUntil)
	}
	if err == nil {
		m.RefreshState()
	}
	return err
}
