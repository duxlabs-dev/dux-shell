package tui

import (
	"context"
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const dmsDepName = "dms (Dux Shell)"

func (m Model) viewDetectingDeps() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Detecting Dependencies"))
	b.WriteString("\n\n")
	fmt.Fprintf(&b, "%s %s", m.spinner.View(), m.styles.Normal.Render("Scanning system for existing packages and configurations..."))

	return b.String()
}

func partitionOptionalLast(dependencies []deps.Dependency) []deps.Dependency {
	ordered := make([]deps.Dependency, 0, len(dependencies))
	for _, dep := range dependencies {
		if dep.Required {
			ordered = append(ordered, dep)
		}
	}
	for _, dep := range dependencies {
		if !dep.Required {
			ordered = append(ordered, dep)
		}
	}
	return ordered
}

func (m Model) viewDependencyReview() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Dependency Review"))
	b.WriteString("\n\n")

	optionalHeaderShown := false
	for i, dep := range m.dependencies {
		if !dep.Required && !optionalHeaderShown {
			b.WriteByte('\n')
			b.WriteString(m.styles.Subtle.Render("Optional (space to enable)"))
			b.WriteByte('\n')
			optionalHeaderShown = true
		}
		b.WriteString(m.dependencyLine(dep, i == m.selectedDep))
		b.WriteByte('\n')
	}

	b.WriteByte('\n')
	b.WriteString(m.styles.Subtle.Render("↑/↓: Navigate, Space: Toggle, G: Toggle stable/git, Enter: Continue"))
	return b.String()
}

func (m Model) dependencyLine(dep deps.Dependency, selected bool) string {
	marker, status := m.dependencyStatus(dep)

	variant := ""
	if dep.CanToggle && dep.Variant == deps.VariantGit {
		variant = "[git] "
	}

	cursor, style := "  ", m.styles.Normal
	if selected {
		cursor, style = "▶ ", m.styles.SelectedOption
	}

	line := fmt.Sprintf("%s%s%s%-25s %s", cursor, marker, variant, dep.Name, status)
	if dep.Version != "" {
		line += fmt.Sprintf(" (%s)", dep.Version)
	}
	return style.Render(line) + m.dependencyNote(dep.Name)
}

func (m Model) dependencyStatus(dep deps.Dependency) (marker, status string) {
	switch {
	case m.disabledItems[dep.Name]:
		return "✗ ", m.styles.Subtle.Render("Will skip")
	case m.variantMarks[dep.Name]:
		return "🔄 ", m.styles.Warning.Render("Will switch to " + variantLabel(dep.Variant))
	case m.reinstallItems[dep.Name]:
		return "🔄 ", m.styles.Warning.Render("Will upgrade")
	case m.isImmutable() && !dep.Required && dep.Status == deps.StatusInstalled:
		return "✓ ", m.styles.Success.Render("✓ Selected (installed)")
	case dep.Name == dmsDepName:
		switch dep.Status {
		case deps.StatusInstalled:
			return "⚡ ", m.styles.Success.Render("✓ Required (installed)")
		case deps.StatusMissing:
			if m.isImmutable() {
				return "⚡ ", m.styles.Warning.Render("○ Required (not installed)")
			}
			return "⚡ ", m.styles.Warning.Render("○ Required (will install)")
		case deps.StatusNeedsUpdate:
			return "⚡ ", m.styles.Warning.Render("△ Required (needs update)")
		case deps.StatusNeedsReinstall:
			return "⚡ ", m.styles.Error.Render("! Required (needs reinstall)")
		}
		return "⚡ ", ""
	}

	verb := "Will install"
	if m.isImmutable() {
		verb = "Not installed"
	}
	switch dep.Status {
	case deps.StatusInstalled:
		return "", m.styles.Subtle.Render("✓ Already installed")
	case deps.StatusMissing:
		return "", m.styles.Warning.Render("○ " + verb)
	case deps.StatusNeedsUpdate:
		return "", m.styles.Warning.Render("△ " + verb)
	case deps.StatusNeedsReinstall:
		return "", m.styles.Error.Render("! " + verb)
	}
	return "", ""
}

func variantLabel(variant deps.PackageVariant) string {
	if variant == deps.VariantGit {
		return "git"
	}
	return "stable"
}

func (m Model) dependencyNote(name string) string {
	switch name {
	case "dux-greeter":
		return m.styles.Subtle.Render(" (selection replaces your current display manager)")
	case "dux-search":
		return m.styles.Subtle.Render(" (file search; enables dsearch.service)")
	case "dux-calendar":
		return m.styles.Subtle.Render(" (autostart managed in dux-calendar settings)")
	default:
		return ""
	}
}

func (m Model) updateDetectingDepsState(msg tea.Msg) (tea.Model, tea.Cmd) {
	depsMsg, ok := msg.(depsDetectedMsg)
	if !ok {
		return m, m.listenForLogs()
	}

	m.isLoading = false
	if depsMsg.err != nil {
		m.err = depsMsg.err
		m.state = StateError
		return m, m.listenForLogs()
	}

	if m.isImmutable() {
		depsMsg.deps = distros.ApplyImmutableDetection(depsMsg.deps)
	}
	m.dependencies = partitionOptionalLast(depsMsg.deps)
	for _, dep := range m.dependencies {
		m.detectedVariants[dep.Name] = dep.Variant
		if dep.Required {
			continue
		}
		m.disabledItems[dep.Name] = true
	}
	if m.resume != nil {
		return m.resumeAfterLayering()
	}
	m.state = StateDependencyReview
	return m, m.listenForLogs()
}

func (m Model) updateDependencyReviewState(msg tea.Msg) (tea.Model, tea.Cmd) {
	keyMsg, ok := msg.(tea.KeyMsg)
	if !ok {
		return m, m.listenForLogs()
	}

	switch keyMsg.String() {
	case "up":
		m.selectedDep = moveIndex(m.selectedDep, -1, len(m.dependencies)-1)
	case "down":
		m.selectedDep = moveIndex(m.selectedDep, 1, len(m.dependencies)-1)
	case " ":
		m.toggleSelectedDependency()
	case "g", "G":
		m.toggleSelectedVariant()
	case "enter":
		if m.isImmutable() {
			return m.continueOnImmutable()
		}
		if m.osInfo != nil {
			if config, ok := distros.Registry[m.osInfo.Distribution.ID]; ok && config.Family == distros.FamilyGentoo {
				m.state = StateGentooUseFlags
				return m, nil
			}
		}
		return m.enterAuthPhase()
	case "esc":
		m.state = StateSelectWindowManager
		return m, nil
	}
	return m, m.listenForLogs()
}

func (m Model) toggleSelectedDependency() {
	if len(m.dependencies) == 0 {
		return
	}

	dep := m.dependencies[m.selectedDep]
	if dep.Name == dmsDepName {
		return
	}

	installed := dep.Status == deps.StatusInstalled || dep.Status == deps.StatusNeedsReinstall
	// Nothing to reinstall on an image; enabling only drives the user-space setup.
	if installed && !m.isImmutable() {
		m.reinstallItems[dep.Name] = !m.reinstallItems[dep.Name]
		m.disabledItems[dep.Name] = false
		return
	}
	m.disabledItems[dep.Name] = !m.disabledItems[dep.Name]
	m.reinstallItems[dep.Name] = false
}

func (m Model) toggleSelectedVariant() {
	if len(m.dependencies) == 0 || !m.dependencies[m.selectedDep].CanToggle {
		return
	}

	dep := &m.dependencies[m.selectedDep]
	if dep.Variant == deps.VariantStable {
		dep.Variant = deps.VariantGit
	} else {
		dep.Variant = deps.VariantStable
	}

	// The installer skips installed deps unless marked, and the mark is what triggers the variant swap.
	if dep.Status == deps.StatusMissing {
		return
	}
	switched := dep.Variant != m.detectedVariants[dep.Name]
	if switched {
		m.variantMarks[dep.Name] = !m.reinstallItems[dep.Name]
		m.reinstallItems[dep.Name] = true
		m.disabledItems[dep.Name] = false
		return
	}
	if m.variantMarks[dep.Name] {
		delete(m.reinstallItems, dep.Name)
		delete(m.variantMarks, dep.Name)
	}
}

func (m Model) installPackages() tea.Cmd {
	return func() tea.Msg {
		if m.osInfo == nil {
			return packageInstallProgressMsg{step: "Error: OS info not available", isComplete: true}
		}

		installer, err := distros.NewPackageInstaller(m.osInfo.Distribution.ID, m.logChan)
		if err != nil {
			return packageInstallProgressMsg{step: fmt.Sprintf("Error: %s", err.Error()), isComplete: true}
		}

		progressChan := make(chan distros.InstallProgressMsg, 100)
		go func() {
			defer close(progressChan)
			err := installer.InstallPackages(context.Background(), m.dependencies, m.chosenWindowManager(), m.sudoPassword, m.reinstallItems, m.disabledItems, m.skipGentooUseFlags, progressChan)
			if err != nil {
				progressChan <- distros.InstallProgressMsg{
					Step:       fmt.Sprintf("Installation error: %s", err.Error()),
					IsComplete: true,
					Error:      err,
				}
			}
		}()
		go m.forwardInstallProgress(progressChan)

		return packageInstallProgressMsg{progress: 0.05, step: "Starting installation..."}
	}
}

func (m Model) forwardInstallProgress(progressChan <-chan distros.InstallProgressMsg) {
	for msg := range progressChan {
		if msg.Phase == distros.PhaseComplete && msg.IsComplete && msg.Error == nil {
			m.runPostInstallTasks()
		}

		if msg.IsComplete {
			m.logChan <- fmt.Sprintf("[DEBUG] Sending completion signal: step=%s, progress=%.2f", msg.Step, msg.Progress)
		}
		m.packageProgressChan <- packageInstallProgressMsg{
			progress:    msg.Progress,
			step:        msg.Step,
			isComplete:  msg.IsComplete,
			needsSudo:   msg.NeedsSudo,
			commandInfo: msg.CommandInfo,
			logOutput:   msg.LogOutput,
			error:       msg.Error,
		}
	}
	m.logChan <- "[DEBUG] Installer channel closed"
}

func (m Model) runPostInstallTasks() {
	if m.optionalDepSelected("dux-greeter") {
		m.reportProgress(0.92, "Configuring DMS greeter...", "Starting automated greeter setup...")
		logLine := func(line string) {
			m.reportProgress(0.94, "Configuring DMS greeter...", line)
		}
		if err := utils.RunDmsGreeterInstall(m.sudoPassword, logLine); err != nil {
			m.reportProgress(0.96, "Greeter setup warning", fmt.Sprintf("⚠ Greeter auto-setup warning (non-fatal): %v", err))
		}
	}

	if !m.useSystemdConfig() || !m.optionalDepSelected("dux-search") {
		return
	}
	m.reportProgress(0.97, "Enabling dux-search service...", "Setting up dsearch.service...")
	logLine := func(line string) {
		m.reportProgress(0.97, "Enabling dux-search service...", line)
	}
	if err := distros.SetupDsearchService(context.Background(), logLine); err != nil {
		m.reportProgress(0.98, "dux-search service warning", fmt.Sprintf("dux-search service setup warning (non-fatal): %v", err))
	}
}

func (m Model) reportProgress(progress float64, step, logOutput string) {
	m.packageProgressChan <- packageInstallProgressMsg{
		progress:  progress,
		step:      step,
		logOutput: logOutput,
	}
}
