package tui

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
)

type configDeploymentResult struct {
	results []config.DeploymentResult
	error   error
}

type ExistingConfigInfo struct {
	ConfigType string
	Path       string
	Exists     bool
}

type configCheckResult struct {
	configs []ExistingConfigInfo
	error   error
}

func (m Model) viewDeployingConfigs() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Deploying Configurations"))
	b.WriteString("\n\n")
	fmt.Fprintf(&b, "%s %s", m.spinner.View(), m.styles.Normal.Render("Setting up configuration files..."))
	b.WriteString("\n\n")
	b.WriteString(m.styles.Subtle.Render("• Creating backups of existing configurations\n• Deploying optimized configurations\n• Detecting system paths"))

	if len(m.installationLogs) > 0 {
		b.WriteString("\n\n")
		m.writeRecentLogs(&b, m.styles.Subtle.Render("Configuration Log:"), 5)
	}

	return b.String()
}

func (m Model) updateDeployingConfigsState(msg tea.Msg) (tea.Model, tea.Cmd) {
	result, ok := msg.(configDeploymentResult)
	if !ok {
		return m, m.listenForLogs()
	}

	if result.error != nil {
		m.err = result.error
		m.state = StateError
		m.isLoading = false
		return m, nil
	}

	for _, deployResult := range result.results {
		if !deployResult.Deployed {
			continue
		}
		logLine := fmt.Sprintf("✓ %s configuration deployed", deployResult.ConfigType)
		if deployResult.BackupPath != "" {
			logLine += fmt.Sprintf(" (backup: %s)", deployResult.BackupPath)
		}
		m.installationLogs = append(m.installationLogs, logLine)
	}

	if m.isImmutable() {
		clearLayerResume()
	}
	m.state = StateInstallComplete
	m.isLoading = false
	return m, nil
}

func (m Model) deployConfigurations() tea.Cmd {
	return func() tea.Msg {
		deployer := config.NewConfigDeployer(m.logChan)
		results, err := deployer.DeployConfigurationsSelectiveWithReinstallsAndSystemd(
			context.Background(), m.chosenWindowManager(), m.chosenTerminal(),
			m.dependencies, m.replaceConfigs, m.reinstallItems, m.useSystemdConfig())
		return configDeploymentResult{results: results, error: err}
	}
}

func (m Model) optionalDepSelected(name string) bool {
	if m.disabledItems[name] {
		return false
	}
	for _, dep := range m.dependencies {
		if dep.Name == name {
			return true
		}
	}
	return false
}

func (m Model) useSystemdConfig() bool {
	return distros.HasSystemd()
}

func (m Model) viewConfigConfirmation() string {
	var b strings.Builder

	b.WriteString(m.renderBanner())
	b.WriteByte('\n')
	b.WriteString(m.styles.Title.Render("Configuration Deployment"))
	b.WriteString("\n\n")

	if len(m.existingConfigs) == 0 {
		b.WriteString(m.styles.Normal.Render("No existing configurations found. Proceeding with deployment..."))
		return b.String()
	}

	for i, cfg := range m.existingConfigs {
		if !cfg.Exists {
			continue
		}

		marker, status := "🔄 ", m.styles.Warning.Render("Will replace")
		if !m.replaceConfigs[cfg.ConfigType] {
			marker, status = "✓ ", m.styles.Success.Render("Keep existing")
		}

		cursor, style := "  ", m.styles.Normal
		if i == m.selectedConfig {
			cursor, style = "▶ ", m.styles.SelectedOption
		}

		b.WriteString(style.Render(fmt.Sprintf("%s%s%-15s %s\n    %s", cursor, marker, cfg.ConfigType, status, cfg.Path)))
		b.WriteString("\n\n")
	}

	b.WriteString(m.styles.Success.Render("✓ Replaced configurations will be backed up with timestamp"))
	b.WriteString("\n\n")

	if note := m.configReplacementNote(); note != "" {
		b.WriteString(m.styles.Subtle.Render(note))
		b.WriteString("\n\n")
	}

	b.WriteString(m.styles.Subtle.Render("↑/↓: Navigate, Space: Toggle replace/keep, Enter: Continue"))
	return b.String()
}

func (m Model) configReplacementNote() string {
	if m.selectedConfig < 0 || m.selectedConfig >= len(m.existingConfigs) {
		return ""
	}
	configInfo := m.existingConfigs[m.selectedConfig]
	if !configInfo.Exists {
		return ""
	}

	switch configInfo.ConfigType {
	case "Niri":
		if m.useSystemdConfig() {
			return "Replacing Niri writes the DMS Niri template and uses the user systemd dms service for shell autostart."
		}
		return `Replacing Niri writes the DMS Niri template and starts DMS from Niri with spawn-at-startup "dms" "run".`
	case "Hyprland":
		if m.useSystemdConfig() {
			return "Replacing Hyprland writes the DMS Lua template and uses the user systemd dms service for shell autostart."
		}
		return `Replacing Hyprland writes the DMS Lua template and starts DMS from Hyprland with hl.exec_cmd("dms run").`
	case "Mango":
		if m.useSystemdConfig() && mangoconf.SessionTargetInstalled() {
			return "Replacing Mango writes the DMS Mango template and starts the user systemd dms service with mango-session.target. Existing binds, monitor and window rules move into the dms/ files."
		}
		return "Replacing Mango writes the DMS Mango template and starts DMS from Mango with exec_once=dms run. Existing binds, monitor and window rules move into the dms/ files."
	case config.BindsConfigType:
		return "Keep uses your binds as they are; replace starts from the DMS stock binds. A timestamped backup is kept either way."
	case "Ghostty":
		return "Replacing Ghostty writes the DMS terminal defaults and theme include."
	case "Kitty":
		return "Replacing Kitty writes the DMS terminal defaults, theme include, and tab styling."
	case "Alacritty":
		return "Replacing Alacritty writes the DMS terminal defaults and theme import."
	default:
		return ""
	}
}

func (m Model) updateConfigConfirmationState(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case configCheckResult:
		return m.applyConfigCheck(msg)

	case tea.KeyMsg:
		switch msg.String() {
		case "up":
			m.selectedConfig = m.nearestExistingConfig(m.selectedConfig, -1)
		case "down":
			m.selectedConfig = m.nearestExistingConfig(m.selectedConfig, 1)
		case " ":
			if m.selectedConfig < len(m.existingConfigs) && m.existingConfigs[m.selectedConfig].Exists {
				configType := m.existingConfigs[m.selectedConfig].ConfigType
				m.replaceConfigs[configType] = !m.replaceConfigs[configType]
			}
		case "enter":
			m.state = StateDeployingConfigs
			return m, m.deployConfigurations()
		}
	}
	return m, nil
}

func (m Model) applyConfigCheck(result configCheckResult) (tea.Model, tea.Cmd) {
	if result.error != nil {
		m.err = result.error
		m.state = StateError
		return m, nil
	}

	m.existingConfigs = result.configs

	hasExisting := false
	for i, cfg := range result.configs {
		if !cfg.Exists {
			continue
		}
		// Binds are the user's work; replacing them is opt-in.
		m.replaceConfigs[cfg.ConfigType] = cfg.ConfigType != config.BindsConfigType
		if !hasExisting {
			m.selectedConfig = i
		}
		hasExisting = true
	}

	if !hasExisting {
		m.state = StateDeployingConfigs
		return m, m.deployConfigurations()
	}
	return m, nil
}

func (m Model) nearestExistingConfig(from, direction int) int {
	for i := from + direction; i >= 0 && i < len(m.existingConfigs); i += direction {
		if m.existingConfigs[i].Exists {
			return i
		}
	}
	return from
}

func statConfig(configType string, paths ...string) ExistingConfigInfo {
	for _, path := range paths {
		if _, err := os.Stat(path); err == nil {
			return ExistingConfigInfo{ConfigType: configType, Path: path, Exists: true}
		}
	}
	return ExistingConfigInfo{ConfigType: configType, Path: paths[0]}
}

func (m Model) wmConfigInfo() ExistingConfigInfo {
	configDir := filepath.Join(os.Getenv("HOME"), ".config")
	switch m.chosenWindowManager() {
	case deps.WindowManagerNiri:
		return statConfig("Niri", filepath.Join(configDir, "niri", "config.kdl"))
	case deps.WindowManagerMango:
		return statConfig("Mango",
			filepath.Join(configDir, "mango", "config.conf"),
			filepath.Join(configDir, "mango", "mango.conf"))
	default:
		return statConfig("Hyprland", filepath.Join(config.HyprlandConfigDir(), "hyprland.lua"))
	}
}

func (m Model) terminalConfigInfo() ExistingConfigInfo {
	configDir := filepath.Join(os.Getenv("HOME"), ".config")
	switch m.chosenTerminal() {
	case deps.TerminalGhostty:
		return statConfig("Ghostty", filepath.Join(configDir, "ghostty", "config"))
	case deps.TerminalKitty:
		return statConfig("Kitty", filepath.Join(configDir, "kitty", "kitty.conf"))
	default:
		return statConfig("Alacritty", filepath.Join(configDir, "alacritty", "alacritty.toml"))
	}
}

func (m Model) checkExistingConfigurations() tea.Cmd {
	return func() tea.Msg {
		configs := []ExistingConfigInfo{m.wmConfigInfo()}
		if path, ok := config.ExistingBinds(m.chosenWindowManager()); ok {
			configs = append(configs, ExistingConfigInfo{ConfigType: config.BindsConfigType, Path: path, Exists: true})
		}
		return configCheckResult{configs: append(configs, m.terminalConfigInfo())}
	}
}
