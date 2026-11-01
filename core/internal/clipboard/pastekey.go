package clipboard

import (
	"fmt"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/wayland/keymap"
	"golang.org/x/sys/unix"
)

const (
	keyStateReleased = 0
	keyStatePressed  = 1

	// xkb real modifier bit positions are fixed: Shift=0, Lock=1, Control=2
	shiftModMask = 1 << 0
	ctrlModMask  = 1 << 2
)

// SendPasteKeystroke emulates a paste shortcut via zwp_virtual_keyboard_v1
// using the seat's own keymap, so keycodes stay valid for XWayland clients
// (a synthetic wtype-style keymap breaks X11 apps like Steam). withShift
// selects ctrl+shift+v for terminal targets.
func SendPasteKeystroke(withShift bool) (err error) {
	s, err := connectSession()
	if err != nil {
		return err
	}
	defer s.Close()

	if s.virtualKeyboardMgr == nil {
		return fmt.Errorf("compositor does not support zwp_virtual_keyboard_manager_v1")
	}
	if s.seat == nil {
		return fmt.Errorf("no seat available")
	}

	keyboard, err := s.seat.GetKeyboard()
	if err != nil {
		return fmt.Errorf("get keyboard: %w", err)
	}
	defer keyboard.Release()

	var seatKeymap *wlclient.KeyboardKeymapEvent
	keyboard.SetKeymapHandler(func(e wlclient.KeyboardKeymapEvent) {
		if seatKeymap == nil {
			seatKeymap = &e
		}
	})

	s.display.Roundtrip()

	if seatKeymap == nil || seatKeymap.Format != keymap.FormatXkbV1 {
		return fmt.Errorf("no xkb keymap from seat")
	}
	defer unix.Close(seatKeymap.Fd)

	keymapText, err := keymap.Read(seatKeymap.Fd, seatKeymap.Size)
	if err != nil {
		return fmt.Errorf("read keymap: %w", err)
	}
	keys := keymap.Parse(keymapText)

	vk, err := s.virtualKeyboardMgr.CreateVirtualKeyboard(s.seat)
	if err != nil {
		return fmt.Errorf("create virtual keyboard: %w", err)
	}
	defer vk.Destroy()

	if err := vk.Keymap(keymap.FormatXkbV1, seatKeymap.Fd, seatKeymap.Size); err != nil {
		return fmt.Errorf("set keymap: %w", err)
	}

	mods := uint32(ctrlModMask)
	held := []uint32{keys.Keycode("Control_L")}
	if withShift {
		mods |= shiftModMask
		held = append(held, keys.Keycode("Shift_L"))
	}

	t := uint32(0)
	var pressed []uint32
	press := func(key uint32) error {
		t++
		if err := vk.Key(t, key, keyStatePressed); err != nil {
			return err
		}
		pressed = append(pressed, key)
		return nil
	}

	// all releases happen here so error paths can't leave keys held or
	// modifiers latched for the compositor to interpret on destroy
	defer func() {
		for i := len(pressed) - 1; i >= 0; i-- {
			t++
			if e := vk.Key(t, pressed[i], keyStateReleased); e != nil && err == nil {
				err = fmt.Errorf("key release: %w", e)
			}
		}
		if e := vk.Modifiers(0, 0, 0, 0); e != nil && err == nil {
			err = fmt.Errorf("clear modifiers: %w", e)
		}
		s.display.Roundtrip()
	}()

	for _, key := range held {
		if err := press(key); err != nil {
			return fmt.Errorf("key press: %w", err)
		}
	}
	if err := vk.Modifiers(mods, 0, 0, 0); err != nil {
		return fmt.Errorf("set modifiers: %w", err)
	}
	if err := press(keys.Keycode("v")); err != nil {
		return fmt.Errorf("key press: %w", err)
	}
	return nil
}
