package config

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	NiriCapBindsNext  = "niri.binds-next"
	NiriCapConfigNext = "niri.config-next"

	NiriBindsNextFile = "binds-next.kdl"
)

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

// Tests swap this so deploys never shell out to a real niri.
var niriCapabilityProbe = ProbeNiriCapabilities

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
	var caps []string
	if validates(NiriBindsNextConfig) {
		caps = append(caps, NiriCapBindsNext)
	}
	if validates(niriConfigNextProbe) {
		caps = append(caps, NiriCapConfigNext)
	}
	return caps
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

// The 26.04 variant is valid on every niri.
func NiriBindsNextContent(caps []string) string {
	if slices.Contains(caps, NiriCapBindsNext) {
		return NiriBindsNextConfig
	}
	return NiriBindsNext2604Config
}

// Every write reloads niri, so only write on change.
func WriteNiriBindsNext(dmsDir string, caps []string) (bool, error) {
	path := filepath.Join(dmsDir, NiriBindsNextFile)
	want := NiriBindsNextContent(caps)
	if got, err := os.ReadFile(path); err == nil && string(got) == want {
		return false, nil
	}
	if err := os.WriteFile(path, []byte(want), 0o644); err != nil {
		return false, err
	}
	return true, nil
}

func SyncNiriBindsNext() (bool, error) {
	if os.Getenv("NIRI_SOCKET") == "" {
		return false, nil
	}
	dmsDir := filepath.Join(utils.XDGConfigHome(), "niri", "dms")
	if info, err := os.Stat(dmsDir); err != nil || !info.IsDir() {
		return false, nil
	}
	return WriteNiriBindsNext(dmsDir, NiriCapabilities())
}

const NiriBindsNextIncludeHint = `config.kdl does not include dms/binds-next.kdl; add include optional=true "dms/binds-next.kdl" above dms/binds.kdl to keep the Keyboard Shortcuts bind`

// A pre-existing config.kdl without this include loses the cheatsheet bind.
func NiriConfigMissingBindsNext(dmsDir string) bool {
	data, err := os.ReadFile(filepath.Join(filepath.Dir(dmsDir), "config.kdl"))
	return err == nil && !strings.Contains(string(data), "dms/"+NiriBindsNextFile)
}
