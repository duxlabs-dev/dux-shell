package cups

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/pkg/ipp"
)

func NewManager() (*Manager, error) {
	host := os.Getenv("DMS_IPP_HOST")
	if host == "" {
		host = "localhost"
	}

	portStr := os.Getenv("DMS_IPP_PORT")
	port := 631
	if portStr != "" {
		if p, err := strconv.Atoi(portStr); err == nil {
			port = p
		}
	}

	username := os.Getenv("DMS_IPP_USERNAME")
	password := os.Getenv("DMS_IPP_PASSWORD")

	client := ipp.NewCUPSClient(host, port, username, password, false)
	baseURL := fmt.Sprintf("http://%s:%d", host, port)

	var pkHelper PkHelper
	if isLocalCUPS(host) {
		var err error
		pkHelper, err = NewPkHelper()
		if err != nil {
			log.Warnf("[CUPS] Failed to initialize pkhelper: %v", err)
		}
	}

	m := &Manager{
		state: &CUPSState{
			Printers: make(map[string]*Printer),
		},
		client:     client,
		pkHelper:   pkHelper,
		baseURL:    baseURL,
		stateMutex: sync.RWMutex{},
		stopChan:   make(chan struct{}),
		dirty:      make(chan struct{}, 1),
	}

	if err := m.updateState(); err != nil {
		return nil, err
	}

	if isLocalCUPS(host) {
		m.subscription = NewDBusSubscriptionManager(client, baseURL)
		log.Infof("[CUPS] Using D-Bus notifications for local CUPS")
	} else {
		m.subscription = NewSubscriptionManager(client, baseURL)
		log.Infof("[CUPS] Using IPPGET notifications for remote CUPS")
	}

	m.notifierWg.Add(1)
	go m.notifier()

	return m, nil
}

func isLocalCUPS(host string) bool {
	switch host {
	case "localhost", "127.0.0.1", "::1", "":
		return true
	}
	return false
}

func (m *Manager) eventHandler() {
	defer m.eventWG.Done()

	if m.subscription == nil {
		return
	}

	for {
		select {
		case <-m.stopChan:
			return
		case event, ok := <-m.subscription.Events():
			if !ok {
				return
			}
			log.Debugf("[CUPS] Received event: %s (printer: %s, job: %d)",
				event.EventName, event.PrinterName, event.JobID)

			if err := m.updateState(); err != nil {
				log.Warnf("[CUPS] Failed to update state after event: %v", err)
			} else {
				m.notifySubscribers()
			}
		}
	}
}

func (m *Manager) updateState() error {
	printers, err := m.GetPrinters()
	if err != nil {
		if isNoPrintersError(err) {
			m.stateMutex.Lock()
			m.state.Printers = make(map[string]*Printer)
			m.stateMutex.Unlock()
			return nil
		}
		return err
	}

	printerMap := make(map[string]*Printer, len(printers))
	for _, printer := range printers {
		jobs, err := m.GetJobs(printer.Name, "not-completed")
		if err != nil {
			return err
		}

		printer.Jobs = jobs
		printerMap[printer.Name] = &printer
	}

	m.stateMutex.Lock()
	m.state.Printers = printerMap
	m.stateMutex.Unlock()

	return nil
}

func isNoPrintersError(err error) bool {
	if err == nil {
		return false
	}

	if ippErr, ok := errors.AsType[ipp.IPPError](err); ok {
		return ippErr.Status == 1030
	}

	return false
}

func (m *Manager) notifier() {
	defer m.notifierWg.Done()
	const minGap = 100 * time.Millisecond
	timer := time.NewTimer(minGap)
	timer.Stop()
	var pending bool
	for {
		select {
		case <-m.stopChan:
			timer.Stop()
			return
		case <-m.dirty:
			if pending {
				continue
			}
			pending = true
			timer.Reset(minGap)
		case <-timer.C:
			if !pending {
				continue
			}

			currentState := m.snapshotState()

			if m.lastNotifiedState != nil && !stateChanged(m.lastNotifiedState, &currentState) {
				pending = false
				continue
			}

			m.subscribers.Range(func(key string, ch chan CUPSState) bool {
				select {
				case ch <- currentState:
				default:
				}
				return true
			})

			stateCopy := currentState
			m.lastNotifiedState = &stateCopy
			pending = false
		}
	}
}

func (m *Manager) notifySubscribers() {
	select {
	case m.dirty <- struct{}{}:
	default:
	}
}

func (m *Manager) RefreshState() {
	if err := m.updateState(); err != nil {
		log.Warnf("[CUPS] Failed to refresh state: %v", err)
		return
	}
	m.notifySubscribers()
}

func (m *Manager) GetState() CUPSState {
	return m.snapshotState()
}

func (m *Manager) snapshotState() CUPSState {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()

	s := CUPSState{
		Printers: make(map[string]*Printer, len(m.state.Printers)),
	}
	for name, printer := range m.state.Printers {
		printerCopy := *printer
		s.Printers[name] = &printerCopy
	}
	return s
}

func (m *Manager) Subscribe(id string) chan CUPSState {
	ch := make(chan CUPSState, 64)

	m.subLifecycleMu.Lock()
	defer m.subLifecycleMu.Unlock()

	wasEmpty := true
	m.subscribers.Range(func(key string, ch chan CUPSState) bool {
		wasEmpty = false
		return false
	})

	m.subscribers.Store(id, ch)

	if !wasEmpty || m.subscription == nil {
		return ch
	}

	if err := m.subscription.Start(); err != nil {
		log.Warnf("[CUPS] Failed to start subscription manager: %v", err)
		return ch
	}

	m.eventWG.Add(1)
	go m.eventHandler()

	return ch
}

func (m *Manager) Unsubscribe(id string) {
	m.subLifecycleMu.Lock()
	defer m.subLifecycleMu.Unlock()

	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}

	isEmpty := true
	m.subscribers.Range(func(key string, ch chan CUPSState) bool {
		isEmpty = false
		return false
	})

	if !isEmpty || m.subscription == nil {
		return
	}

	m.subscription.Stop()
	m.eventWG.Wait()
}

func (m *Manager) Close() {
	close(m.stopChan)

	m.subLifecycleMu.Lock()
	if m.subscription != nil {
		m.subscription.Stop()
	}
	m.subLifecycleMu.Unlock()

	m.eventWG.Wait()
	m.notifierWg.Wait()

	m.subscribers.Range(func(key string, ch chan CUPSState) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
}

func stateChanged(old, new *CUPSState) bool {
	if len(old.Printers) != len(new.Printers) {
		return true
	}
	for name, oldPrinter := range old.Printers {
		newPrinter, exists := new.Printers[name]
		if !exists {
			return true
		}
		if oldPrinter.State != newPrinter.State ||
			oldPrinter.StateReason != newPrinter.StateReason ||
			oldPrinter.Accepting != newPrinter.Accepting ||
			len(oldPrinter.Jobs) != len(newPrinter.Jobs) {
			return true
		}
	}
	return false
}

func parsePrinterState(attrs ipp.Attributes) string {
	if stateAttr, ok := attrs[ipp.AttributePrinterState]; ok && len(stateAttr) > 0 {
		if state, ok := stateAttr[0].Value.(int); ok {
			switch state {
			case 3:
				return "idle"
			case 4:
				return "processing"
			case 5:
				return "stopped"
			default:
				return fmt.Sprintf("%d", state)
			}
		}
	}
	return "unknown"
}

func parseJobState(attrs ipp.Attributes) string {
	if stateAttr, ok := attrs[ipp.AttributeJobState]; ok && len(stateAttr) > 0 {
		if state, ok := stateAttr[0].Value.(int); ok {
			switch state {
			case 3:
				return "pending"
			case 4:
				return "pending-held"
			case 5:
				return "processing"
			case 6:
				return "processing-stopped"
			case 7:
				return "canceled"
			case 8:
				return "aborted"
			case 9:
				return "completed"
			default:
				return fmt.Sprintf("%d", state)
			}
		}
	}
	return "unknown"
}

func getStringAttr(attrs ipp.Attributes, key string) string {
	if attr, ok := attrs[key]; ok && len(attr) > 0 {
		if val, ok := attr[0].Value.(string); ok {
			return val
		}
		return fmt.Sprintf("%v", attr[0].Value)
	}
	return ""
}

func getIntAttr(attrs ipp.Attributes, key string) int {
	if attr, ok := attrs[key]; ok && len(attr) > 0 {
		if val, ok := attr[0].Value.(int); ok {
			return val
		}
	}
	return 0
}

func getBoolAttr(attrs ipp.Attributes, key string) bool {
	if attr, ok := attrs[key]; ok && len(attr) > 0 {
		if val, ok := attr[0].Value.(bool); ok {
			return val
		}
	}
	return false
}

func getStringSliceAttr(attrs ipp.Attributes, key string) []string {
	attr, ok := attrs[key]
	if !ok {
		return nil
	}

	result := make([]string, 0, len(attr))
	for _, a := range attr {
		if val, ok := a.Value.(string); ok {
			result = append(result, val)
		}
	}
	return result
}
