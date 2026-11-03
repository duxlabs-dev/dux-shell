package main

import (
	"fmt"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_output_management"
)

type randrOutput struct {
	Name    string  `json:"name"`
	Scale   float64 `json:"scale"`
	Width   int32   `json:"width"`
	Height  int32   `json:"height"`
	Refresh int32   `json:"refresh"`
	Enabled bool    `json:"enabled"`
}

type randrHead struct {
	name          string
	enabled       bool
	scale         float64
	currentModeID uint32
	modeIDs       []uint32
}

type randrMode struct {
	width   int32
	height  int32
	refresh int32
}

type randrClient struct {
	display *wlclient.Display
	ctx     *wlclient.Context
	manager *wlr_output_management.ZwlrOutputManagerV1
	heads   map[uint32]*randrHead
	modes   map[uint32]*randrMode
	done    bool
	err     error
}

func queryRandr() ([]randrOutput, error) {
	display, err := wlclient.Connect("")
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Wayland: %w", err)
	}

	c := &randrClient{
		display: display,
		ctx:     display.Context(),
		heads:   make(map[uint32]*randrHead),
		modes:   make(map[uint32]*randrMode),
	}
	defer c.ctx.Close()

	registry, err := display.GetRegistry()
	if err != nil {
		return nil, fmt.Errorf("failed to get registry: %w", err)
	}

	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		if e.Interface == wlr_output_management.ZwlrOutputManagerV1InterfaceName {
			mgr := wlr_output_management.NewZwlrOutputManagerV1(c.ctx)
			version := min(e.Version, 4)

			mgr.SetHeadHandler(func(e wlr_output_management.ZwlrOutputManagerV1HeadEvent) {
				c.handleHead(e)
			})

			mgr.SetDoneHandler(func(e wlr_output_management.ZwlrOutputManagerV1DoneEvent) {
				c.done = true
			})

			if err := registry.Bind(e.Name, e.Interface, version, mgr); err == nil {
				c.manager = mgr
			}
		}
	})

	// First roundtrip: discover globals and bind manager
	syncCallback, err := display.Sync()
	if err != nil {
		return nil, fmt.Errorf("failed to sync display: %w", err)
	}
	syncCallback.SetDoneHandler(func(e wlclient.CallbackDoneEvent) {
		if c.manager == nil {
			c.err = fmt.Errorf("zwlr_output_manager_v1 protocol not supported by compositor")
			c.done = true
		}
		// Otherwise wait for manager's DoneHandler
	})

	for !c.done {
		if err := c.ctx.Dispatch(); err != nil {
			return nil, fmt.Errorf("dispatch error: %w", err)
		}
	}

	if c.err != nil {
		return nil, c.err
	}

	return c.buildOutputs(), nil
}

func (c *randrClient) handleHead(e wlr_output_management.ZwlrOutputManagerV1HeadEvent) {
	handle := e.Head
	headID := handle.ID()

	head := &randrHead{
		modeIDs: make([]uint32, 0),
	}
	c.heads[headID] = head

	handle.SetNameHandler(func(e wlr_output_management.ZwlrOutputHeadV1NameEvent) {
		head.name = e.Name
	})

	handle.SetEnabledHandler(func(e wlr_output_management.ZwlrOutputHeadV1EnabledEvent) {
		head.enabled = e.Enabled != 0
	})

	handle.SetScaleHandler(func(e wlr_output_management.ZwlrOutputHeadV1ScaleEvent) {
		head.scale = e.Scale
	})

	handle.SetCurrentModeHandler(func(e wlr_output_management.ZwlrOutputHeadV1CurrentModeEvent) {
		head.currentModeID = e.Mode.ID()
	})

	handle.SetModeHandler(func(e wlr_output_management.ZwlrOutputHeadV1ModeEvent) {
		modeHandle := e.Mode
		modeID := modeHandle.ID()

		head.modeIDs = append(head.modeIDs, modeID)

		mode := &randrMode{}
		c.modes[modeID] = mode

		modeHandle.SetSizeHandler(func(e wlr_output_management.ZwlrOutputModeV1SizeEvent) {
			mode.width = e.Width
			mode.height = e.Height
		})

		modeHandle.SetRefreshHandler(func(e wlr_output_management.ZwlrOutputModeV1RefreshEvent) {
			mode.refresh = e.Refresh
		})
	})
}

func (c *randrClient) buildOutputs() []randrOutput {
	outputs := make([]randrOutput, 0, len(c.heads))

	for _, head := range c.heads {
		out := randrOutput{
			Name:    head.name,
			Scale:   head.scale,
			Enabled: head.enabled,
		}

		if mode, ok := c.modes[head.currentModeID]; ok {
			out.Width = mode.width
			out.Height = mode.height
			out.Refresh = mode.refresh
		}

		outputs = append(outputs, out)
	}

	return outputs
}
