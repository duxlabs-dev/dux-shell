package config

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync"
	"time"
)

const NiriCapConfigNext = "niri.config-next"

const niriConfigNextProbe = `window-rule {
    variable-refresh-rate "fullscreen-only"
    on-xdg-activate "set-urgent"
    pinch-sensitivity 1.0
}
input {
    touchpad {
        pinch-sensitivity 1.0
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
		niriCaps.caps = probeNiriCapabilities(NiriValidates, niriSessionVersionMismatch)
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
	ctx, cancel := context.WithTimeout(context.Background(), niriProbeTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "niri", "validate", "-c", f.Name()).CombinedOutput()
	if err == nil {
		return nil
	}
	if msg := strings.TrimSpace(string(out)); msg != "" {
		return fmt.Errorf("niri validate: %s", msg)
	}
	return fmt.Errorf("niri validate: %w", err)
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
