package tui

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
)

func archModel() Model {
	m := NewModel("test", "")
	m.osInfo = &distros.OSInfo{
		Distribution: distros.DistroInfo{ID: "arch"},
		PrettyName:   "Arch Linux",
		Architecture: "amd64",
	}
	m.isLoading = false
	return m
}

func pressKey(t *testing.T, m Model, key tea.KeyMsg) Model {
	t.Helper()
	updated, _ := m.Update(key)
	next, ok := updated.(Model)
	if !ok {
		t.Fatalf("Update returned %T, want Model", updated)
	}
	return next
}

var enterKey = tea.KeyMsg{Type: tea.KeyEnter}
var downKey = tea.KeyMsg{Type: tea.KeyDown}
var escKey = tea.KeyMsg{Type: tea.KeyEsc}

func TestWelcomeEnterAdvances(t *testing.T) {
	m := archModel()
	m = pressKey(t, m, enterKey)
	if m.state != StateSelectWindowManager {
		t.Fatalf("state = %v, want StateSelectWindowManager", m.state)
	}
}

func TestWelcomeEnterBlockedWithoutOSInfo(t *testing.T) {
	m := NewModel("test", "")
	m = pressKey(t, m, enterKey)
	if m.state != StateWelcome {
		t.Fatalf("state = %v, want StateWelcome", m.state)
	}
}

func TestWelcomeEnterBlockedOnUnsupportedDistro(t *testing.T) {
	m := archModel()
	m.osInfo.Distribution.ID = "ubuntu"
	m.osInfo.VersionID = "22.04"
	m = pressKey(t, m, enterKey)
	if m.state != StateWelcome {
		t.Fatalf("state = %v, want StateWelcome", m.state)
	}
}

func TestSelectionFlowAndEscape(t *testing.T) {
	m := archModel()
	m = pressKey(t, m, enterKey)
	m = pressKey(t, m, downKey)
	if m.selectedWM != 1 {
		t.Fatalf("selectedWM = %d, want 1", m.selectedWM)
	}
	if m.chosenWindowManager() != deps.WindowManagerHyprland {
		t.Fatalf("chosenWindowManager = %v, want Hyprland", m.chosenWindowManager())
	}

	m = pressKey(t, m, enterKey)
	if m.state != StateSelectTerminal {
		t.Fatalf("state = %v, want StateSelectTerminal", m.state)
	}
	m = pressKey(t, m, downKey)
	if m.chosenTerminal() != deps.TerminalKitty {
		t.Fatalf("chosenTerminal = %v, want Kitty", m.chosenTerminal())
	}

	m = pressKey(t, m, escKey)
	if m.state != StateSelectWindowManager {
		t.Fatalf("state = %v, want StateSelectWindowManager after esc", m.state)
	}
}

func TestWindowManagerChoicesOmitHyprlandOnDebian(t *testing.T) {
	m := archModel()
	m.osInfo.Distribution.ID = "debian"
	for _, c := range m.windowManagerChoices() {
		if c.wm == deps.WindowManagerHyprland {
			t.Fatal("debian choices include Hyprland")
		}
	}
}

func TestTerminalChoicesOmitGhosttyOnGentoo(t *testing.T) {
	m := archModel()
	m.osInfo.Distribution.ID = "gentoo"
	choices := m.terminalChoices()
	if len(choices) != 2 || choices[0].terminal != deps.TerminalKitty {
		t.Fatalf("gentoo terminal choices = %+v, want kitty first without ghostty", choices)
	}
	if m.chosenTerminal() != deps.TerminalKitty {
		t.Fatalf("chosenTerminal = %v, want Kitty default on gentoo", m.chosenTerminal())
	}
}

func TestToggleSelectedDependency(t *testing.T) {
	m := archModel()
	m.dependencies = []deps.Dependency{
		{Name: dmsDepName, Required: true, Status: deps.StatusMissing},
		{Name: "quickshell", Required: true, Status: deps.StatusInstalled},
		{Name: "matugen", Required: true, Status: deps.StatusMissing},
	}

	m.selectedDep = 0
	m.toggleSelectedDependency()
	if m.disabledItems[dmsDepName] || m.reinstallItems[dmsDepName] {
		t.Fatal("dms must not be toggleable")
	}

	m.selectedDep = 1
	m.toggleSelectedDependency()
	if !m.reinstallItems["quickshell"] {
		t.Fatal("toggling an installed dep should mark reinstall")
	}

	m.selectedDep = 2
	m.toggleSelectedDependency()
	if !m.disabledItems["matugen"] {
		t.Fatal("toggling a missing dep should mark disabled")
	}
}

func TestDetectedDepsPartitionAndOptOut(t *testing.T) {
	m := archModel()
	m.state = StateDetectingDeps
	updated, _ := m.Update(depsDetectedMsg{deps: []deps.Dependency{
		{Name: "dux-greeter", Required: false},
		{Name: "quickshell", Required: true},
	}})
	m = updated.(Model)

	if m.state != StateDependencyReview {
		t.Fatalf("state = %v, want StateDependencyReview", m.state)
	}
	if m.dependencies[0].Name != "quickshell" {
		t.Fatal("required deps should sort before optional")
	}
	if !m.disabledItems["dux-greeter"] {
		t.Fatal("optional deps should default to disabled")
	}
}

func TestPasswordPromptValidation(t *testing.T) {
	m := archModel()
	m.state = StatePasswordPrompt

	updated, _ := m.Update(passwordValidMsg{valid: false})
	m = updated.(Model)
	if !m.authFailed || m.state != StatePasswordPrompt {
		t.Fatalf("invalid password: authFailed=%v state=%v", m.authFailed, m.state)
	}

	updated, _ = m.Update(passwordValidMsg{password: "hunter2", valid: true})
	m = updated.(Model)
	if m.state != StateInstallingPackages || m.sudoPassword != "hunter2" || m.authFailed {
		t.Fatalf("valid password: state=%v sudoPassword set=%v", m.state, m.sudoPassword != "")
	}
}

func TestConfigCheckDefaultsToReplace(t *testing.T) {
	m := archModel()
	m.state = StateConfigConfirmation
	updated, _ := m.Update(configCheckResult{configs: []ExistingConfigInfo{
		{ConfigType: "Niri", Path: "/tmp/niri.kdl", Exists: false},
		{ConfigType: "Ghostty", Path: "/tmp/ghostty", Exists: true},
	}})
	m = updated.(Model)

	if m.state != StateConfigConfirmation {
		t.Fatalf("state = %v, want StateConfigConfirmation while configs exist", m.state)
	}
	if !m.replaceConfigs["Ghostty"] {
		t.Fatal("existing config should default to replace")
	}
	if m.selectedConfig != 1 {
		t.Fatalf("selectedConfig = %d, want first existing config", m.selectedConfig)
	}
}

func TestConfigCheckKeepsBindsByDefault(t *testing.T) {
	m := archModel()
	m.state = StateConfigConfirmation
	updated, _ := m.Update(configCheckResult{configs: []ExistingConfigInfo{
		{ConfigType: "Mango", Path: "/tmp/config.conf", Exists: true},
		{ConfigType: config.BindsConfigType, Path: "/tmp/binds.conf", Exists: true},
	}})
	m = updated.(Model)
	if !m.replaceConfigs["Mango"] || m.replaceConfigs[config.BindsConfigType] {
		t.Fatalf("replaceConfigs = %v, want Mango replaced and its binds kept", m.replaceConfigs)
	}
}

func TestToggleVariantMarksInstalledDepForSwap(t *testing.T) {
	m := archModel()
	m.dependencies = []deps.Dependency{
		{Name: "dux-greeter", Status: deps.StatusInstalled, CanToggle: true},
		{Name: "dux-calendar", Status: deps.StatusMissing, CanToggle: true},
	}
	m.detectedVariants["dux-greeter"] = deps.VariantStable
	m.disabledItems["dux-greeter"] = true

	m.toggleSelectedVariant()
	if !m.reinstallItems["dux-greeter"] || m.disabledItems["dux-greeter"] {
		t.Fatal("switching an installed dep's variant should queue it for install")
	}
	m.toggleSelectedVariant()
	if m.reinstallItems["dux-greeter"] {
		t.Fatal("switching back to the installed variant should clear the reinstall")
	}

	m.reinstallItems["dux-greeter"] = true
	m.toggleSelectedVariant()
	m.toggleSelectedVariant()
	if !m.reinstallItems["dux-greeter"] {
		t.Fatal("a reinstall the user marked by hand must survive toggling the variant and back")
	}

	m.selectedDep = 1
	m.toggleSelectedVariant()
	if m.reinstallItems["dux-calendar"] {
		t.Fatal("a missing dep installs anyway and must not be marked for reinstall")
	}
}
