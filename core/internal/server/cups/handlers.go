package cups

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

type CUPSEvent struct {
	Type string    `json:"type"`
	Data CUPSState `json:"data"`
}

type TestPageResult struct {
	Success bool   `json:"success"`
	JobID   int    `json:"jobId"`
	Message string `json:"message"`
}

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "cups.subscribe":
		handleSubscribe(conn, req, manager)
	case "cups.getPrinters":
		handleGetPrinters(conn, req, manager)
	case "cups.getJobs":
		handleGetJobs(conn, req, manager)
	case "cups.pausePrinter":
		handlePausePrinter(conn, req, manager)
	case "cups.resumePrinter":
		handleResumePrinter(conn, req, manager)
	case "cups.cancelJob":
		handleCancelJob(conn, req, manager)
	case "cups.purgeJobs":
		handlePurgeJobs(conn, req, manager)
	case "cups.getDevices":
		handleGetDevices(conn, req, manager)
	case "cups.getPPDs":
		handleGetPPDs(conn, req, manager)
	case "cups.getClasses":
		handleGetClasses(conn, req, manager)
	case "cups.createPrinter":
		handleCreatePrinter(conn, req, manager)
	case "cups.deletePrinter":
		handleDeletePrinter(conn, req, manager)
	case "cups.acceptJobs":
		handleAcceptJobs(conn, req, manager)
	case "cups.rejectJobs":
		handleRejectJobs(conn, req, manager)
	case "cups.setPrinterShared":
		handleSetPrinterShared(conn, req, manager)
	case "cups.setPrinterLocation":
		handleSetPrinterLocation(conn, req, manager)
	case "cups.setPrinterInfo":
		handleSetPrinterInfo(conn, req, manager)
	case "cups.moveJob":
		handleMoveJob(conn, req, manager)
	case "cups.printTestPage":
		handlePrintTestPage(conn, req, manager)
	case "cups.addPrinterToClass":
		handleAddPrinterToClass(conn, req, manager)
	case "cups.removePrinterFromClass":
		handleRemovePrinterFromClass(conn, req, manager)
	case "cups.deleteClass":
		handleDeleteClass(conn, req, manager)
	case "cups.restartJob":
		handleRestartJob(conn, req, manager)
	case "cups.holdJob":
		handleHoldJob(conn, req, manager)
	case "cups.testConnection":
		handleTestConnection(conn, req, manager)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetPrinters(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printers, err := manager.GetPrinters()
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, printers)
}

func handleGetJobs(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.String(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	jobs, err := manager.GetJobs(printerName, "not-completed")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, jobs)
}

func handlePausePrinter(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.String(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.PausePrinter(printerName); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "paused"})
}

func handleResumePrinter(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.String(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.ResumePrinter(printerName); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "resumed"})
}

func handleCancelJob(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	jobID, err := params.Int(req.Params, "jobID")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.CancelJob(jobID); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "job canceled"})
}

func handlePurgeJobs(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.String(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.PurgeJobs(printerName); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "jobs canceled"})
}

func handleSubscribe(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	clientID := fmt.Sprintf("client-%p", conn)
	stateChan := manager.Subscribe(clientID)
	defer manager.Unsubscribe(clientID)

	initialState := manager.GetState()
	event := CUPSEvent{
		Type: "state_changed",
		Data: initialState,
	}

	if err := conn.WriteResponse(ipc.Response[CUPSEvent]{
		ID:     req.ID,
		Result: &event,
	}); err != nil {
		return
	}

	for state := range stateChan {
		event := CUPSEvent{
			Type: "state_changed",
			Data: state,
		}
		if err := conn.WriteResponse(ipc.Response[CUPSEvent]{
			Result: &event,
		}); err != nil {
			return
		}
	}
}

func handleGetDevices(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	devices, err := manager.GetDevices()
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, devices)
}

func handleGetPPDs(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	ppds, err := manager.GetPPDs()
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, ppds)
}

func handleGetClasses(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	classes, err := manager.GetClasses()
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, classes)
}

func handleCreatePrinter(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	name, err := params.StringNonEmpty(req.Params, "name")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	deviceURI, err := params.StringNonEmpty(req.Params, "deviceURI")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	ppd, err := params.StringNonEmpty(req.Params, "ppd")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	shared := params.BoolOpt(req.Params, "shared", false)
	errorPolicy := params.StringOpt(req.Params, "errorPolicy", "")
	information := params.StringOpt(req.Params, "information", "")
	location := params.StringOpt(req.Params, "location", "")

	if err := manager.CreatePrinter(name, deviceURI, ppd, shared, errorPolicy, information, location); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "printer created"})
}

func handleDeletePrinter(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.StringNonEmpty(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.DeletePrinter(printerName); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "printer deleted"})
}

func handleAcceptJobs(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.StringNonEmpty(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.AcceptJobs(printerName); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "accepting jobs"})
}

func handleRejectJobs(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.StringNonEmpty(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.RejectJobs(printerName); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "rejecting jobs"})
}

func handleSetPrinterShared(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.StringNonEmpty(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	shared, err := params.Bool(req.Params, "shared")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.SetPrinterShared(printerName, shared); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "sharing updated"})
}

func handleSetPrinterLocation(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.StringNonEmpty(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	location, err := params.String(req.Params, "location")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.SetPrinterLocation(printerName, location); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "location updated"})
}

func handleSetPrinterInfo(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.StringNonEmpty(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	info, err := params.String(req.Params, "info")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.SetPrinterInfo(printerName, info); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "info updated"})
}

func handleMoveJob(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	jobID, err := params.Int(req.Params, "jobID")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	destPrinter, err := params.StringNonEmpty(req.Params, "destPrinter")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.MoveJob(jobID, destPrinter); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "job moved"})
}

func handlePrintTestPage(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	printerName, err := params.StringNonEmpty(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	jobID, err := manager.PrintTestPage(printerName)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, TestPageResult{Success: true, JobID: jobID, Message: "test page queued"})
}

func handleAddPrinterToClass(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	className, err := params.StringNonEmpty(req.Params, "className")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	printerName, err := params.StringNonEmpty(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.AddPrinterToClass(className, printerName); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "printer added to class"})
}

func handleRemovePrinterFromClass(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	className, err := params.StringNonEmpty(req.Params, "className")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	printerName, err := params.StringNonEmpty(req.Params, "printerName")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.RemovePrinterFromClass(className, printerName); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "printer removed from class"})
}

func handleDeleteClass(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	className, err := params.StringNonEmpty(req.Params, "className")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.DeleteClass(className); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "class deleted"})
}

func handleRestartJob(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	jobID, err := params.Int(req.Params, "jobID")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.RestartJob(jobID); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "job restarted"})
}

func handleHoldJob(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	jobID, err := params.Int(req.Params, "jobID")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	holdUntil := params.StringOpt(req.Params, "holdUntil", "indefinite")

	if err := manager.HoldJob(jobID, holdUntil); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "job held"})
}

func handleTestConnection(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	host, err := params.StringNonEmpty(req.Params, "host")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	port := params.IntOpt(req.Params, "port", 631)
	protocol := params.StringOpt(req.Params, "protocol", "ipp")

	result, err := manager.TestRemotePrinter(host, port, protocol)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, result)
}
