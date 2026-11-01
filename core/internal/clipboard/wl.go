package clipboard

import (
	"fmt"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-go/wayland/ext_data_control"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/virtual_keyboard"
)

type session struct {
	display            *wlclient.Display
	ctx                *wlclient.Context
	registry           *wlclient.Registry
	seat               *wlclient.Seat
	dataControlMgr     *ext_data_control.ExtDataControlManagerV1
	virtualKeyboardMgr *virtual_keyboard.ZwpVirtualKeyboardManagerV1
}

// connectSession opens a short-lived Wayland connection and binds the seat
// plus whichever clipboard-related globals the compositor advertises.
func connectSession() (*session, error) {
	display, err := wlclient.Connect("")
	if err != nil {
		return nil, fmt.Errorf("wayland connect: %w", err)
	}

	s := &session{display: display, ctx: display.Context()}

	registry, err := display.GetRegistry()
	if err != nil {
		display.Destroy()
		return nil, fmt.Errorf("get registry: %w", err)
	}
	s.registry = registry

	var bindErr error
	bind := func(name uint32, iface string, version uint32, proxy wlclient.Proxy) {
		if err := registry.Bind(name, iface, version, proxy); err != nil {
			bindErr = fmt.Errorf("bind %s: %w", iface, err)
		}
	}

	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		switch e.Interface {
		case ext_data_control.ExtDataControlManagerV1InterfaceName:
			mgr := ext_data_control.NewExtDataControlManagerV1(s.ctx)
			bind(e.Name, e.Interface, e.Version, mgr)
			s.dataControlMgr = mgr
		case virtual_keyboard.ZwpVirtualKeyboardManagerV1InterfaceName:
			mgr := virtual_keyboard.NewZwpVirtualKeyboardManagerV1(s.ctx)
			bind(e.Name, e.Interface, e.Version, mgr)
			s.virtualKeyboardMgr = mgr
		case "wl_seat":
			if s.seat != nil {
				return
			}
			seat := wlclient.NewSeat(s.ctx)
			bind(e.Name, e.Interface, e.Version, seat)
			s.seat = seat
		}
	})

	display.Roundtrip()
	display.Roundtrip()

	if bindErr != nil {
		s.Close()
		return nil, bindErr
	}
	return s, nil
}

func (s *session) requireDataControl() (*ext_data_control.ExtDataControlManagerV1, error) {
	switch {
	case s.dataControlMgr == nil:
		return nil, fmt.Errorf("compositor does not support ext_data_control_manager_v1")
	case s.seat == nil:
		return nil, fmt.Errorf("no seat available")
	default:
		return s.dataControlMgr, nil
	}
}

func (s *session) Close() {
	if s.dataControlMgr != nil {
		s.dataControlMgr.Destroy()
	}
	if s.registry != nil {
		s.registry.Destroy()
	}
	s.display.Destroy()
}
