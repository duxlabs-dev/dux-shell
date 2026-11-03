package keymap

import (
	"fmt"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
)

// FromSeat opens a short-lived Wayland connection just to receive the xkb
// keymap the compositor hands out on wl_keyboard, and parses it.
func FromSeat() (*Keymap, error) {
	display, err := wlclient.Connect("")
	if err != nil {
		return nil, fmt.Errorf("wayland connect: %w", err)
	}
	defer display.Destroy()

	registry, err := display.GetRegistry()
	if err != nil {
		return nil, fmt.Errorf("get registry: %w", err)
	}
	defer registry.Destroy()

	ctx := display.Context()
	var (
		seat    *wlclient.Seat
		bindErr error
	)
	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		if e.Interface != "wl_seat" || seat != nil {
			return
		}
		candidate := wlclient.NewSeat(ctx)
		if err := registry.Bind(e.Name, e.Interface, e.Version, candidate); err != nil {
			bindErr = fmt.Errorf("bind wl_seat: %w", err)
			return
		}
		seat = candidate
	})

	display.Roundtrip()
	display.Roundtrip()

	switch {
	case bindErr != nil:
		return nil, bindErr
	case seat == nil:
		return nil, fmt.Errorf("no seat available")
	}

	keyboard, err := seat.GetKeyboard()
	if err != nil {
		return nil, fmt.Errorf("get keyboard: %w", err)
	}
	defer keyboard.Release()

	var event *wlclient.KeyboardKeymapEvent
	keyboard.SetKeymapHandler(func(e wlclient.KeyboardKeymapEvent) {
		if event == nil {
			event = &e
		}
	})
	display.Roundtrip()

	if event == nil {
		return nil, fmt.Errorf("no keymap from seat")
	}

	// FromEvent owns the fd and closes it.
	k := FromEvent(*event)
	if k == nil {
		return nil, fmt.Errorf("seat keymap is not xkb v1")
	}
	return k, nil
}
