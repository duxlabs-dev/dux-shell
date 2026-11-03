package cups

import (
	"fmt"
	"strings"
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/pkg/ipp"
	"github.com/godbus/dbus/v5"
)

var cupsNotifierMatch = dbus.WithMatchInterface("org.cups.cupsd.Notifier")

type DBusSubscriptionManager struct {
	client         CUPSClientInterface
	subscriptionID int
	eventChan      chan SubscriptionEvent
	stopChan       chan struct{}
	wg             sync.WaitGroup
	baseURL        string
	running        bool
	mu             sync.Mutex
	conn           *dbus.Conn
}

func NewDBusSubscriptionManager(client CUPSClientInterface, baseURL string) *DBusSubscriptionManager {
	return &DBusSubscriptionManager{
		client:    client,
		eventChan: make(chan SubscriptionEvent, 100),
		stopChan:  make(chan struct{}),
		baseURL:   baseURL,
	}
}

func (sm *DBusSubscriptionManager) Start() error {
	sm.mu.Lock()
	if sm.running {
		sm.mu.Unlock()
		return fmt.Errorf("subscription manager already running")
	}
	sm.running = true
	// replaced here rather than in Stop(); see SubscriptionManager.Start()
	sm.eventChan = make(chan SubscriptionEvent, 100)
	sm.mu.Unlock()

	conn, err := dbus.SystemBus()
	if err != nil {
		sm.mu.Lock()
		sm.running = false
		sm.mu.Unlock()
		return fmt.Errorf("connect to system bus: %w", err)
	}
	sm.conn = conn

	subID, err := sm.createDBusSubscription()
	if err != nil {
		sm.mu.Lock()
		sm.running = false
		sm.mu.Unlock()
		return fmt.Errorf("failed to create D-Bus subscription: %w", err)
	}

	sm.subscriptionID = subID
	log.Infof("[CUPS] Created D-Bus subscription with ID %d", subID)

	if err := sm.conn.AddMatchSignal(cupsNotifierMatch); err != nil {
		sm.cancelSubscription()
		sm.mu.Lock()
		sm.running = false
		sm.mu.Unlock()
		return fmt.Errorf("failed to add D-Bus match: %w", err)
	}

	sm.wg.Add(1)
	go sm.dbusListenerLoop()

	return nil
}

func (sm *DBusSubscriptionManager) createDBusSubscription() (int, error) {
	req := ipp.NewRequest(ipp.OperationCreatePrinterSubscriptions, 2)
	req.OperationAttributes[ipp.AttributePrinterURI] = fmt.Sprintf("%s/", sm.baseURL)
	req.OperationAttributes[ipp.AttributeRequestingUserName] = "dms"

	req.SubscriptionAttributes = map[string]any{
		"notify-events": []string{
			"printer-state-changed",
			"printer-added",
			"printer-deleted",
			"job-created",
			"job-completed",
			"job-state-changed",
		},
		"notify-recipient-uri":  "dbus:/",
		"notify-lease-duration": 86400,
	}

	resp, err := sm.client.SendRequest(fmt.Sprintf("%s/", sm.baseURL), req, nil)
	if err != nil {
		return 0, fmt.Errorf("SendRequest failed: %w", err)
	}

	if err := resp.CheckForErrors(); err != nil {
		return 0, fmt.Errorf("IPP error: %w", err)
	}

	if len(resp.SubscriptionAttributes) > 0 {
		if idAttr, ok := resp.SubscriptionAttributes[0]["notify-subscription-id"]; ok && len(idAttr) > 0 {
			if val, ok := idAttr[0].Value.(int); ok {
				return val, nil
			}
		}
	}

	return 0, fmt.Errorf("no subscription ID returned")
}

func (sm *DBusSubscriptionManager) dbusListenerLoop() {
	defer sm.wg.Done()

	signalChan := make(chan *dbus.Signal, 10)
	sm.conn.Signal(signalChan)
	defer sm.conn.RemoveSignal(signalChan)

	for {
		select {
		case <-sm.stopChan:
			return
		case sig := <-signalChan:
			if sig == nil {
				continue
			}

			event := sm.parseDBusSignal(sig)
			if event.EventName == "" {
				continue
			}

			select {
			case sm.eventChan <- event:
			case <-sm.stopChan:
				return
			default:
				log.Warn("[CUPS] Event channel full, dropping event")
			}
		}
	}
}

func (sm *DBusSubscriptionManager) parseDBusSignal(sig *dbus.Signal) SubscriptionEvent {
	event := SubscriptionEvent{}

	switch sig.Name {
	case "org.cups.cupsd.Notifier.JobStateChanged":
		if len(sig.Body) >= 6 {
			if text, ok := sig.Body[0].(string); ok {
				event.EventName = "job-state-changed"
				parts := strings.Split(text, " ")
				if len(parts) >= 2 {
					event.PrinterName = parts[0]
				}
			}
			if printerURI, ok := sig.Body[1].(string); ok && event.PrinterName == "" {
				if idx := strings.LastIndex(printerURI, "/"); idx != -1 {
					event.PrinterName = printerURI[idx+1:]
				}
			}
			if jobID, ok := sig.Body[3].(uint32); ok {
				event.JobID = int(jobID)
			}
		}

	case "org.cups.cupsd.Notifier.JobCreated":
		if len(sig.Body) >= 6 {
			if text, ok := sig.Body[0].(string); ok {
				event.EventName = "job-created"
				parts := strings.Split(text, " ")
				if len(parts) >= 2 {
					event.PrinterName = parts[0]
				}
			}
			if printerURI, ok := sig.Body[1].(string); ok && event.PrinterName == "" {
				if idx := strings.LastIndex(printerURI, "/"); idx != -1 {
					event.PrinterName = printerURI[idx+1:]
				}
			}
			if jobID, ok := sig.Body[3].(uint32); ok {
				event.JobID = int(jobID)
			}
		}

	case "org.cups.cupsd.Notifier.JobCompleted":
		if len(sig.Body) >= 6 {
			if text, ok := sig.Body[0].(string); ok {
				event.EventName = "job-completed"
				parts := strings.Split(text, " ")
				if len(parts) >= 2 {
					event.PrinterName = parts[0]
				}
			}
			if printerURI, ok := sig.Body[1].(string); ok && event.PrinterName == "" {
				if idx := strings.LastIndex(printerURI, "/"); idx != -1 {
					event.PrinterName = printerURI[idx+1:]
				}
			}
			if jobID, ok := sig.Body[3].(uint32); ok {
				event.JobID = int(jobID)
			}
		}

	case "org.cups.cupsd.Notifier.PrinterStateChanged":
		if len(sig.Body) >= 6 {
			if text, ok := sig.Body[0].(string); ok {
				event.EventName = "printer-state-changed"
				parts := strings.Split(text, " ")
				if len(parts) >= 2 {
					event.PrinterName = parts[0]
				}
			}
			if printerURI, ok := sig.Body[1].(string); ok && event.PrinterName == "" {
				if idx := strings.LastIndex(printerURI, "/"); idx != -1 {
					event.PrinterName = printerURI[idx+1:]
				}
			}
		}

	case "org.cups.cupsd.Notifier.PrinterAdded":
		if len(sig.Body) >= 6 {
			if text, ok := sig.Body[0].(string); ok {
				event.EventName = "printer-added"
				parts := strings.Split(text, " ")
				if len(parts) >= 2 {
					event.PrinterName = parts[0]
				}
			}
		}

	case "org.cups.cupsd.Notifier.PrinterDeleted":
		if len(sig.Body) >= 6 {
			if text, ok := sig.Body[0].(string); ok {
				event.EventName = "printer-deleted"
				parts := strings.Split(text, " ")
				if len(parts) >= 2 {
					event.PrinterName = parts[0]
				}
			}
		}
	}

	return event
}

func (sm *DBusSubscriptionManager) Events() <-chan SubscriptionEvent {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	return sm.eventChan
}

func (sm *DBusSubscriptionManager) Stop() {
	sm.mu.Lock()
	if !sm.running {
		sm.mu.Unlock()
		return
	}
	sm.running = false
	sm.mu.Unlock()

	close(sm.stopChan)
	sm.wg.Wait()

	if sm.subscriptionID != 0 {
		sm.cancelSubscription()
		sm.subscriptionID = 0
	}

	if sm.conn != nil {
		_ = sm.conn.RemoveMatchSignal(cupsNotifierMatch)
		sm.conn = nil
	}

	sm.stopChan = make(chan struct{})

	// the writer (dbusListenerLoop) joined above, so closing is safe; see
	// SubscriptionManager.Stop()
	sm.mu.Lock()
	close(sm.eventChan)
	sm.mu.Unlock()
}

func (sm *DBusSubscriptionManager) cancelSubscription() {
	req := ipp.NewRequest(ipp.OperationCancelSubscription, 1)
	req.OperationAttributes[ipp.AttributePrinterURI] = fmt.Sprintf("%s/", sm.baseURL)
	req.OperationAttributes[ipp.AttributeRequestingUserName] = "dms"
	req.OperationAttributes["notify-subscription-id"] = sm.subscriptionID

	_, err := sm.client.SendRequest(fmt.Sprintf("%s/", sm.baseURL), req, nil)
	if err != nil {
		log.Warnf("[CUPS] Failed to cancel subscription %d: %v", sm.subscriptionID, err)
	} else {
		log.Infof("[CUPS] Cancelled subscription %d", sm.subscriptionID)
	}
}
