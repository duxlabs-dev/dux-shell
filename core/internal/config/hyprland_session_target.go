package config

import (
	"os"
	"path/filepath"
	"slices"
)

// Mirrors Hyprland's shipped target. Before=graphical-session.target would cycle with the add-wants implicit After=dms.service.
const hyprlandSessionTargetUnit = `[Unit]
Description=Hyprland Session Target
BindsTo=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
PropagatesStopTo=graphical-session.target
`

var staleHyprlandSessionTargetUnits = []string{
	`[Unit]
Description=Hyprland Session Target
Requires=graphical-session.target
After=graphical-session.target
`,
	`[Unit]
Description=Hyprland Session Target
BindsTo=graphical-session.target
Before=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
`,
}

var packagedHyprlandSessionTargetDirs = []string{
	"/usr/lib/systemd/user",
	"/usr/local/lib/systemd/user",
}

// EnsureHyprlandSessionTarget returns the unit path that provides hyprland-session.target.
// Hyprland 0.57+ ships the unit; ours would shadow it, so it is removed then. Hand-written units are left alone.
func EnsureHyprlandSessionTarget() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	userPath := filepath.Join(homeDir, ".config", "systemd", "user", "hyprland-session.target")
	return ensureHyprlandSessionTarget(userPath, packagedHyprlandSessionTargetDirs)
}

func ensureHyprlandSessionTarget(userPath string, packagedDirs []string) (string, error) {
	existing, readErr := os.ReadFile(userPath)
	content := string(existing)
	ours := readErr == nil && (content == hyprlandSessionTargetUnit || slices.Contains(staleHyprlandSessionTargetUnits, content))
	if readErr == nil && !ours {
		return userPath, nil
	}

	if packaged := packagedHyprlandSessionTarget(packagedDirs); packaged != "" {
		if ours {
			if err := os.Remove(userPath); err != nil {
				return "", err
			}
		}
		return packaged, nil
	}

	if content == hyprlandSessionTargetUnit {
		return userPath, nil
	}
	if err := os.MkdirAll(filepath.Dir(userPath), 0o755); err != nil {
		return "", err
	}
	if err := os.WriteFile(userPath, []byte(hyprlandSessionTargetUnit), 0o644); err != nil {
		return "", err
	}
	return userPath, nil
}

func packagedHyprlandSessionTarget(dirs []string) string {
	for _, dir := range dirs {
		path := filepath.Join(dir, "hyprland-session.target")
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}
	return ""
}
