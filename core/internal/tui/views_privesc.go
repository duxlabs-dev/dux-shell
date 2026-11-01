package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

func (m Model) viewSelectPrivesc() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Privilege Escalation Tool"))
	b.WriteString("\n\n")
	b.WriteString(m.styles.Normal.Render("Multiple privilege tools are available. Choose one for installation:"))
	b.WriteString("\n\n")

	options := make([]listOption, len(m.availablePrivesc))
	for i, t := range m.availablePrivesc {
		options[i] = listOption{label: fmt.Sprintf("%s  —  %s", t.Name(), privescToolDescription(t))}
	}
	m.renderOptionList(&b, options, m.selectedPrivesc)

	b.WriteByte('\n')
	b.WriteString(m.styles.Subtle.Render(fmt.Sprintf("Set %s=<tool> to skip this prompt in future runs.", privesc.EnvVar)))
	b.WriteString("\n\n")
	b.WriteString(m.styles.Subtle.Render("↑/↓: Navigate, Enter: Select, Esc: Back"))
	return b.String()
}

func (m Model) updateSelectPrivescState(msg tea.Msg) (tea.Model, tea.Cmd) {
	keyMsg, ok := msg.(tea.KeyMsg)
	if !ok {
		return m, m.listenForLogs()
	}

	switch keyMsg.String() {
	case "up":
		m.selectedPrivesc = moveIndex(m.selectedPrivesc, -1, len(m.availablePrivesc)-1)
	case "down":
		m.selectedPrivesc = moveIndex(m.selectedPrivesc, 1, len(m.availablePrivesc)-1)
	case "enter":
		chosen := m.availablePrivesc[m.selectedPrivesc]
		if err := privesc.SetTool(chosen); err != nil {
			m.err = fmt.Errorf("failed to select %s: %w", chosen.Name(), err)
			m.state = StateError
			return m, nil
		}
		return m.routeToAuthAfterPrivesc()
	case "esc":
		m.state = StateDependencyReview
	}
	return m, nil
}

func privescToolDescription(t privesc.Tool) string {
	switch t {
	case privesc.ToolSudo:
		return "classic sudo (supports password prompt in this installer)"
	case privesc.ToolDoas:
		return "OpenBSD-style doas (requires persist or nopass in /etc/doas.conf)"
	case privesc.ToolRun0:
		return "systemd run0 (authenticated via polkit)"
	default:
		return string(t)
	}
}

// Sudo goes through the fingerprint/password path; doas and run0 skip password
// entry and proceed straight to install.
func (m Model) routeToAuthAfterPrivesc() (tea.Model, tea.Cmd) {
	tool, err := privesc.Detect()
	if err != nil {
		m.err = err
		m.state = StateError
		return m, nil
	}

	if tool != privesc.ToolSudo {
		return m.startInstallation("")
	}

	if checkFingerprintEnabled() {
		m.selectedAuthMethod = 0
		m.state = StateAuthMethodChoice
		return m, nil
	}
	return m.promptForPassword()
}

func (m Model) enterAuthPhase() (tea.Model, tea.Cmd) {
	tools := privesc.AvailableTools()
	if len(tools) == 0 {
		m.err = fmt.Errorf("no supported privilege tool (sudo/doas/run0) found on PATH")
		m.state = StateError
		return m, nil
	}

	if _, envSet := privesc.EnvOverride(); envSet || len(tools) == 1 {
		return m.routeToAuthAfterPrivesc()
	}

	m.availablePrivesc = tools
	m.selectedPrivesc = 0
	m.state = StateSelectPrivesc
	return m, nil
}
