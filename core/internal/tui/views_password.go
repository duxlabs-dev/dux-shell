package tui

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

func (m Model) viewAuthMethodChoice() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Authentication Method"))
	b.WriteString("\n\n")
	b.WriteString(m.styles.Normal.Render("Fingerprint authentication is available.\nHow would you like to authenticate?"))
	b.WriteString("\n\n")

	m.renderOptionList(&b, []listOption{{label: "Use Fingerprint"}, {label: "Use Password"}}, m.selectedAuthMethod)

	b.WriteByte('\n')
	b.WriteString(m.styles.Subtle.Render("↑/↓: Navigate, Enter: Select, Esc: Back"))
	return b.String()
}

func (m Model) viewFingerprintAuth() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Fingerprint Authentication"))
	b.WriteString("\n\n")

	if m.fingerprintFailed {
		b.WriteString(m.styles.Error.Render("✗ Fingerprint authentication failed"))
		b.WriteByte('\n')
		b.WriteString(m.styles.Subtle.Render("Returning to authentication menu..."))
		return b.String()
	}

	b.WriteString(m.styles.Normal.Render("Please place your finger on the fingerprint reader."))
	b.WriteString("\n\n")
	fmt.Fprintf(&b, "%s %s", m.spinner.View(), m.styles.Normal.Render("Waiting for fingerprint..."))

	return b.String()
}

func (m Model) viewPasswordPrompt() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Password Authentication"))
	b.WriteString("\n\n")
	b.WriteString(m.styles.Normal.Render("Installation requires sudo privileges.\nPlease enter your password to continue:"))
	b.WriteString("\n\n")
	b.WriteString(m.passwordInput.View())
	b.WriteByte('\n')

	switch {
	case m.authValidating:
		fmt.Fprintf(&b, "%s %s\n", m.spinner.View(), m.styles.Normal.Render("Validating sudo password..."))
	case m.authFailed:
		b.WriteString(m.styles.Error.Render("✗ Incorrect password. Please try again."))
		b.WriteByte('\n')
	}

	b.WriteByte('\n')
	b.WriteString(m.styles.Subtle.Render("Enter: Continue, Esc: Back, Ctrl+C: Cancel"))
	return b.String()
}

func (m Model) updateAuthMethodChoiceState(msg tea.Msg) (tea.Model, tea.Cmd) {
	m.fingerprintFailed = false

	keyMsg, ok := msg.(tea.KeyMsg)
	if !ok {
		return m, nil
	}

	switch keyMsg.String() {
	case "up":
		m.selectedAuthMethod = moveIndex(m.selectedAuthMethod, -1, 1)
	case "down":
		m.selectedAuthMethod = moveIndex(m.selectedAuthMethod, 1, 1)
	case "enter":
		if m.selectedAuthMethod == 0 {
			m.state = StateFingerprintAuth
			m.isLoading = true
			return m, tea.Batch(m.spinner.Tick, m.tryFingerprint())
		}
		return m.promptForPassword()
	case "esc":
		m.state = StateDependencyReview
	}
	return m, nil
}

func (m Model) updateFingerprintAuthState(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case passwordValidMsg:
		if msg.valid {
			return m.startInstallation("")
		}
		m.fingerprintFailed = true
		return m, m.delayThenReturn()

	case delayCompleteMsg:
		m.fingerprintFailed = false
		m.selectedAuthMethod = 0
		m.state = StateAuthMethodChoice
		return m, nil
	}
	return m, m.listenForLogs()
}

func (m Model) updatePasswordPromptState(msg tea.Msg) (tea.Model, tea.Cmd) {
	if validMsg, ok := msg.(passwordValidMsg); ok {
		m.authValidating = false
		if validMsg.valid {
			return m.startInstallation(validMsg.password)
		}
		m.authFailed = true
		m.passwordInput.SetValue("")
		m.passwordInput.Focus()
		return m, nil
	}

	if keyMsg, ok := msg.(tea.KeyMsg); ok {
		switch keyMsg.String() {
		case "enter":
			if m.authValidating || m.passwordInput.Value() == "" {
				return m, nil
			}
			m.authValidating = true
			m.authFailed = false
			return m, m.validatePassword(m.passwordInput.Value())
		case "esc":
			m.passwordInput.SetValue("")
			m.authValidating = false
			m.authFailed = false
			m.state = StateDependencyReview
			return m, nil
		}
	}

	var cmd tea.Cmd
	m.passwordInput, cmd = m.passwordInput.Update(msg)
	return m, cmd
}

func checkFingerprintEnabled() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	pamCheck := exec.CommandContext(ctx, "grep", "-q", "pam_fprintd.so", "/etc/pam.d/system-auth")
	if err := pamCheck.Run(); err != nil {
		return false
	}

	user := os.Getenv("USER")
	if user == "" {
		return false
	}

	output, err := exec.CommandContext(ctx, "fprintd-list", user).CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(string(output), "finger")
}

func (m Model) delayThenReturn() tea.Cmd {
	return func() tea.Msg {
		time.Sleep(2 * time.Second)
		return delayCompleteMsg{}
	}
}

// Validates cached credentials without a password by pointing sudo at an
// askpass script that always fails, so only fingerprint/PAM auth can succeed.
func (m Model) tryFingerprint() tea.Cmd {
	return func() tea.Msg {
		_ = privesc.ClearCache(context.Background())

		askpassScript := filepath.Join(os.TempDir(), fmt.Sprintf("dms-fp-%d.sh", time.Now().UnixNano()))
		if err := os.WriteFile(askpassScript, []byte("#!/bin/sh\nexit 1\n"), 0o700); err != nil {
			return passwordValidMsg{valid: false}
		}
		defer os.Remove(askpassScript)

		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()

		if err := privesc.ValidateWithAskpass(ctx, askpassScript); err != nil {
			return passwordValidMsg{valid: false}
		}
		return passwordValidMsg{valid: true}
	}
}

func (m Model) validatePassword(password string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		if err := privesc.ValidatePassword(ctx, password); err != nil {
			return passwordValidMsg{valid: false}
		}
		return passwordValidMsg{password: password, valid: true}
	}
}
