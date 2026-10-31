package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
)

func wrapText(text string, width int) string {
	if len(text) <= width {
		return text
	}

	var result strings.Builder
	currentLine := ""
	for word := range strings.FieldsSeq(text) {
		switch {
		case currentLine == "":
			currentLine = word
		case len(currentLine)+1+len(word) <= width:
			currentLine += " " + word
		default:
			result.WriteString(currentLine)
			result.WriteByte('\n')
			currentLine = word
		}
	}
	result.WriteString(currentLine)
	return result.String()
}

func tailLines(lines []string, n int) []string {
	if len(lines) <= n {
		return lines
	}
	return lines[len(lines)-n:]
}

func (m Model) writeRecentLogs(b *strings.Builder, renderedHeader string, maxLines int) {
	if len(m.installationLogs) == 0 {
		return
	}

	b.WriteString(renderedHeader)
	b.WriteByte('\n')
	for _, line := range tailLines(m.installationLogs, maxLines) {
		if line == "" {
			continue
		}
		b.WriteString(m.styles.Subtle.Render("  " + line))
		b.WriteByte('\n')
	}
}

func (m Model) viewInstallingPackages() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Installing Packages"))
	b.WriteString("\n\n")

	if m.packageProgress.isComplete {
		if m.packageProgress.error != nil {
			b.WriteString(m.styles.Error.Render(wrapText("✗ Installation failed: "+m.packageProgress.error.Error(), 80)))
			return b.String()
		}
		b.WriteString(m.styles.Success.Render("✓ Installation complete!"))
		return b.String()
	}

	fmt.Fprintf(&b, "%s %s\n\n", m.spinner.View(), m.styles.Normal.Render(m.packageProgress.step))
	b.WriteString(m.styles.Normal.Render(m.renderInstallProgressBar()))
	b.WriteByte('\n')

	if m.packageProgress.commandInfo != "" {
		b.WriteString(m.styles.Subtle.Render("$ " + m.packageProgress.commandInfo))
		b.WriteByte('\n')
	}

	if len(m.installationLogs) > 0 {
		b.WriteByte('\n')
		m.writeRecentLogs(&b, m.styles.Subtle.Render("Live Output:"), 8)
	}

	if m.packageProgress.error != nil {
		b.WriteByte('\n')
		b.WriteString(m.styles.Error.Render(wrapText("Error: "+m.packageProgress.error.Error(), 80)))
	}

	if m.packageProgress.needsSudo {
		b.WriteString(m.styles.Warning.Render("⚠ Using provided sudo password"))
	}

	return b.String()
}

func (m Model) renderInstallProgressBar() string {
	const barWidth = 30
	filled := min(max(int(m.packageProgress.progress*barWidth), 0), barWidth)
	return fmt.Sprintf("[%s%s] %.0f%%",
		strings.Repeat("█", filled), strings.Repeat("░", barWidth-filled), m.packageProgress.progress*100)
}

func dmsPackageName(distroID string, dependencies []deps.Dependency) string {
	config, ok := distros.Registry[distroID]
	if !ok {
		return "dms"
	}

	var isGit bool
	for _, dep := range dependencies {
		if dep.Name == dmsDepName {
			isGit = dep.Variant == deps.VariantGit
			break
		}
	}

	switch config.Family {
	case distros.FamilyArch:
		if isGit {
			return "dux-shell-git"
		}
		return "dux-shell"
	case distros.FamilyFedora, distros.FamilyUbuntu, distros.FamilyDebian, distros.FamilySUSE, distros.FamilyVoid:
		if isGit {
			return "dms-git"
		}
		return "dms"
	default:
		return "dms"
	}
}

func (m Model) uninstallHint() string {
	if m.isImmutable() {
		if distros.Registry[m.osInfo.Distribution.ID].Family == distros.FamilyFedora {
			return "sudo rpm-ostree uninstall " + dmsPackageName(m.osInfo.Distribution.ID, m.dependencies)
		}
		return ""
	}
	return uninstallCommand(m.osInfo.Distribution.ID, m.dependencies)
}

func uninstallCommand(distroID string, dependencies []deps.Dependency) string {
	config, ok := distros.Registry[distroID]
	if !ok {
		return ""
	}
	if config.Family == distros.FamilyGentoo {
		return "sudo emerge --deselect dux-desktop/dux-shell && sudo emerge --depclean dux-desktop/dux-shell"
	}

	pkg := dmsPackageName(distroID, dependencies)
	switch config.Family {
	case distros.FamilyArch:
		return "sudo pacman -Rs " + pkg
	case distros.FamilyFedora:
		return "sudo dnf remove " + pkg
	case distros.FamilyUbuntu, distros.FamilyDebian:
		return "sudo apt remove " + pkg
	case distros.FamilySUSE:
		return "sudo zypper remove " + pkg
	case distros.FamilyVoid:
		return "sudo xbps-remove -R " + pkg
	default:
		return ""
	}
}

func (m Model) loginHint() string {
	wm := m.chosenWindowManager()

	if !m.useSystemdConfig() {
		switch wm {
		case deps.WindowManagerNiri:
			return "If you do not have a greeter, from a TTY run: dbus-run-session niri"
		case deps.WindowManagerHyprland:
			return "If you do not have a greeter, from a TTY run: dbus-run-session Hyprland"
		default:
			return "If you do not have a greeter, from a TTY run: dbus-run-session mango"
		}
	}

	switch wm {
	case deps.WindowManagerNiri:
		return `If you do not have a greeter, login with "niri-session"`
	case deps.WindowManagerHyprland:
		return `If you do not have a greeter, login with "Hyprland"`
	default:
		return `If you do not have a greeter, login with "mango"`
	}
}

func (m Model) troubleshootingHints() (autostart, logs string) {
	wm := m.chosenWindowManager()

	if !m.useSystemdConfig() {
		logs = "quickshell --path ~/.config/quickshell/dms log"
		switch wm {
		case deps.WindowManagerNiri:
			autostart = `remove spawn-at-startup "dms" "run" from ~/.config/niri/config.kdl`
		case deps.WindowManagerHyprland:
			autostart = `remove hl.exec_cmd("dms run") from ~/.config/hypr/hyprland.lua`
		default:
			autostart = "remove 'exec_once=dms run' from ~/.config/mango/config.conf"
		}
		return autostart, logs
	}

	if wm == deps.WindowManagerMango {
		if mangoconf.SessionTargetInstalled() {
			return "rm ~/.config/systemd/user/mango-session.target.wants/dms.service", "journalctl --user -u dms"
		}
		return "remove 'exec_once=dms run' from ~/.config/mango/config.conf", "qs -p ~/.config/quickshell/dms log"
	}
	return "systemctl --user disable dms", "journalctl --user -u dms"
}

func (m Model) viewInstallComplete() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Success.Render("Setup Complete!"))
	b.WriteString("\n\n")
	summary := "✓ All packages installed and configurations deployed."
	accomplishments := []string{
		"• Window manager and dependencies installed",
		"• Terminal and development tools configured",
		"• Configuration files deployed with backups",
		"• System optimized for Dux Shell",
	}
	if m.isImmutable() {
		summary = "✓ Configurations deployed. No packages were changed on this image."
		accomplishments = accomplishments[1:]
	}
	b.WriteString(m.styles.Success.Render(summary))
	b.WriteString("\n\n")

	for _, item := range accomplishments {
		b.WriteString(m.styles.Subtle.Render(item))
		b.WriteByte('\n')
	}

	b.WriteByte('\n')
	b.WriteString(m.styles.Normal.Render("Your system is ready! Log out and log back in to start using\nyour new desktop environment.\n" + m.loginHint()))
	b.WriteString("\n\n")

	label := m.styles.Subtle
	cmd := m.styles.Accent
	autostart, logs := m.troubleshootingHints()

	if m.isImmutable() && m.optionalDepSelected("dms-greeter") {
		b.WriteString(label.Render("Greeter:") + "\n")
		b.WriteString(label.Render("  Configure greetd:  ") + cmd.Render("dms-greeter install --yes") + "\n\n")
	}

	b.WriteString(label.Render("Troubleshooting:") + "\n")
	b.WriteString(label.Render("  Disable autostart: ") + cmd.Render(autostart) + "\n")
	b.WriteString(label.Render("  View logs:         ") + cmd.Render(logs) + "\n")

	if m.osInfo != nil {
		if uninstall := m.uninstallHint(); uninstall != "" {
			b.WriteString(label.Render("  Uninstall:         ") + cmd.Render(uninstall) + "\n")
		}
	}

	b.WriteByte('\n')
	b.WriteString(m.styles.Normal.Render("Press Enter to exit."))

	if m.logFilePath != "" {
		b.WriteString("\n\n")
		b.WriteString(m.styles.Subtle.Render(fmt.Sprintf("Full logs: %s", m.logFilePath)))
	}

	return b.String()
}

func (m Model) viewError() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Error.Render("Installation Failed"))
	b.WriteString("\n\n")

	if m.err != nil {
		b.WriteString(m.styles.Error.Render(wrapText("✗ "+m.err.Error(), 80)))
		b.WriteString("\n\n")
	}

	if m.packageProgress.error != nil {
		b.WriteString(m.styles.Error.Render(wrapText("Package Installation Error: "+m.packageProgress.error.Error(), 80)))
		b.WriteString("\n\n")
	}

	if len(m.installationLogs) > 0 {
		m.writeRecentLogs(&b, m.styles.Warning.Render("Installation Logs (last 15 lines):"), 15)
		b.WriteByte('\n')
	}

	b.WriteString(m.styles.Subtle.Render("Press Ctrl+D for full debug logs"))
	b.WriteByte('\n')

	if m.logFilePath != "" {
		b.WriteByte('\n')
		b.WriteString(m.styles.Warning.Render(fmt.Sprintf("Full logs: %s", m.logFilePath)))
		b.WriteByte('\n')
	}

	b.WriteString(m.styles.Subtle.Render("Press Enter to exit"))
	return b.String()
}

func (m Model) updateInstallingPackagesState(msg tea.Msg) (tea.Model, tea.Cmd) {
	progressMsg, ok := msg.(packageInstallProgressMsg)
	if !ok {
		return m, m.listenForLogs()
	}

	m.packageProgress = progressMsg

	if progressMsg.logOutput != "" {
		m.installationLogs = append(m.installationLogs, progressMsg.logOutput)
		m.installationLogs = tailLines(m.installationLogs, 50)
	}

	if !progressMsg.isComplete {
		return m, m.listenForPackageProgress()
	}

	if progressMsg.error != nil {
		m.state = StateError
		m.isLoading = false
		return m, m.listenForPackageProgress()
	}

	m.installationLogs = nil
	m.state = StateConfigConfirmation
	m.isLoading = true
	return m, tea.Batch(m.spinner.Tick, m.checkExistingConfigurations())
}

func (m Model) updateInstallCompleteState(msg tea.Msg) (tea.Model, tea.Cmd) {
	if keyMsg, ok := msg.(tea.KeyMsg); ok && keyMsg.String() == "enter" {
		return m, tea.Quit
	}
	return m, m.listenForLogs()
}

func (m Model) updateErrorState(msg tea.Msg) (tea.Model, tea.Cmd) {
	if keyMsg, ok := msg.(tea.KeyMsg); ok && keyMsg.String() == "enter" {
		return m, tea.Quit
	}
	return m, m.listenForLogs()
}

func (m Model) listenForPackageProgress() tea.Cmd {
	return func() tea.Msg {
		msg, ok := <-m.packageProgressChan
		if !ok {
			return packageProgressCompletedMsg{}
		}
		return msg
	}
}

func (m Model) viewDebugLogs() string {
	var b strings.Builder

	b.WriteString(m.styles.Highlight.Render("Debug Logs"))
	b.WriteString("\n\n")

	allLogs := append(append([]string{}, m.logMessages...), m.installationLogs...)
	if len(allLogs) == 0 {
		b.WriteString("No logs available\n")
	} else {
		maxHeight := max(m.height-6, 10)
		startIdx := max(len(allLogs)-maxHeight, 0)

		for i := startIdx; i < len(allLogs); i++ {
			if allLogs[i] != "" {
				fmt.Fprintf(&b, "%d: %s\n", i, allLogs[i])
			}
		}

		if startIdx > 0 {
			b.WriteString(m.styles.Subtle.Render(fmt.Sprintf("... (%d older log entries hidden)\n", startIdx)))
		}
	}

	b.WriteByte('\n')
	b.WriteString(m.styles.Accent.Render("Press Ctrl+D to return, Ctrl+C to quit"))
	return b.String()
}
