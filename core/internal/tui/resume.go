package tui

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

// Carries the first run's choices across the reboot that layering needs.
type layerResume struct {
	WindowManager string   `json:"window_manager"`
	Terminal      string   `json:"terminal"`
	Selected      []string `json:"selected"`
}

func resumePath() string {
	dir := os.Getenv("XDG_STATE_HOME")
	if dir == "" {
		dir = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return filepath.Join(dir, "duxinstall", "resume.json")
}

func saveLayerResume(r layerResume) error {
	path := resumePath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.Marshal(r)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

func loadLayerResume() *layerResume {
	data, err := os.ReadFile(resumePath())
	if err != nil {
		return nil
	}
	var r layerResume
	if json.Unmarshal(data, &r) != nil || r.WindowManager == "" || r.Terminal == "" {
		return nil
	}
	for i, name := range r.Selected {
		r.Selected[i] = deps.CanonicalName(name)
	}
	return &r
}

func layerScriptPath() string {
	return filepath.Join(filepath.Dir(resumePath()), "layer.sh")
}

// The view cuts lines at the terminal width and a wrapped copy breaks the command, so the user runs a file instead.
func saveLayerScript(commands []string) (string, error) {
	path := layerScriptPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return "", err
	}
	script := "#!/bin/sh\nset -e\n" + strings.Join(commands, "\n") + "\n"
	return path, os.WriteFile(path, []byte(script), 0o644)
}

func clearLayerResume() {
	os.Remove(resumePath())
	os.Remove(layerScriptPath())
}

func (m Model) currentLayerResume() layerResume {
	r := layerResume{}
	if wms := m.windowManagerChoices(); m.selectedWM >= 0 && m.selectedWM < len(wms) {
		r.WindowManager = strings.ToLower(wms[m.selectedWM].label)
	}
	if terms := m.terminalChoices(); m.selectedTerminal >= 0 && m.selectedTerminal < len(terms) {
		r.Terminal = strings.ToLower(terms[m.selectedTerminal].label)
	}
	for _, dep := range m.dependencies {
		if !dep.Required && !m.disabledItems[dep.Name] {
			r.Selected = append(r.Selected, dep.Name)
		}
	}
	return r
}

// false: the saved choices no longer fit this host.
func (m *Model) applyLayerResume() bool {
	if m.resume == nil {
		return false
	}
	wm, term := -1, -1
	for i, c := range m.windowManagerChoices() {
		if strings.ToLower(c.label) == m.resume.WindowManager {
			wm = i
		}
	}
	for i, c := range m.terminalChoices() {
		if strings.ToLower(c.label) == m.resume.Terminal {
			term = i
		}
	}
	if wm < 0 || term < 0 {
		return false
	}
	m.selectedWM, m.selectedTerminal = wm, term
	return true
}
