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
	"sync/atomic"
	"time"
)

const (
	NiriCapRuleVrrFullscreenOnly = "niri.rule-vrr-fullscreen-only"
	NiriCapRuleOnXdgActivate     = "niri.rule-on-xdg-activate"
	NiriCapRulePinchSensitivity  = "niri.rule-pinch-sensitivity"
	NiriCapRuleOpenOnOutputList  = "niri.rule-open-on-output-list"
	NiriCapRuleBlockOutKind      = "niri.rule-block-out-kind"
	NiriCapTypeInOverview        = "niri.type-in-overview"
)

type niriFeatureProbe struct {
	capability string
	section    string
	body       string
}

const niriProbeBindKey = "Mod+Shift+Ctrl+Alt+"

// One entry per post-26.04 syntax DMS gates, so a niri git build gets exactly the ones it accepts.
// Bind keys stay distinct: the entries are also validated as one file.
var niriFeatureProbes = []niriFeatureProbe{
	{NiriCapRuleVrrFullscreenOnly, "window-rule", `variable-refresh-rate "fullscreen-only"`},
	{NiriCapRuleOnXdgActivate, "window-rule", `on-xdg-activate "set-urgent"`},
	{NiriCapRulePinchSensitivity, "window-rule", `pinch-sensitivity 1.0`},
	{NiriCapRuleOpenOnOutputList, "window-rule", "open-on-output \"probe-1\"\nopen-on-output \"probe-2\""},
	{NiriCapRuleBlockOutKind, "window-rule", `block-out-from "screencast" kind="hide"`},
	{"niri.layer-block-out-kind", "layer-rule", `block-out-from "screencast" kind="hide"`},
	{NiriCapTypeInOverview, "layer-rule", `focus-on-type-in-overview true`},
	{"niri.transparent-fullscreen-backdrop", "layout", `fullscreen-backdrop-color "transparent"`},
	{"niri.output-drm-lease", `output "probe"`, `drm-lease`},
	{"niri.focus-follows-mouse-outputs-only", "input", `focus-follows-mouse outputs-only=true`},
	{"niri.touchpad-pinch-sensitivity", "input", `touchpad { pinch-sensitivity 1.0; }`},
	{"niri.tablet-map-to-focused-window", "input", `tablet { map-to-focused-window; }`},
	{"niri.bind-release", "binds", niriProbeBindKey + `F1 { release { toggle-overview; }; }`},
	{"niri.bind-pass-through", "binds", niriProbeBindKey + `F2 pass-through=true { toggle-overview; }`},
	{"niri.bind-lone-modifier", "binds", `Mod { release { toggle-overview; }; }`},
	// One capability gates focus= on all nine in the keybind editor.
	{"niri.bind-move-focus", "binds", niriProbeBindKey + "A { move-column-left focus=false; }\n" +
		niriProbeBindKey + "B { move-column-right focus=false; }\n" +
		niriProbeBindKey + "C { move-column-to-first focus=false; }\n" +
		niriProbeBindKey + "D { move-column-to-last focus=false; }\n" +
		niriProbeBindKey + "E { move-column-to-index 1 focus=false; }\n" +
		niriProbeBindKey + "F { move-window-down focus=false; }\n" +
		niriProbeBindKey + "G { move-window-up focus=false; }\n" +
		niriProbeBindKey + "H { swap-window-left focus=false; }\n" +
		niriProbeBindKey + "I { swap-window-right focus=false; }"},
	{"niri.bind-focus-window-previous-scope", "binds", niriProbeBindKey + `F4 { focus-window-previous scope="workspace"; }`},
	{"niri.bind-focus-window-previous-filter", "binds", niriProbeBindKey + `F5 { focus-window-previous filter="app-id"; }`},
	// niri 9955d921c added these six together.
	{"niri.bind-window-state", "binds", niriProbeBindKey + "F6 { set-window-fullscreen; }\n" +
		niriProbeBindKey + "F7 { unset-window-fullscreen; }\n" +
		niriProbeBindKey + "F8 { set-windowed-fullscreen; }\n" +
		niriProbeBindKey + "F9 { unset-windowed-fullscreen; }\n" +
		niriProbeBindKey + "F10 { set-window-maximized-to-edges; }\n" +
		niriProbeBindKey + "F11 { unset-window-maximized-to-edges; }"},
	{"niri.bind-move-column-to-new-workspace-below", "binds", niriProbeBindKey + `F12 { move-column-to-new-workspace-below; }`},
	{"niri.bind-move-column-to-new-workspace-above", "binds", niriProbeBindKey + `1 { move-column-to-new-workspace-above; }`},
	{"niri.bind-move-window-to-new-workspace-below", "binds", niriProbeBindKey + `2 { move-window-to-new-workspace-below; }`},
	{"niri.bind-move-window-to-new-workspace-above", "binds", niriProbeBindKey + `3 { move-window-to-new-workspace-above; }`},
	{"niri.bind-toggle-touchpad", "binds", niriProbeBindKey + `4 { toggle-touchpad; }`},
	{"niri.bind-change-vt", "binds", niriProbeBindKey + `5 { change-vt 2; }`},
}

// niri allows input, layout and binds once per file, so probes sharing a section share its block.
func niriProbeConfig(probes []niriFeatureProbe) string {
	var sections []string
	bodies := map[string][]string{}
	for _, probe := range probes {
		if _, seen := bodies[probe.section]; !seen {
			sections = append(sections, probe.section)
		}
		bodies[probe.section] = append(bodies[probe.section], probe.body)
	}
	var b strings.Builder
	for _, section := range sections {
		fmt.Fprintf(&b, "%s {\n%s\n}\n", section, strings.Join(bodies[section], "\n"))
	}
	return b.String()
}

const niriProbeTimeout = 5 * time.Second

// Each probe is a niri process holding about 17 MB.
const niriProbeConcurrency = 4

var niriCaps struct {
	once sync.Once
	caps []string
}

// NiriCapabilities lists the post-26.04 syntax the running niri accepts.
func NiriCapabilities() []string {
	if os.Getenv("NIRI_SOCKET") == "" {
		return nil
	}
	niriCaps.once.Do(func() { niriCaps.caps = loadNiriCapabilities() })
	return niriCaps.caps
}

func loadNiriCapabilities() []string {
	if _, err := exec.LookPath("niri"); err != nil {
		return nil
	}
	key := niriCapsCacheKey()
	if caps, ok := readNiriCapsCache(key); ok {
		return caps
	}

	// A validator that could not run proves nothing about niri, so its answers are not kept.
	var inconclusive atomic.Bool
	validates := func(content string) bool {
		err := NiriValidateConfig(content)
		var rejected *NiriRejectedError
		if err != nil && !errors.As(err, &rejected) {
			inconclusive.Store(true)
		}
		return err == nil
	}
	mismatch := niriValidatorMayDiffer()
	caps := probeNiriCapabilities(validates, func() bool { return mismatch })
	if !mismatch && !inconclusive.Load() {
		writeNiriCapsCache(key, caps)
	}
	return caps
}

func HasNiriCapability(name string) bool {
	return slices.Contains(NiriCapabilities(), name)
}

// git builds of niri main still report 26.04, so only its own validator can tell.
func probeNiriCapabilities(validates func(string) bool, mismatch func() bool) []string {
	// A niri upgraded mid-session validates syntax the running compositor would reject.
	if mismatch() {
		return nil
	}

	accepted := make([]bool, len(niriFeatureProbes))
	if validates(niriProbeConfig(niriFeatureProbes)) {
		for i := range accepted {
			accepted[i] = true
		}
	} else {
		var wg sync.WaitGroup
		slots := make(chan struct{}, niriProbeConcurrency)
		for i, probe := range niriFeatureProbes {
			slots <- struct{}{}
			wg.Go(func() {
				defer func() { <-slots }()
				accepted[i] = validates(niriProbeConfig([]niriFeatureProbe{probe}))
			})
		}
		wg.Wait()
	}

	var caps []string
	for i, probe := range niriFeatureProbes {
		if accepted[i] {
			caps = append(caps, probe.capability)
		}
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
	out, err := NiriValidateFile(f.Name())
	if err == nil {
		return nil
	}
	return niriValidateError(out, err)
}

const niriRejectedExitCode = 1

// NiriRejectedError is niri parsing a config and refusing it, as opposed to a validator that never ran.
type NiriRejectedError struct {
	Message string
}

func (e *NiriRejectedError) Error() string {
	return "niri validate: " + e.Message
}

func niriValidateError(out []byte, err error) error {
	msg := strings.TrimSpace(string(out))
	var exit *exec.ExitError
	if errors.As(err, &exit) && exit.ExitCode() == niriRejectedExitCode {
		return &NiriRejectedError{Message: msg}
	}
	if msg != "" {
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
