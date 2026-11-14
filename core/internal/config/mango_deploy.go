package config

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
)

// BindsConfigType is the replaceConfigs key choosing stock DMS binds over the user's.
const BindsConfigType = "Keybinds"

// SetReplaceBinds picks the DMS stock binds over existing ones; existing binds are kept by default.
func (cd *ConfigDeployer) SetReplaceBinds(replace bool) {
	cd.replaceBinds = replace
}

// ExistingBinds returns where the user's keybinds for wm live, if any. Hyprland
// is absent on purpose: its binds.lua is DMS-owned and user binds sit in binds-user.lua.
func ExistingBinds(wm deps.WindowManager) (string, bool) {
	switch wm {
	case deps.WindowManagerNiri:
		return nonEmptyFile(filepath.Join(os.Getenv("HOME"), ".config", "niri", "dms", "binds.kdl"))
	case deps.WindowManagerMango:
		return MangoExistingBinds()
	}
	return "", false
}

func nonEmptyFile(path string) (string, bool) {
	info, err := os.Stat(path)
	if err != nil || info.Size() == 0 {
		return "", false
	}
	return path, true
}

var (
	mangoBindLine    = regexp.MustCompile(`^\s*((bind|mousebind|axisbind|gesturebind|switchbind)[a-z]*|key_mode)\s*=`)
	mangoMonitorLine = regexp.MustCompile(`^\s*monitor_rule\s*=`)
	mangoWindowLine  = regexp.MustCompile(`^\s*window_rule(_once)?\s*=`)
	mangoExecOnceDMS = regexp.MustCompile(`(?m)^# Starts the shell when DMS.*\n#.*\nexec_once( = "dms run"|=dms run)\n`)
)

var (
	mangoSessionTargetInstalled = mangoconf.SessionTargetInstalled
)

// config.toml binds are left out: replacing it never carries them.
func MangoExistingBinds() (string, bool) {
	dir := mangoconf.Dir()
	bindsPath := filepath.Join(dir, "dms", "binds.conf")
	if info, err := os.Stat(bindsPath); err == nil && info.Size() > 0 {
		return bindsPath, true
	}
	mainPath := mangoconf.MainConfig(dir)
	if mangoconf.IsTOML(mainPath) {
		return "", false
	}
	data, err := os.ReadFile(mainPath)
	if err != nil || extractMangoLines(string(data), mangoBindLine) == "" {
		return "", false
	}
	return mainPath, true
}

func extractMangoLines(text string, match *regexp.Regexp) string {
	var out []string
	for line := range strings.SplitSeq(text, "\n") {
		if match.MatchString(line) {
			out = append(out, strings.TrimSpace(line))
		}
	}
	if len(out) == 0 {
		return ""
	}
	return strings.Join(out, "\n") + "\n"
}

func (cd *ConfigDeployer) deployMangoConfig(terminalCommand string, useSystemd bool) (DeploymentResult, error) {
	configDir := mangoconf.Dir()
	// A config.toml in use is replaced by the TOML template, so Mango keeps loading the same file.
	mainPath := mangoconf.MainConfig(configDir)
	toml := mangoconf.IsTOML(mainPath)
	result := DeploymentResult{ConfigType: "Mango", Path: mainPath}

	// A config that can't be read can't be backed up, so nothing may be written.
	data, err := os.ReadFile(mainPath)
	if err != nil && !os.IsNotExist(err) {
		result.Error = fmt.Errorf("failed to read %s: %w", mainPath, err)
		return result, result.Error
	}

	dmsDir := filepath.Join(configDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		result.Error = fmt.Errorf("failed to create dms directory: %w", err)
		return result, result.Error
	}

	timestamp := time.Now().Format("2006-01-02_15-04-05")
	var existing string
	if err == nil {
		cd.log("Found existing Mango configuration")
		result.BackupPath = mainPath + ".backup." + timestamp
		if err := os.WriteFile(result.BackupPath, data, 0o644); err != nil {
			result.Error = fmt.Errorf("failed to create backup: %w", err)
			return result, result.Error
		}
		cd.log(fmt.Sprintf("Backed up existing config to %s", result.BackupPath))
		if toml {
			cd.log(fmt.Sprintf("Binds and rules from config.toml are not carried over; copy what you need from %s", result.BackupPath))
		} else {
			existing = string(data)
		}
	}

	template := MangoConfig
	if toml {
		template = MangoTOMLConfig
	}
	newConfig := strings.ReplaceAll(template, "{{TERMINAL_COMMAND}}", terminalCommand)
	autostart := cd.systemdAutostart(deps.WindowManagerMango, useSystemd)
	if autostart {
		newConfig = mangoExecOnceDMS.ReplaceAllString(newConfig, "")
	}

	if err := cd.deployMangoDmsConfigs(dmsDir, terminalCommand, existing, timestamp); err != nil {
		result.Error = fmt.Errorf("failed to deploy dms configs: %w", err)
		return result, result.Error
	}

	if err := os.WriteFile(result.Path, []byte(newConfig), 0o644); err != nil {
		result.Error = fmt.Errorf("failed to write config: %w", err)
		return result, result.Error
	}

	if autostart {
		cd.startInLiveSession(deps.WindowManagerMango)
	}

	result.Deployed = true
	cd.log("Successfully deployed Mango configuration")
	return result, nil
}

// Like niri, fragments the user or the shell already filled are left alone; the
// replaced config.conf hands its binds, monitor and window rules to empty ones.
func (cd *ConfigDeployer) deployMangoDmsConfigs(dmsDir, terminalCommand, oldMain, timestamp string) error {
	stockBinds := strings.ReplaceAll(MangoBindsConfig, "{{TERMINAL_COMMAND}}", terminalCommand)
	bindsPath := filepath.Join(dmsDir, "binds.conf")
	if data, err := os.ReadFile(bindsPath); err == nil && len(data) > 0 {
		backup := bindsPath + ".backup." + timestamp
		if err := os.WriteFile(backup, data, 0o644); err != nil {
			return fmt.Errorf("failed to back up binds.conf: %w", err)
		}
		cd.log(fmt.Sprintf("Backed up existing binds to %s", backup))
		if cd.replaceBinds {
			if err := os.WriteFile(bindsPath, []byte(stockBinds), 0o644); err != nil {
				return fmt.Errorf("failed to write binds.conf: %w", err)
			}
			cd.log("Deployed DMS stock binds.conf")
		} else {
			if !mangoconf.HasUserBindsHeader(string(data)) {
				if err := os.WriteFile(bindsPath, append([]byte(mangoconf.BindsKeptHeader+"\n"), data...), 0o644); err != nil {
					return fmt.Errorf("failed to write binds.conf: %w", err)
				}
			}
			cd.log("Keeping existing binds.conf")
		}
	} else {
		binds := stockBinds
		if old := extractMangoLines(oldMain, mangoBindLine); old != "" && !cd.replaceBinds {
			binds = mangoconf.BindsMovedHeader + "\n" + old
			cd.log("Moved existing binds from config.conf to binds.conf")
		}
		if err := os.WriteFile(bindsPath, []byte(binds), 0o644); err != nil {
			return fmt.Errorf("failed to write binds.conf: %w", err)
		}
	}

	configs := []struct {
		name    string
		content string
	}{
		{"colors.conf", MangoColorsConfig},
		{"layout.conf", MangoLayoutConfig},
		{"animations.conf", MangoAnimationsConfig},
		{"outputs.conf", extractMangoLines(oldMain, mangoMonitorLine)},
		{"cursor.conf", ""},
		{"input.conf", ""},
		{"windowrules.conf", extractMangoLines(oldMain, mangoWindowLine)},
	}
	for _, cfg := range configs {
		path := filepath.Join(dmsDir, cfg.name)
		if info, err := os.Stat(path); err == nil && info.Size() > 0 {
			cd.log(fmt.Sprintf("Skipping %s (already exists)", cfg.name))
			continue
		}
		if err := os.WriteFile(path, []byte(cfg.content), 0o644); err != nil {
			return fmt.Errorf("failed to write %s: %w", cfg.name, err)
		}
		cd.log(fmt.Sprintf("Deployed %s", cfg.name))
	}
	return nil
}
