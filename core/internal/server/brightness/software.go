package brightness

import (
	"maps"
	"regexp"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wayland"
)

const softwareIDPrefix = "software:"

var internalOutputPattern = regexp.MustCompile(`^(eDP|LVDS|DSI)-`)

// uncoveredOutputs returns the outputs no backlight or DDC device controls. A
// sysfs backlight cannot be tied to a connector, so it is taken to cover every
// internal panel.
func uncoveredOutputs(outputs []string, hasBacklight bool, ddcConnectors []string) []string {
	uncovered := []string{}
	for _, name := range outputs {
		switch {
		case strings.HasPrefix(name, "HEADLESS-"):
			continue
		case hasBacklight && internalOutputPattern.MatchString(name):
			continue
		case slices.Contains(ddcConnectors, name):
			continue
		}
		uncovered = append(uncovered, name)
	}
	return uncovered
}

// takenOverOutputs returns the connected outputs that still have a software
// level but are now controlled by hardware, so their ramp would stay dimmed
// with no slider to undo it.
func takenOverOutputs(outputs, uncovered []string, levels map[string]int) []string {
	takenOver := []string{}
	for name := range levels {
		if !slices.Contains(outputs, name) || slices.Contains(uncovered, name) {
			continue
		}
		takenOver = append(takenOver, name)
	}
	return takenOver
}

func (m *Manager) softwareDevices(hardware []Device) []Device {
	gamma := m.gamma.Load()
	if gamma == nil || !m.ddcSettled.Load() {
		return nil
	}

	hasBacklight := slices.ContainsFunc(hardware, func(d Device) bool { return d.Class == ClassBacklight })
	var ddcConnectors []string
	if m.ddcReady && m.ddcBackend != nil {
		ddcConnectors = m.ddcBackend.ControlledOutputs()
	}

	outputs := gamma.ListOutputs()
	uncovered := uncoveredOutputs(outputs, hasBacklight, ddcConnectors)
	levels := gamma.GetOutputBrightness()
	for _, name := range takenOverOutputs(outputs, uncovered, levels) {
		if err := gamma.SetOutputBrightness(name, 100); err != nil {
			log.Debugf("failed to drop software brightness for %s: %v", name, err)
		}
	}

	refused := gamma.GammaRefusedOutputs()
	devices := []Device{}
	for _, name := range uncovered {
		if slices.Contains(refused, name) {
			continue
		}
		percent, dimmed := levels[name]
		if !dimmed {
			percent = 100
		}
		devices = append(devices, Device{
			Class:          ClassSoftware,
			ID:             softwareIDPrefix + name,
			Name:           name,
			Current:        percent,
			Max:            100,
			CurrentPercent: percent,
			Backend:        "gamma",
		})
	}
	return devices
}

// AttachGamma enables software brightness for outputs without a backlight or
// DDC/CI. Only output and brightness changes are followed, not night light steps.
func (m *Manager) AttachGamma(gamma *wayland.Manager) {
	m.gamma.Store(gamma)
	m.updateState()

	const subscriberID = "brightness-software"
	ch := gamma.Subscribe(subscriberID)
	go func() {
		defer gamma.Unsubscribe(subscriberID)
		var outputs, refused []string
		var levels map[string]int
		for {
			select {
			case <-m.stopChan:
				return
			case state, ok := <-ch:
				if !ok {
					return
				}
				if slices.Equal(outputs, state.Outputs) && maps.Equal(levels, state.Config.OutputBrightness) && slices.Equal(refused, state.GammaRefused) {
					continue
				}
				outputs = state.Outputs
				levels = state.Config.OutputBrightness
				refused = state.GammaRefused
				m.updateState()
			}
		}
	}()
}
