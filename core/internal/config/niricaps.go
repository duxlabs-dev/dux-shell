package config

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync"
	"time"
)

const NiriCapConfigNext = "niri.config-next"

// One line per syntax DMS gates; niri git builds older than every line drop to 26.04 behavior.
const niriConfigNextProbe = `window-rule {
    variable-refresh-rate "fullscreen-only"
    on-xdg-activate "set-urgent"
    pinch-sensitivity 1.0
    open-on-output "probe-1"
    open-on-output "probe-2"
    block-out-from "screencast" kind="hide"
}
layer-rule {
    match namespace="probe"
    focus-on-type-in-overview true
}
layout {
    fullscreen-backdrop-color "transparent"
}
output "probe" {
    drm-lease
}
input {
    focus-follows-mouse outputs-only=true
    touchpad {
        pinch-sensitivity 1.0
    }
    tablet {
        map-to-focused-window
    }
}
binds {
    Mod+Shift+Ctrl+Alt+F1 { move-column-to-new-workspace-below; }
    Mod+Shift+Ctrl+Alt+F2 { set-window-fullscreen; }
    Mod+Shift+Ctrl+Alt+F3 { move-column-left focus=false; }
    Mod+Shift+Ctrl+Alt+F4 { change-vt 2; }
    Mod+Shift+Ctrl+Alt+F5 { focus-window-previous scope="workspace"; }
    Mod+Shift+Ctrl+Alt+F6 pass-through=true { toggle-touchpad; }
    Mod {
        release { toggle-overview; }
    }
}
`

const niriProbeTimeout = 5 * time.Second

var niriCaps struct {
	once sync.Once
	caps []string
}

// NiriCapabilities lists the post-26.04 syntax the running niri accepts.
func NiriCapabilities() []string {
	if os.Getenv("NIRI_SOCKET") == "" {
		return nil
	}
	return ProbeNiriCapabilities()
}

func HasNiriCapability(name string) bool {
	return slices.Contains(NiriCapabilities(), name)
}

// git builds of niri main still report 26.04, so only its own validator can tell.
func ProbeNiriCapabilities() []string {
	niriCaps.once.Do(func() {
		if _, err := exec.LookPath("niri"); err != nil {
			return
		}
		niriCaps.caps = probeNiriCapabilities(NiriValidates, niriValidatorMayDiffer)
	})
	return niriCaps.caps
}

func probeNiriCapabilities(validates func(string) bool, mismatch func() bool) []string {
	// A niri upgraded mid-session validates syntax the running compositor would reject.
	if mismatch() {
		return nil
	}
	if !validates(niriConfigNextProbe) {
		return nil
	}
	return []string{NiriCapConfigNext}
}

func NiriValidates(content string) bool {
	return NiriValidateConfig(content) == nil
}

func NiriValidateConfig(content string) error {
	f, err := os.CreateTemp("", "dms-niri-probe-*.kdl")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	_, err = f.WriteString(content)
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return err
	}
	out, err := NiriValidateFile(f.Name())
	if err == nil {
		return nil
	}
	if msg := strings.TrimSpace(string(out)); msg != "" {
		return fmt.Errorf("niri validate: %s", msg)
	}
	return fmt.Errorf("niri validate: %w", err)
}

// NiriValidateFile asks the running compositor's binary, and niri on PATH when that one cannot be found or started.
func NiriValidateFile(path string) ([]byte, error) {
	exe := runningNiriExe()
	if exe == "" {
		return runNiriValidate("niri", path)
	}
	out, err := runNiriValidate(exe, path)
	if niriFailedToStart(err) {
		return runNiriValidate("niri", path)
	}
	return out, err
}

func runNiriValidate(bin, path string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), niriProbeTimeout)
	defer cancel()
	return exec.CommandContext(ctx, bin, "validate", "-c", path).CombinedOutput()
}

const loaderFailureExitCode = 127

// The dynamic loader exits 127 when an upgrade removed a library the old binary links.
func niriFailedToStart(err error) bool {
	if err == nil {
		return false
	}
	var exit *exec.ExitError
	if !errors.As(err, &exit) {
		return true
	}
	return exit.ExitCode() == loaderFailureExitCode
}

// Only niri on PATH can be newer than the session; the running binary answers for itself.
func niriValidatorMayDiffer() bool {
	exe := runningNiriExe()
	if exe == "" {
		return niriSessionVersionMismatch()
	}
	_, err := runNiriValidate(exe, os.DevNull)
	return niriFailedToStart(err) && niriSessionVersionMismatch()
}

func niriSessionVersionMismatch() bool {
	if os.Getenv("NIRI_SOCKET") == "" {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), niriProbeTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "niri", "msg", "--json", "version").Output()
	if err != nil {
		return true
	}
	var v struct {
		CLI        string `json:"cli"`
		Compositor string `json:"compositor"`
	}
	if err := json.Unmarshal(out, &v); err != nil {
		return true
	}
	return v.CLI != v.Compositor
}
