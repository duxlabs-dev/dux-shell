package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
)

func immutableFedoraModel(dependencies []deps.Dependency) Model {
	m := NewModel("test", "")
	m.osInfo = &distros.OSInfo{PrettyName: "Fedora Linux 44 (Silverblue)", Distribution: distros.DistroInfo{ID: "fedora"}, Immutable: true, ImmutableReason: "ostree-based system"}
	m.dependencies = dependencies
	return m
}

func TestImmutableHostStopsAtLayerScreen(t *testing.T) {
	m := immutableFedoraModel([]deps.Dependency{
		{Name: dmsDepName, Status: deps.StatusMissing, Required: true},
		{Name: "niri", Status: deps.StatusInstalled, Required: true},
	})
	next, _ := m.continueOnImmutable()
	if got := next.(Model).state; got != StateLayerPackages {
		t.Fatalf("state = %v, want StateLayerPackages", got)
	}
	view := next.(Model).viewLayerPackages()
	if !strings.Contains(view, "sudo rpm-ostree install dms") || !strings.Contains(view, "bootc switch") {
		t.Fatalf("layer screen missing commands:\n%s", view)
	}
}

func TestImmutableHostWithPackagesSkipsToConfigs(t *testing.T) {
	m := immutableFedoraModel([]deps.Dependency{
		{Name: dmsDepName, Status: deps.StatusInstalled, Required: true},
		{Name: "niri", Status: deps.StatusInstalled, Required: true},
	})
	next, _ := m.continueOnImmutable()
	if got := next.(Model).state; got != StateConfigConfirmation {
		t.Fatalf("state = %v, want StateConfigConfirmation", got)
	}
	if m.cannotContinue() {
		t.Fatal("registered immutable host must pass the welcome screen")
	}
}

func TestImmutableSecondRunResumesPastReview(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())

	first := immutableFedoraModel([]deps.Dependency{
		{Name: dmsDepName, Status: deps.StatusMissing, Required: true},
		{Name: "dux-search", Status: deps.StatusMissing},
		{Name: "dux-calendar", Status: deps.StatusMissing},
	})
	first.selectedWM, first.selectedTerminal = 0, 1 // niri, kitty
	first.disabledItems["dux-search"] = false
	first.disabledItems["dux-calendar"] = true
	if next, _ := first.continueOnImmutable(); next.(Model).state != StateLayerPackages {
		t.Fatal("first run should stop at the layer screen")
	}

	second := immutableFedoraModel(nil)
	second.isLoading = false
	second.resume = loadLayerResume()
	if second.resume == nil {
		t.Fatal("layer screen must save a resume file")
	}
	second = pressKey(t, second, enterKey)
	if second.state != StateDetectingDeps || second.selectedTerminal != 1 {
		t.Fatalf("state = %v, terminal = %d; want detection with the saved choices", second.state, second.selectedTerminal)
	}

	updated, _ := second.Update(depsDetectedMsg{deps: []deps.Dependency{
		{Name: dmsDepName, Status: deps.StatusInstalled, Required: true},
		{Name: "dux-search", Status: deps.StatusInstalled},
		{Name: "dux-calendar", Status: deps.StatusInstalled},
	}})
	second = updated.(Model)
	if second.state != StateConfigConfirmation {
		t.Fatalf("state = %v, want StateConfigConfirmation without a review stop", second.state)
	}
	if second.disabledItems["dux-search"] || !second.disabledItems["dux-calendar"] {
		t.Fatalf("resume must restore the optional selection: %v", second.disabledItems)
	}
}

func TestResumeFromOlderInstallerUsesCurrentNames(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	if err := saveLayerResume(layerResume{WindowManager: "niri", Terminal: "kitty", Selected: []string{"danksearch", "dms-greeter"}}); err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(loadLayerResume().Selected, ","); got != "dux-search,dux-greeter" {
		t.Fatalf("Selected = %q, want dux-search,dux-greeter", got)
	}
}

func TestImmutableStartOverClearsResume(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	if err := saveLayerResume(layerResume{WindowManager: "niri", Terminal: "ghostty"}); err != nil {
		t.Fatal(err)
	}
	m := immutableFedoraModel(nil)
	m.isLoading = false
	m.resume = loadLayerResume()
	m = pressKey(t, m, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("s")})
	if m.resume != nil || loadLayerResume() != nil {
		t.Fatal("S must drop the saved run")
	}
	m = pressKey(t, m, enterKey)
	if m.state != StateSelectWindowManager {
		t.Fatalf("state = %v, want StateSelectWindowManager", m.state)
	}
}

func TestImmutableEnableInstalledOptionalIsNotPending(t *testing.T) {
	m := immutableFedoraModel([]deps.Dependency{
		{Name: dmsDepName, Status: deps.StatusInstalled, Required: true},
		{Name: "dux-greeter", Status: deps.StatusInstalled},
	})
	m.selectedDep = 1
	m.disabledItems["dux-greeter"] = true
	m.toggleSelectedDependency()
	if m.disabledItems["dux-greeter"] || m.reinstallItems["dux-greeter"] {
		t.Fatalf("enable on an image must not mark a reinstall: disabled=%v reinstall=%v", m.disabledItems, m.reinstallItems)
	}
	if pending := distros.PendingDependencies(m.dependencies, m.reinstallItems, m.disabledItems); len(pending) != 0 {
		t.Fatalf("installed package listed for layering: %v", pending)
	}
	if line := m.dependencyLine(m.dependencies[1], false); !strings.Contains(line, "Selected (installed)") {
		t.Fatalf("status line = %q", line)
	}
}

func TestImmutableVariantToggleMarksSwitch(t *testing.T) {
	m := immutableFedoraModel([]deps.Dependency{
		{Name: dmsDepName, Status: deps.StatusInstalled, Required: true, CanToggle: true, Variant: deps.VariantGit},
	})
	m.detectedVariants[dmsDepName] = deps.VariantGit
	m.toggleSelectedVariant()
	if m.dependencies[0].Variant != deps.VariantStable || !m.reinstallItems[dmsDepName] || !m.variantMarks[dmsDepName] {
		t.Fatalf("G on an image must mark a switch: %+v reinstall=%v marks=%v", m.dependencies[0], m.reinstallItems, m.variantMarks)
	}
	if line := m.dependencyLine(m.dependencies[0], false); !strings.Contains(line, "Will switch to stable") {
		t.Fatalf("status line = %q", line)
	}
	m.toggleSelectedVariant()
	if m.reinstallItems[dmsDepName] || m.variantMarks[dmsDepName] {
		t.Fatal("toggling back must clear the switch mark")
	}
}
