package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/site"
)

func (m Model) viewWelcome() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Accent.Render(strings.Repeat("━", 58)))
	b.WriteByte('\n')
	b.WriteString(m.styles.TitleBox.Render(
		m.styles.Highlight.Render("duxinstall") + m.styles.AccentItalic.Render(" // Dux Labs Installer")))
	b.WriteByte('\n')
	b.WriteString(m.styles.SubtleItalic.Render("Quickstart for a Dux Desktop"))
	b.WriteString("\n\n")

	switch {
	case m.osInfo == nil && m.isLoading:
		fmt.Fprintf(&b, "%s %s\n\n", m.spinner.View(), m.styles.Normal.Render("Detecting system..."))
	case m.osInfo != nil && m.osInfo.Immutable && !m.distroSupported():
		m.writeImmutableSystem(&b)
	case m.osInfo != nil && m.osInfo.Immutable && m.resume != nil:
		m.writeSystemSummary(&b)
		m.writeResumeNotice(&b)
	case m.osInfo != nil && m.osInfo.Immutable:
		m.writeSystemSummary(&b)
		m.writeImmutableNotice(&b)
	case m.osInfo != nil && distros.IsUnsupportedDistro(m.osInfo.Distribution.ID, m.osInfo.VersionID):
		m.writeUnsupportedDistro(&b)
	case m.osInfo != nil:
		m.writeSystemSummary(&b)
	}

	b.WriteString(m.styles.Subtle.Render(strings.Repeat("─", 59)))
	b.WriteByte('\n')
	m.writeWelcomeFooter(&b)

	return b.String()
}

func (m Model) writeUnsupportedDistro(b *strings.Builder) {
	title := m.styles.Error.Bold(true).Render("⚠ UNSUPPORTED DISTRIBUTION")
	msg := m.styles.Normal.Render(unsupportedDistroMessage(m.osInfo))
	b.WriteString(m.styles.ErrorBox.Render(title + "\n\n" + msg))
	b.WriteString("\n\n")
}

func (m Model) writeImmutableSystem(b *strings.Builder) {
	title := m.styles.Warning.Bold(true).Render("⚠ IMAGE-BASED SYSTEM")
	var paragraphs []string
	for _, p := range strings.Split(distros.ImmutableGuidance(m.osInfo), "\n\n") {
		paragraphs = append(paragraphs, wrapText(p, 70))
	}
	msg := m.styles.Normal.Render(strings.Join(paragraphs, "\n\n"))
	b.WriteString(m.styles.ErrorBox.Render(title + "\n\n" + msg))
	b.WriteString("\n\n")
}

func (m Model) writeImmutableNotice(b *strings.Builder) {
	title := m.styles.Warning.Bold(true).Render("Image-based system: " + m.osInfo.ImmutableReason)
	msg := wrapText("duxinstall will not install packages or ask for a password here. It checks what is installed, lists anything missing with the command to layer it, and deploys configuration into your home directory.", 70)
	b.WriteString(m.styles.InfoBox.Render(title + "\n" + m.styles.Normal.Render(msg)))
	b.WriteString("\n\n")
}

func (m Model) writeResumeNotice(b *strings.Builder) {
	title := m.styles.Success.Bold(true).Render(fmt.Sprintf("▶ Resuming setup: %s with %s", m.resume.WindowManager, m.resume.Terminal))
	msg := wrapText("Press Enter to finish. duxinstall checks that the layered packages are installed and deploys configuration into your home directory. No packages are installed and no password is needed.", 70)
	b.WriteString(m.styles.InfoBox.Render(title + "\n" + m.styles.Normal.Render(msg)))
	b.WriteString("\n\n")
}

func (m Model) isImmutable() bool {
	return m.osInfo != nil && m.osInfo.Immutable
}

func (m Model) distroSupported() bool {
	return m.osInfo != nil && distros.IsDistroSupported(m.osInfo.Distribution.ID)
}

func (m Model) cannotContinue() bool {
	if m.osInfo == nil {
		return true
	}
	if m.osInfo.Immutable {
		return !m.distroSupported()
	}
	return distros.IsUnsupportedDistro(m.osInfo.Distribution.ID, m.osInfo.VersionID)
}

func unsupportedDistroMessage(info *distros.OSInfo) string {
	switch info.Distribution.ID {
	case "ubuntu":
		return fmt.Sprintf("Ubuntu %s is not supported.\n\nOnly Ubuntu 25.04+ is supported.\n\nPlease upgrade to Ubuntu 25.04 or later.", info.VersionID)
	case "debian":
		return fmt.Sprintf("Debian %s is not supported.\n\nOnly Debian 13+ (Trixie) is supported.\n\nPlease upgrade to Debian 13 or later.", info.VersionID)
	case "nixos":
		return "See the NixOS documentation for installation instructions: " + site.Docs + "/dms/nixos."
	case "rhel", "centos", "rocky", "almalinux":
		return fmt.Sprintf("%s is not supported.\n\nOnly Enterprise Linux 10+ (RHEL, CentOS Stream, Rocky, AlmaLinux) is supported.", info.PrettyName)
	default:
		return fmt.Sprintf("%s is not supported.\nFeel free to request on https://github.com/duxlabs-dev/dux-shell", info.PrettyName)
	}
}

func (m Model) writeSystemSummary(b *strings.Builder) {
	distroName := lipgloss.NewStyle().
		Foreground(lipgloss.Color(m.osInfo.Distribution.HexColorCode)).
		Bold(true).
		Render(m.osInfo.PrettyName)
	arch := m.styles.Accent.Render(m.osInfo.Architecture)
	b.WriteString(m.styles.InfoBox.Render(fmt.Sprintf("System: %s / %s", distroName, arch)))
	b.WriteByte('\n')

	b.WriteString(m.styles.Highlight.Underline(true).Render("WHAT YOU GET"))
	b.WriteString("\n\n")

	features := []struct {
		tag  string
		desc string
	}{
		{"[shell]", "dms (Dux Shell)"},
		{"[wm]", "niri or Hyprland"},
		{"[term]", "Ghostty, kitty, or Alacritty"},
		{"[style]", "All the themes, automatically."},
		{"[config]", "DANK defaults - keybindings, rules, animations, etc."},
	}

	tagStyle := m.styles.Accent.Bold(true)
	for i, feat := range features {
		descStyle := m.styles.Normal
		if i == len(features)-1 {
			descStyle = descStyle.Bold(true)
		}
		fmt.Fprintf(b, "  %s %s\n", tagStyle.Render(fmt.Sprintf("%-9s", feat.tag)), descStyle.Render(feat.desc))
	}
	b.WriteByte('\n')

	b.WriteString(m.styles.SubtleItalic.Render("* Existing configs can be replaced (and backed up) or preserved"))
	b.WriteByte('\n')
	if m.isGentoo() {
		b.WriteString(m.styles.SubtleItalic.Render("* Will set per-package USE flags and unmask testing packages as needed"))
		b.WriteByte('\n')
	}
	if m.isEL() {
		b.WriteString(m.styles.Warning.Render("* Enterprise Linux support is in testing: niri only, EPEL 10 will be enabled"))
		b.WriteByte('\n')
	}
	b.WriteByte('\n')
}

func (m Model) writeWelcomeFooter(b *strings.Builder) {
	if m.osInfo == nil {
		b.WriteString(m.styles.Subtle.Render("Press Enter to continue, Ctrl+C to quit"))
		return
	}

	ctrlKey := m.styles.Highlight.Render("Ctrl+C")
	if m.cannotContinue() {
		b.WriteString(m.styles.Subtle.Render("Press ") + ctrlKey + m.styles.Subtle.Render(" to quit"))
		return
	}

	enterKey := m.styles.Highlight.Render("Enter")
	if m.resume != nil {
		b.WriteString(m.styles.Subtle.Render("Press ") + enterKey + m.styles.Subtle.Render(" to resume setup, ") +
			m.styles.Highlight.Render("S") + m.styles.Subtle.Render(" to start over, ") + ctrlKey + m.styles.Subtle.Render(" to quit"))
		return
	}
	b.WriteString(m.styles.Subtle.Render("Press ") + enterKey +
		m.styles.Subtle.Render(" to choose window manager, ") + ctrlKey + m.styles.Subtle.Render(" to quit"))
}

func (m Model) updateWelcomeState(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case osInfoCompleteMsg:
		m.isLoading = false
		if msg.err != nil {
			m.err = msg.err
			m.state = StateError
			return m, m.listenForLogs()
		}
		m.osInfo = msg.info
		if m.isImmutable() && m.distroSupported() {
			m.resume = loadLayerResume()
		}

	case tea.KeyMsg:
		if m.cannotContinue() {
			break
		}
		switch msg.String() {
		case "s", "S":
			if m.resume == nil {
				break
			}
			clearLayerResume()
			m.resume = nil
		case "enter":
			if m.applyLayerResume() {
				m.state = StateDetectingDeps
				m.isLoading = true
				return m, tea.Batch(m.spinner.Tick, m.detectDependencies())
			}
			clearLayerResume()
			m.resume = nil
			m.state = StateSelectWindowManager
		}
	}
	return m, m.listenForLogs()
}
