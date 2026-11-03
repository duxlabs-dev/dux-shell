package main

import (
	"fmt"
	"sync"
	"time"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_output_power"
)

type cmd struct {
	fn   func()
	done chan error
}

type dpmsClient struct {
	display   *wlclient.Display
	ctx       *wlclient.Context
	powerMgr  *wlr_output_power.ZwlrOutputPowerManagerV1
	outputs   map[string]*outputState
	mu        sync.Mutex
	syncRound int
	done      bool
	err       error
	cmdq      chan cmd
	stopChan  chan struct{}
	wg        sync.WaitGroup
}

type outputState struct {
	wlOutput  *wlclient.Output
	powerCtrl *wlr_output_power.ZwlrOutputPowerV1
	name      string
	mode      uint32
	failed    bool
	waitCh    chan struct{}
	wantMode  *uint32
}

func (c *dpmsClient) post(fn func()) {
	done := make(chan error, 1)
	select {
	case c.cmdq <- cmd{fn: fn, done: done}:
		<-done
	case <-c.stopChan:
	}
}

func (c *dpmsClient) waylandActor() {
	defer c.wg.Done()
	for {
		select {
		case <-c.stopChan:
			return
		case cmd := <-c.cmdq:
			cmd.fn()
			close(cmd.done)
		}
	}
}

func newDPMSClient() (*dpmsClient, error) {
	display, err := wlclient.Connect("")
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Wayland: %w", err)
	}

	c := &dpmsClient{
		display:  display,
		ctx:      display.Context(),
		outputs:  make(map[string]*outputState),
		cmdq:     make(chan cmd, 128),
		stopChan: make(chan struct{}),
	}

	c.wg.Add(1)
	go c.waylandActor()

	registry, err := display.GetRegistry()
	if err != nil {
		display.Context().Close()
		return nil, fmt.Errorf("failed to get registry: %w", err)
	}

	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		switch e.Interface {
		case wlr_output_power.ZwlrOutputPowerManagerV1InterfaceName:
			powerMgr := wlr_output_power.NewZwlrOutputPowerManagerV1(c.ctx)
			version := min(e.Version, 1)
			if err := registry.Bind(e.Name, e.Interface, version, powerMgr); err == nil {
				c.powerMgr = powerMgr
			}

		case "wl_output":
			output := wlclient.NewOutput(c.ctx)
			version := min(e.Version, 4)
			if err := registry.Bind(e.Name, e.Interface, version, output); err == nil {
				outputID := fmt.Sprintf("output-%d", output.ID())
				state := &outputState{
					wlOutput: output,
					name:     outputID,
				}

				c.mu.Lock()
				c.outputs[outputID] = state
				c.mu.Unlock()

				output.SetNameHandler(func(ev wlclient.OutputNameEvent) {
					c.mu.Lock()
					delete(c.outputs, state.name)
					state.name = ev.Name
					c.outputs[ev.Name] = state
					c.mu.Unlock()
				})
			}
		}
	})

	syncCallback, err := display.Sync()
	if err != nil {
		c.Close()
		return nil, fmt.Errorf("failed to sync display: %w", err)
	}
	syncCallback.SetDoneHandler(func(e wlclient.CallbackDoneEvent) {
		c.handleSync()
	})

	for !c.done {
		if err := c.ctx.Dispatch(); err != nil {
			c.Close()
			return nil, fmt.Errorf("dispatch error: %w", err)
		}
	}

	if c.err != nil {
		c.Close()
		return nil, c.err
	}

	return c, nil
}

func (c *dpmsClient) handleSync() {
	c.syncRound++

	switch c.syncRound {
	case 1:
		if c.powerMgr == nil {
			c.err = fmt.Errorf("wlr-output-power-management protocol not supported by compositor")
			c.done = true
			return
		}

		c.mu.Lock()
		for _, state := range c.outputs {
			powerCtrl, err := c.powerMgr.GetOutputPower(state.wlOutput)
			if err != nil {
				continue
			}
			state.powerCtrl = powerCtrl

			powerCtrl.SetModeHandler(func(e wlr_output_power.ZwlrOutputPowerV1ModeEvent) {
				c.mu.Lock()
				defer c.mu.Unlock()
				if state.powerCtrl == nil {
					return
				}
				state.mode = e.Mode
				if state.wantMode != nil && e.Mode == *state.wantMode && state.waitCh != nil {
					close(state.waitCh)
					state.wantMode = nil
				}
			})

			powerCtrl.SetFailedHandler(func(e wlr_output_power.ZwlrOutputPowerV1FailedEvent) {
				c.mu.Lock()
				defer c.mu.Unlock()
				if state.powerCtrl == nil {
					return
				}
				state.failed = true
				if state.waitCh != nil {
					close(state.waitCh)
					state.wantMode = nil
				}
			})
		}
		c.mu.Unlock()

		syncCallback, err := c.display.Sync()
		if err != nil {
			c.err = fmt.Errorf("failed to sync display: %w", err)
			c.done = true
			return
		}
		syncCallback.SetDoneHandler(func(e wlclient.CallbackDoneEvent) {
			c.handleSync()
		})

	default:
		c.done = true
	}
}

func (c *dpmsClient) ListOutputs() []string {
	c.mu.Lock()
	defer c.mu.Unlock()

	names := make([]string, 0, len(c.outputs))
	for name := range c.outputs {
		names = append(names, name)
	}
	return names
}

func (c *dpmsClient) SetDPMS(outputName string, on bool) error {
	var mode uint32
	if on {
		mode = uint32(wlr_output_power.ZwlrOutputPowerV1ModeOn)
	} else {
		mode = uint32(wlr_output_power.ZwlrOutputPowerV1ModeOff)
	}

	var setErr error
	c.post(func() {
		c.mu.Lock()
		var waitStates []*outputState

		if outputName == "" || outputName == "all" {
			if len(c.outputs) == 0 {
				c.mu.Unlock()
				setErr = fmt.Errorf("no outputs found")
				return
			}

			for _, state := range c.outputs {
				if state.powerCtrl == nil {
					continue
				}
				state.wantMode = &mode
				state.waitCh = make(chan struct{})
				state.failed = false
				waitStates = append(waitStates, state)
				state.powerCtrl.SetMode(mode)
			}
		} else {
			state, ok := c.outputs[outputName]
			if !ok {
				c.mu.Unlock()
				setErr = fmt.Errorf("output not found: %s", outputName)
				return
			}
			if state.powerCtrl == nil {
				c.mu.Unlock()
				setErr = fmt.Errorf("output %s has nil powerCtrl", outputName)
				return
			}
			state.wantMode = &mode
			state.waitCh = make(chan struct{})
			state.failed = false
			waitStates = append(waitStates, state)
			state.powerCtrl.SetMode(mode)
		}
		c.mu.Unlock()

		deadline := time.Now().Add(10 * time.Second)

		for _, state := range waitStates {
			c.mu.Lock()
			ch := state.waitCh
			c.mu.Unlock()

			done := false
			for !done {
				if err := c.ctx.Dispatch(); err != nil {
					setErr = fmt.Errorf("dispatch error: %w", err)
					return
				}

				select {
				case <-ch:
					c.mu.Lock()
					if state.failed {
						setErr = fmt.Errorf("compositor reported failed for %s", state.name)
						c.mu.Unlock()
						return
					}
					c.mu.Unlock()
					done = true
				default:
					if time.Now().After(deadline) {
						setErr = fmt.Errorf("timeout waiting for mode change on %s", state.name)
						return
					}
					time.Sleep(10 * time.Millisecond)
				}
			}
		}

		c.mu.Lock()
		for _, state := range waitStates {
			if state.powerCtrl != nil {
				state.powerCtrl.Destroy()
				state.powerCtrl = nil
			}
		}
		c.mu.Unlock()

		c.display.Roundtrip()
	})

	return setErr
}

func (c *dpmsClient) Close() {
	close(c.stopChan)
	c.wg.Wait()

	c.mu.Lock()
	defer c.mu.Unlock()

	for _, state := range c.outputs {
		if state.powerCtrl != nil {
			state.powerCtrl.Destroy()
		}
	}
	c.outputs = nil

	if c.powerMgr != nil {
		c.powerMgr.Destroy()
		c.powerMgr = nil
	}

	if c.display != nil {
		c.ctx.Close()
		c.display = nil
	}
}
