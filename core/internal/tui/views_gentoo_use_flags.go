package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
)

func (m Model) viewGentooUseFlags() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Gentoo Global USE Flags"))
	b.WriteString("\n\n")
	b.WriteString(m.styles.Normal.Render("The following global USE flags will be enabled in /etc/portage/make.conf:"))
	b.WriteString("\n\n")

	for _, flag := range distros.GentooGlobalUseFlags {
		b.WriteString(m.styles.Success.Render(fmt.Sprintf("  • %s", flag)))
		b.WriteByte('\n')
	}

	b.WriteByte('\n')
	b.WriteString(m.styles.Subtle.Render("These flags ensure proper Qt6, Wayland, and compositor support."))
	b.WriteString("\n\n")

	toggle := m.styles.Subtle.Render("  [ ] Skip adding global USE flags (will use existing configuration)")
	if m.skipGentooUseFlags {
		toggle = m.styles.Warning.Render("▶ [✗] Skip adding global USE flags (will use existing configuration)")
	}
	b.WriteString(toggle)
	b.WriteString("\n\n")

	b.WriteString(m.styles.Subtle.Render("Space: Toggle skip, Enter: Continue, Esc: Go back"))
	return b.String()
}

func (m Model) updateGentooUseFlagsState(msg tea.Msg) (tea.Model, tea.Cmd) {
	if gccMsg, ok := msg.(gccVersionCheckMsg); ok {
		if gccMsg.err != nil || gccMsg.major < 15 {
			m.state = StateGentooGCCCheck
			return m, nil
		}
		return m.enterAuthPhase()
	}

	if keyMsg, ok := msg.(tea.KeyMsg); ok {
		switch keyMsg.String() {
		case " ":
			m.skipGentooUseFlags = !m.skipGentooUseFlags
			return m, nil
		case "enter":
			if m.chosenWindowManager() == deps.WindowManagerHyprland {
				return m, m.checkGCCVersion()
			}
			return m.enterAuthPhase()
		case "esc":
			m.state = StateDependencyReview
			return m, nil
		}
	}
	return m, m.listenForLogs()
}
