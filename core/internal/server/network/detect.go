package network

import (
	"fmt"
	"os"
	"runtime"

	"github.com/godbus/dbus/v5"
)

type BackendType int

const (
	BackendNone BackendType = iota
	BackendNetworkManager
	BackendIwd
	BackendConnMan
	BackendNetworkd
	BackendWpaSupplicant
)

func nameHasOwner(bus *dbus.Conn, name string) (bool, error) {
	obj := bus.Object("org.freedesktop.DBus", "/org/freedesktop/DBus")
	var owned bool
	if err := obj.Call("org.freedesktop.DBus.NameHasOwner", 0, name).Store(&owned); err != nil {
		return false, err
	}
	return owned, nil
}

type DetectResult struct {
	Backend      BackendType
	HasNM        bool
	HasIwd       bool
	HasConnMan   bool
	HasWpaSupp   bool
	HasNetworkd  bool
	ChosenReason string
}

func wpaSupplicantCtrlDirPresent() bool {
	info, err := os.Stat(wpaSupplicantCtrlDir)
	return err == nil && info.IsDir()
}

func DetectNetworkStack() (*DetectResult, error) {
	// FreeBSD uses the native ifconfig/wpa_supplicant backend regardless of
	// whether unrelated Linux-oriented D-Bus services happen to be present.
	if runtime.GOOS == "freebsd" {
		hasWpa := wpaSupplicantCtrlDirPresent()
		reason := "FreeBSD detected. Using native Ethernet interfaces."
		if hasWpa {
			reason = "FreeBSD detected with wpa_supplicant control directory. Using native Ethernet and wpa_ctrl Wi-Fi."
		}
		return &DetectResult{
			Backend:      BackendWpaSupplicant,
			HasWpaSupp:   hasWpa,
			ChosenReason: reason,
		}, nil
	}

	bus, err := dbus.ConnectSystemBus()
	if err != nil {
		if runtime.GOOS == "freebsd" {
			hasWpa := wpaSupplicantCtrlDirPresent()
			reason := "FreeBSD detected. Using native Ethernet interfaces."
			if hasWpa {
				reason = "FreeBSD detected with wpa_supplicant control directory. Using native Ethernet and wpa_ctrl Wi-Fi."
			}
			return &DetectResult{
				Backend:      BackendWpaSupplicant,
				HasWpaSupp:   hasWpa,
				ChosenReason: reason,
			}, nil
		}

		if !wpaSupplicantCtrlDirPresent() {
			return nil, fmt.Errorf("connect system bus: %w", err)
		}

		return &DetectResult{
			Backend:      BackendWpaSupplicant,
			HasWpaSupp:   true,
			ChosenReason: "System bus unreachable; wpa_supplicant control directory present. Using wpa_ctrl interface.",
		}, nil
	}

	defer bus.Close()

	hasNM, _ := nameHasOwner(bus, "org.freedesktop.NetworkManager")
	hasIwd, _ := nameHasOwner(bus, "net.connman.iwd")
	hasConn, _ := nameHasOwner(bus, "net.connman")
	hasWpa, _ := nameHasOwner(bus, "fi.w1.wpa_supplicant1")
	hasNetworkd, _ := nameHasOwner(bus, "org.freedesktop.network1")

	res := &DetectResult{
		HasNM:       hasNM,
		HasIwd:      hasIwd,
		HasConnMan:  hasConn,
		HasWpaSupp:  hasWpa,
		HasNetworkd: hasNetworkd,
	}

	switch {
	case hasNM:
		res.Backend = BackendNetworkManager
		if hasIwd {
			res.ChosenReason = "NetworkManager present; iwd also running (likely NM's Wi-Fi backend). Using NM API."
		} else {
			res.ChosenReason = "NetworkManager present. Using NM API."
		}
	case hasConn && hasIwd:
		res.Backend = BackendConnMan
		res.ChosenReason = "ConnMan + iwd detected. Use ConnMan API (iwd is its Wi-Fi daemon)."
	case hasIwd && hasNetworkd:
		res.Backend = BackendNetworkd
		res.ChosenReason = "iwd + systemd-networkd detected. Using iwd for Wi-Fi association and networkd for IP/DHCP."
	case hasIwd:
		res.Backend = BackendIwd
		res.ChosenReason = "iwd detected without NM/ConnMan. Using iwd API."
	case hasNetworkd:
		res.Backend = BackendNetworkd
		res.ChosenReason = "systemd-networkd detected (no NM/ConnMan). Using networkd for L3 and wired."
	case wpaSupplicantCtrlDirPresent():
		res.Backend = BackendWpaSupplicant
		res.HasWpaSupp = true
		res.ChosenReason = "No NM/ConnMan/iwd/networkd; wpa_supplicant control directory present. Using wpa_ctrl interface."
	case runtime.GOOS == "freebsd":
		res.Backend = BackendWpaSupplicant
		res.ChosenReason = "FreeBSD detected without wpa_supplicant. Using native Ethernet support."
	default:
		res.Backend = BackendNone
		if hasWpa {
			res.ChosenReason = "No NM/ConnMan/iwd; wpa_supplicant D-Bus name present but control directory missing."
		} else {
			res.ChosenReason = "No known network manager bus names found."
		}
	}

	return res, nil
}
