package wlroutput

import (
	"fmt"
	"time"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_output_management"
)

func NewManager(display wlclient.WaylandDisplay) (*Manager, error) {
	m := &Manager{
		display:    display,
		ctx:        display.Context(),
		cmdq:       make(chan cmd, 512),
		stopChan:   make(chan struct{}),
		dirty:      make(chan struct{}, 1),
		fatalError: make(chan error, 1),
	}

	m.wg.Add(1)
	go m.waylandActor()

	if err := m.setupRegistry(); err != nil {
		close(m.stopChan)
		m.wg.Wait()
		return nil, err
	}

	m.updateState()

	m.notifierWg.Add(1)
	go m.notifier()

	return m, nil
}

func (m *Manager) post(fn func()) {
	select {
	case m.cmdq <- cmd{fn: fn}:
	default:
		log.Warn("WlrOutput actor command queue full, dropping command")
	}
}

func (m *Manager) waylandActor() {
	defer m.wg.Done()
	defer func() {
		if r := recover(); r != nil {
			err := fmt.Errorf("waylandActor panic: %v", r)
			log.Errorf("WlrOutput: %v", err)

			select {
			case m.fatalError <- err:
			default:
			}

			select {
			case <-m.stopChan:
			default:
				close(m.stopChan)
			}
		}
	}()

	for {
		select {
		case <-m.stopChan:
			return
		case c := <-m.cmdq:
			func() {
				defer func() {
					if r := recover(); r != nil {
						log.Errorf("WlrOutput: command execution panic: %v", r)
					}
				}()
				c.fn()
			}()
		}
	}
}

func (m *Manager) setupRegistry() error {
	log.Info("WlrOutput: starting registry setup")

	registry, err := m.display.GetRegistry()
	if err != nil {
		return fmt.Errorf("failed to get registry: %w", err)
	}
	m.registry = registry

	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		if e.Interface == wlr_output_management.ZwlrOutputManagerV1InterfaceName {
			log.Infof("WlrOutput: found %s", wlr_output_management.ZwlrOutputManagerV1InterfaceName)
			manager := wlr_output_management.NewZwlrOutputManagerV1(m.ctx)
			version := min(e.Version, 4)

			manager.SetHeadHandler(func(e wlr_output_management.ZwlrOutputManagerV1HeadEvent) {
				m.handleHead(e)
			})

			manager.SetDoneHandler(func(e wlr_output_management.ZwlrOutputManagerV1DoneEvent) {
				log.Debugf("WlrOutput: done event received (serial=%d)", e.Serial)
				m.serial = e.Serial
				m.post(func() {
					m.updateState()
				})
			})

			manager.SetFinishedHandler(func(e wlr_output_management.ZwlrOutputManagerV1FinishedEvent) {
				log.Info("WlrOutput: finished event received")
			})

			if err := registry.Bind(e.Name, e.Interface, version, manager); err == nil {
				m.manager = manager
				log.Info("WlrOutput: manager bound successfully")
			} else {
				log.Errorf("WlrOutput: failed to bind manager: %v", err)
			}
		}
	})

	log.Info("WlrOutput: registry setup complete (events will be processed async)")
	return nil
}

func (m *Manager) handleHead(e wlr_output_management.ZwlrOutputManagerV1HeadEvent) {
	handle := e.Head
	headID := handle.ID()

	log.Debugf("WlrOutput: New head (id=%d)", headID)

	head := &headState{
		id:      headID,
		handle:  handle,
		modeIDs: make([]uint32, 0),
	}

	m.heads.Store(headID, head)

	handle.SetNameHandler(func(e wlr_output_management.ZwlrOutputHeadV1NameEvent) {
		log.Debugf("WlrOutput: Head %d name: %s", headID, e.Name)
		head.name = e.Name
		head.ready = true
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetDescriptionHandler(func(e wlr_output_management.ZwlrOutputHeadV1DescriptionEvent) {
		log.Debugf("WlrOutput: Head %d description: %s", headID, e.Description)
		head.description = e.Description
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetPhysicalSizeHandler(func(e wlr_output_management.ZwlrOutputHeadV1PhysicalSizeEvent) {
		log.Debugf("WlrOutput: Head %d physical size: %dx%d", headID, e.Width, e.Height)
		head.physicalWidth = e.Width
		head.physicalHeight = e.Height
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetModeHandler(func(e wlr_output_management.ZwlrOutputHeadV1ModeEvent) {
		m.handleMode(headID, e)
	})

	handle.SetEnabledHandler(func(e wlr_output_management.ZwlrOutputHeadV1EnabledEvent) {
		log.Debugf("WlrOutput: Head %d enabled: %d", headID, e.Enabled)
		head.enabled = e.Enabled != 0
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetCurrentModeHandler(func(e wlr_output_management.ZwlrOutputHeadV1CurrentModeEvent) {
		modeID := e.Mode.ID()
		log.Debugf("WlrOutput: Head %d current mode: %d", headID, modeID)
		head.currentModeID = modeID
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetPositionHandler(func(e wlr_output_management.ZwlrOutputHeadV1PositionEvent) {
		log.Debugf("WlrOutput: Head %d position: %d,%d", headID, e.X, e.Y)
		head.x = e.X
		head.y = e.Y
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetTransformHandler(func(e wlr_output_management.ZwlrOutputHeadV1TransformEvent) {
		log.Debugf("WlrOutput: Head %d transform: %d", headID, e.Transform)
		head.transform = e.Transform
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetScaleHandler(func(e wlr_output_management.ZwlrOutputHeadV1ScaleEvent) {
		log.Debugf("WlrOutput: Head %d scale: %f", headID, e.Scale)
		head.scale = e.Scale
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetMakeHandler(func(e wlr_output_management.ZwlrOutputHeadV1MakeEvent) {
		log.Debugf("WlrOutput: Head %d make: %s", headID, e.Make)
		head.make = e.Make
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetModelHandler(func(e wlr_output_management.ZwlrOutputHeadV1ModelEvent) {
		log.Debugf("WlrOutput: Head %d model: %s", headID, e.Model)
		head.model = e.Model
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetSerialNumberHandler(func(e wlr_output_management.ZwlrOutputHeadV1SerialNumberEvent) {
		log.Debugf("WlrOutput: Head %d serial: %s", headID, e.SerialNumber)
		head.serialNumber = e.SerialNumber
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetAdaptiveSyncHandler(func(e wlr_output_management.ZwlrOutputHeadV1AdaptiveSyncEvent) {
		log.Debugf("WlrOutput: Head %d adaptive sync: %d", headID, e.State)
		head.adaptiveSync = e.State
		head.adaptiveSyncSupported = true
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetFinishedHandler(func(e wlr_output_management.ZwlrOutputHeadV1FinishedEvent) {
		log.Debugf("WlrOutput: Head %d finished", headID)
		head.finished = true

		m.heads.Delete(headID)

		m.wlMutex.Lock()
		handle.Release()
		m.wlMutex.Unlock()

		m.post(func() {
			m.updateState()
		})
	})
}

func (m *Manager) handleMode(headID uint32, e wlr_output_management.ZwlrOutputHeadV1ModeEvent) {
	handle := e.Mode
	modeID := handle.ID()

	log.Debugf("WlrOutput: Head %d new mode (id=%d)", headID, modeID)

	mode := &modeState{
		id:     modeID,
		handle: handle,
	}

	m.modes.Store(modeID, mode)

	if head, ok := m.heads.Load(headID); ok {
		head.modeIDs = append(head.modeIDs, modeID)
		m.heads.Store(headID, head)
	}

	handle.SetSizeHandler(func(e wlr_output_management.ZwlrOutputModeV1SizeEvent) {
		log.Debugf("WlrOutput: Mode %d size: %dx%d", modeID, e.Width, e.Height)
		mode.width = e.Width
		mode.height = e.Height
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetRefreshHandler(func(e wlr_output_management.ZwlrOutputModeV1RefreshEvent) {
		log.Debugf("WlrOutput: Mode %d refresh: %d", modeID, e.Refresh)
		mode.refresh = e.Refresh
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetPreferredHandler(func(e wlr_output_management.ZwlrOutputModeV1PreferredEvent) {
		log.Debugf("WlrOutput: Mode %d preferred", modeID)
		mode.preferred = true
		m.post(func() {
			m.updateState()
		})
	})

	handle.SetFinishedHandler(func(e wlr_output_management.ZwlrOutputModeV1FinishedEvent) {
		log.Debugf("WlrOutput: Mode %d finished", modeID)
		mode.finished = true

		m.modes.Delete(modeID)

		m.wlMutex.Lock()
		handle.Release()
		m.wlMutex.Unlock()

		m.post(func() {
			m.updateState()
		})
	})
}

func (m *Manager) updateState() {
	outputs := make([]Output, 0)

	m.heads.Range(func(key uint32, head *headState) bool {
		if head.finished {
			return true
		}

		if !head.ready {
			return true
		}

		modes := make([]OutputMode, 0)
		var currentMode *OutputMode

		for _, modeID := range head.modeIDs {
			mode, exists := m.modes.Load(modeID)
			if !exists {
				continue
			}
			if mode.finished {
				continue
			}

			outMode := OutputMode{
				Width:     mode.width,
				Height:    mode.height,
				Refresh:   mode.refresh,
				Preferred: mode.preferred,
				ID:        modeID,
			}
			modes = append(modes, outMode)

			if modeID == head.currentModeID {
				currentMode = &outMode
			}
		}

		output := Output{
			Name:                  head.name,
			Description:           head.description,
			Make:                  head.make,
			Model:                 head.model,
			SerialNumber:          head.serialNumber,
			PhysicalWidth:         head.physicalWidth,
			PhysicalHeight:        head.physicalHeight,
			Enabled:               head.enabled,
			X:                     head.x,
			Y:                     head.y,
			Transform:             head.transform,
			Scale:                 head.scale,
			CurrentMode:           currentMode,
			Modes:                 modes,
			AdaptiveSync:          head.adaptiveSync,
			AdaptiveSyncSupported: head.adaptiveSyncSupported,
			ID:                    head.id,
		}
		outputs = append(outputs, output)
		return true
	})

	newState := State{
		Outputs: outputs,
		Serial:  m.serial,
	}

	m.stateMutex.Lock()
	m.state = &newState
	m.stateMutex.Unlock()

	m.notifySubscribers()
}

func (m *Manager) notifier() {
	defer m.notifierWg.Done()
	defer func() {
		if r := recover(); r != nil {
			err := fmt.Errorf("notifier panic: %v", r)
			log.Errorf("WlrOutput: %v", err)

			select {
			case m.fatalError <- err:
			default:
			}

			select {
			case <-m.stopChan:
			default:
				close(m.stopChan)
			}
		}
	}()

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

			currentState := m.GetState()

			if m.lastNotified != nil && !stateChanged(m.lastNotified, &currentState) {
				pending = false
				continue
			}

			m.subscribers.Range(func(key string, ch chan State) bool {
				select {
				case ch <- currentState:
				default:
					log.Warn("WlrOutput: subscriber channel full, dropping update")
				}
				return true
			})

			stateCopy := currentState
			m.lastNotified = &stateCopy
			pending = false
		}
	}
}

func (m *Manager) Close() {
	close(m.stopChan)
	m.wg.Wait()
	m.notifierWg.Wait()

	m.subscribers.Range(func(key string, ch chan State) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})

	m.modes.Range(func(key uint32, mode *modeState) bool {
		if mode.handle != nil {
			mode.handle.Release()
		}
		m.modes.Delete(key)
		return true
	})

	m.heads.Range(func(key uint32, head *headState) bool {
		if head.handle != nil {
			head.handle.Release()
		}
		m.heads.Delete(key)
		return true
	})

	if m.manager != nil {
		m.manager.Stop()
	}
}
