package cups

import (
	"fmt"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/pkg/ipp"
)

type SubscriptionManager struct {
	client         CUPSClientInterface
	subscriptionID int
	sequenceNumber int
	eventChan      chan SubscriptionEvent
	stopChan       chan struct{}
	wg             sync.WaitGroup
	baseURL        string
	running        bool
	mu             sync.Mutex
}

func NewSubscriptionManager(client CUPSClientInterface, baseURL string) *SubscriptionManager {
	return &SubscriptionManager{
		client:    client,
		eventChan: make(chan SubscriptionEvent, 100),
		stopChan:  make(chan struct{}),
		baseURL:   baseURL,
	}
}

func (sm *SubscriptionManager) Start() error {
	sm.mu.Lock()
	if sm.running {
		sm.mu.Unlock()
		return fmt.Errorf("subscription manager already running")
	}
	sm.running = true
	// replace the channel closed by the previous Stop(); doing it here rather
	// than in Stop() guarantees a lagging eventHandler still observes the close
	sm.eventChan = make(chan SubscriptionEvent, 100)
	sm.mu.Unlock()

	subID, err := sm.createSubscription()
	if err != nil {
		sm.mu.Lock()
		sm.running = false
		sm.mu.Unlock()
		return fmt.Errorf("failed to create subscription: %w", err)
	}

	sm.subscriptionID = subID
	log.Infof("[CUPS] Created IPP subscription with ID %d", subID)

	sm.wg.Add(1)
	go sm.notificationLoop()

	return nil
}

func (sm *SubscriptionManager) createSubscription() (int, error) {
	req := ipp.NewRequest(ipp.OperationCreatePrinterSubscriptions, 1)
	req.OperationAttributes[ipp.AttributePrinterURI] = fmt.Sprintf("%s/", sm.baseURL)
	req.OperationAttributes[ipp.AttributeRequestingUserName] = "dms"

	// Subscription attributes go in SubscriptionAttributes (subscription-attributes-tag in IPP)
	req.SubscriptionAttributes = map[string]any{
		"notify-events": []string{
			"printer-state-changed",
			"printer-added",
			"printer-deleted",
			"job-created",
			"job-completed",
			"job-state-changed",
		},
		"notify-pull-method":    "ippget",
		"notify-lease-duration": 0,
	}

	// Send to root IPP endpoint
	resp, err := sm.client.SendRequest(fmt.Sprintf("%s/", sm.baseURL), req, nil)
	if err != nil {
		return 0, fmt.Errorf("SendRequest failed: %w", err)
	}

	// Check for IPP errors
	if err := resp.CheckForErrors(); err != nil {
		return 0, fmt.Errorf("IPP error: %w", err)
	}

	// Subscription ID comes back in SubscriptionAttributes
	if len(resp.SubscriptionAttributes) > 0 {
		if idAttr, ok := resp.SubscriptionAttributes[0]["notify-subscription-id"]; ok && len(idAttr) > 0 {
			if val, ok := idAttr[0].Value.(int); ok {
				return val, nil
			}
		}
	}

	return 0, fmt.Errorf("no subscription ID returned")
}

func (sm *SubscriptionManager) notificationLoop() {
	defer sm.wg.Done()

	backoff := 1 * time.Second

	for {
		select {
		case <-sm.stopChan:
			return
		default:
		}

		gotAny, err := sm.fetchNotificationsWithWait()
		if err != nil {
			log.Warnf("[CUPS] Error fetching notifications: %v", err)
			jitter := time.Duration(50+(time.Now().UnixNano()%200)) * time.Millisecond
			sleepTime := min(backoff+jitter, 30*time.Second)
			select {
			case <-sm.stopChan:
				return
			case <-time.After(sleepTime):
			}
			if backoff < 30*time.Second {
				backoff *= 2
			}
			continue
		}

		backoff = 1 * time.Second

		if gotAny {
			continue
		}

		select {
		case <-sm.stopChan:
			return
		case <-time.After(2 * time.Second):
		}
	}
}

func (sm *SubscriptionManager) fetchNotificationsWithWait() (bool, error) {
	req := ipp.NewRequest(ipp.OperationGetNotifications, 1)
	req.OperationAttributes[ipp.AttributePrinterURI] = fmt.Sprintf("%s/", sm.baseURL)
	req.OperationAttributes[ipp.AttributeRequestingUserName] = "dms"
	req.OperationAttributes["notify-subscription-ids"] = sm.subscriptionID
	if sm.sequenceNumber > 0 {
		req.OperationAttributes["notify-sequence-numbers"] = sm.sequenceNumber
	}

	resp, err := sm.client.SendRequest(fmt.Sprintf("%s/", sm.baseURL), req, nil)
	if err != nil {
		return false, err
	}

	gotAny := false
	for _, eventGroup := range resp.SubscriptionAttributes {
		if seqAttr, ok := eventGroup["notify-sequence-number"]; ok && len(seqAttr) > 0 {
			if seqNum, ok := seqAttr[0].Value.(int); ok {
				sm.sequenceNumber = seqNum + 1
			}
		}

		event := sm.parseEvent(eventGroup)
		gotAny = true
		select {
		case sm.eventChan <- event:
		case <-sm.stopChan:
			return gotAny, nil
		default:
			log.Warn("[CUPS] Event channel full, dropping event")
		}
	}

	return gotAny, nil
}

func (sm *SubscriptionManager) parseEvent(attrs ipp.Attributes) SubscriptionEvent {
	event := SubscriptionEvent{
		SubscribedAt: time.Now(),
	}

	if attr, ok := attrs["notify-subscribed-event"]; ok && len(attr) > 0 {
		if val, ok := attr[0].Value.(string); ok {
			event.EventName = val
		}
	}

	if attr, ok := attrs["printer-name"]; ok && len(attr) > 0 {
		if val, ok := attr[0].Value.(string); ok {
			event.PrinterName = val
		}
	}

	if attr, ok := attrs["notify-job-id"]; ok && len(attr) > 0 {
		if val, ok := attr[0].Value.(int); ok {
			event.JobID = val
		}
	}

	return event
}

func (sm *SubscriptionManager) Events() <-chan SubscriptionEvent {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	return sm.eventChan
}

func (sm *SubscriptionManager) Stop() {
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
		sm.sequenceNumber = 0
	}

	sm.stopChan = make(chan struct{})

	// the writer (notificationLoop) joined above, so closing is safe; without
	// this close Manager.eventHandler never returns and Unsubscribe deadlocks
	// on eventWG.Wait(). Start() allocates the replacement.
	sm.mu.Lock()
	close(sm.eventChan)
	sm.mu.Unlock()
}

func (sm *SubscriptionManager) cancelSubscription() {
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
