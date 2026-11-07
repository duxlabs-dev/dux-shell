package tui

import (
	"context"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
)

// Images skip the privileged phases: packages are present, or the user layers them and comes back after a reboot.
func (m Model) continueOnImmutable() (tea.Model, tea.Cmd) {
	if len(distros.PendingDependencies(m.dependencies, m.reinstallItems, m.disabledItems)) > 0 {
		if err := saveLayerResume(m.currentLayerResume()); err != nil {
			m.logChan <- "could not save resume state: " + err.Error()
		}
		m.state = StateLayerPackages
		return m, nil
	}
	m.installationLogs = nil
	m.state = StateConfigConfirmation
	m.isLoading = true
	return m, tea.Batch(m.spinner.Tick, m.setupUserServices(), m.checkExistingConfigurations())
}

func (m Model) resumeAfterLayering() (tea.Model, tea.Cmd) {
	for _, name := range m.resume.Selected {
		if _, ok := m.disabledItems[name]; ok {
			m.disabledItems[name] = false
		}
	}
	return m.continueOnImmutable()
}

func (m Model) setupUserServices() tea.Cmd {
	return func() tea.Msg {
		if !m.useSystemdConfig() || !m.optionalDepSelected("dux-search") {
			return nil
		}
		if err := distros.SetupDsearchService(context.Background(), func(line string) { m.logChan <- line }); err != nil {
			m.logChan <- "dux-search service setup warning (non-fatal): " + err.Error()
		}
		return nil
	}
}

func (m Model) layerCommands() []string {
	if m.osInfo == nil {
		return nil
	}
	distro, err := distros.NewDistribution(m.osInfo.Distribution.ID, m.logChan)
	if err != nil {
		return nil
	}
	layerer, ok := distro.(distros.PackageLayerer)
	if !ok {
		return nil
	}
	return layerer.LayerCommands(m.dependencies, m.chosenWindowManager(), m.reinstallItems, m.disabledItems)
}

func (m Model) viewLayerPackages() string {
	var b strings.Builder
	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Packages To Layer"))
	b.WriteString("\n\n")

	for _, dep := range distros.PendingDependencies(m.dependencies, m.reinstallItems, m.disabledItems) {
		line := "  ○ " + dep.Name
		if m.variantMarks[dep.Name] {
			line = "  ⇄ " + dep.Name + " → " + variantLabel(dep.Variant)
		}
		b.WriteString(m.styles.Warning.Render(line))
		b.WriteByte('\n')
	}
	b.WriteByte('\n')

	commands := m.layerCommands()
	if len(commands) == 0 {
		b.WriteString(m.styles.Normal.Render(wrapText("This image has no known way to add these packages. Install them from the image's own tooling, reboot, and run duxinstall again.", 70)))
		b.WriteString("\n\n")
	} else {
		b.WriteString(m.styles.Normal.Render("Run these, reboot, then run duxinstall again. It picks up from here and deploys configuration:"))
		b.WriteString("\n\n")
		for _, cmd := range commands {
			b.WriteString("  " + m.styles.Accent.Render(cmd))
			b.WriteByte('\n')
		}
		b.WriteByte('\n')
	}

	if m.osInfo != nil && distros.Registry[m.osInfo.Distribution.ID].Family == distros.FamilyFedora {
		b.WriteString(m.styles.Subtle.Render("Prefer a ready-made image? Zirconium ships niri and Dux Modular Shell:"))
		b.WriteByte('\n')
		b.WriteString("  " + m.styles.Subtle.Render(distros.ZirconiumSwitchCommand))
		b.WriteString("\n\n")
	}

	b.WriteString(m.styles.Subtle.Render("Esc: Back, Ctrl+C: Quit"))
	return b.String()
}

func (m Model) updateLayerPackagesState(msg tea.Msg) (tea.Model, tea.Cmd) {
	if keyMsg, ok := msg.(tea.KeyMsg); ok && keyMsg.String() == "esc" {
		m.state = StateDependencyReview
		return m, nil
	}
	return m, m.listenForLogs()
}
