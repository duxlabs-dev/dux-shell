package config

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Tests never reach the user's systemd; stubAddWants counts the add-wants calls a deploy makes.
func TestMain(m *testing.M) {
	systemctlUser = func(...string) error { return nil }
	// Hyprland paths follow XDG_CONFIG_HOME; tests pin HOME and must not write a real config.
	os.Unsetenv("XDG_CONFIG_HOME")
	os.Exit(m.Run())
}

func stubAddWants(t *testing.T, addWants error) *int {
	t.Helper()
	calls := 0
	prev := systemctlUser
	systemctlUser = func(args ...string) error {
		if args[0] != "add-wants" {
			return nil
		}
		calls++
		return addWants
	}
	t.Cleanup(func() { systemctlUser = prev })
	return &calls
}

func TestMergeNiriOutputSections(t *testing.T) {
	cd := &ConfigDeployer{}

	tests := []struct {
		name           string
		newConfig      string
		existingConfig string
		wantError      bool
		wantContains   []string
	}{
		{
			name: "no existing outputs",
			newConfig: `input {
    keyboard {
        xkb {
        }
    }
}
layout {
    gaps 5
}`,
			existingConfig: `input {
    keyboard {
        xkb {
        }
    }
}
layout {
    gaps 10
}`,
			wantError:    false,
			wantContains: []string{"gaps 5"}, // Should keep new config
		},
		{
			name: "merge multiple outputs",
			newConfig: `input {
    keyboard {
        xkb {
        }
    }
}
/-output "eDP-2" {
    mode "2560x1600@239.998993"
    position x=2560 y=0
}
layout {
    gaps 5
}`,
			existingConfig: `input {
    keyboard {
        xkb {
        }
    }
}
output "eDP-1" {
    mode "1920x1080@60.000000"
    position x=0 y=0
    scale 1.0
}
/-output "HDMI-1" {
    mode "1920x1080@60.000000"
    position x=1920 y=0
}
layout {
    gaps 10
}`,
			wantError: false,
			wantContains: []string{
				"gaps 5",                              // New config preserved
				`output "eDP-1"`,                      // First existing output
				`/-output "HDMI-1"`,                   // Second existing output (commented)
				"1920x1080@60.000000",                 // Output details
				"Outputs from existing configuration", // Comment added
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			result, err := cd.mergeNiriOutputSections(tt.newConfig, tt.existingConfig, tmpDir)

			if tt.wantError {
				assert.Error(t, err)
				return
			}

			require.NoError(t, err)

			for _, want := range tt.wantContains {
				assert.Contains(t, result, want, "merged config should contain: %s", want)
			}

			assert.NotContains(t, result, `/-output "eDP-2"`, "example output should be removed")
		})
	}
}

func TestConfigDeploymentFlow(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "duxinstall-test")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", tempDir)
	defer os.Setenv("HOME", originalHome)

	logChan := make(chan string, 100)
	cd := NewConfigDeployer(logChan)

	t.Run("deploy ghostty config to empty directory", func(t *testing.T) {
		results, err := cd.deployGhosttyConfig()
		require.NoError(t, err)
		require.Len(t, results, 2)

		mainResult := results[0]
		assert.Equal(t, "Ghostty", mainResult.ConfigType)
		assert.True(t, mainResult.Deployed)
		assert.Empty(t, mainResult.BackupPath)
		assert.FileExists(t, mainResult.Path)

		content, err := os.ReadFile(mainResult.Path)
		require.NoError(t, err)
		assert.Contains(t, string(content), "window-decoration = false")

		colorResult := results[1]
		assert.Equal(t, "Ghostty Colors", colorResult.ConfigType)
		assert.True(t, colorResult.Deployed)
		assert.FileExists(t, colorResult.Path)

		colorContent, err := os.ReadFile(colorResult.Path)
		require.NoError(t, err)
		assert.Contains(t, string(colorContent), "background = #101418")
	})

	t.Run("deploy ghostty config with existing file", func(t *testing.T) {
		existingContent := "# Old config\nfont-size = 14\n"
		ghosttyPath := getGhosttyPath()
		err := os.MkdirAll(filepath.Dir(ghosttyPath), 0o755)
		require.NoError(t, err)
		err = os.WriteFile(ghosttyPath, []byte(existingContent), 0o644)
		require.NoError(t, err)

		results, err := cd.deployGhosttyConfig()
		require.NoError(t, err)
		require.Len(t, results, 2)

		mainResult := results[0]
		assert.Equal(t, "Ghostty", mainResult.ConfigType)
		assert.True(t, mainResult.Deployed)
		assert.NotEmpty(t, mainResult.BackupPath)
		assert.FileExists(t, mainResult.Path)
		assert.FileExists(t, mainResult.BackupPath)

		backupContent, err := os.ReadFile(mainResult.BackupPath)
		require.NoError(t, err)
		assert.Equal(t, existingContent, string(backupContent))

		newContent, err := os.ReadFile(mainResult.Path)
		require.NoError(t, err)
		assert.NotContains(t, string(newContent), "# Old config")

		colorResult := results[1]
		assert.Equal(t, "Ghostty Colors", colorResult.ConfigType)
		assert.True(t, colorResult.Deployed)
		assert.FileExists(t, colorResult.Path)
	})
}

func getGhosttyPath() string {
	return filepath.Join(os.Getenv("HOME"), ".config", "ghostty", "config")
}

func TestHyprlandConfigDeployment(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "duxinstall-hyprland-test")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", tempDir)
	defer os.Setenv("HOME", originalHome)

	logChan := make(chan string, 100)
	cd := NewConfigDeployer(logChan)

	t.Run("deploy hyprland config to empty directory", func(t *testing.T) {
		td, err := os.MkdirTemp("", "duxinstall-hyprland-empty")
		require.NoError(t, err)
		defer os.RemoveAll(td)
		os.Setenv("HOME", td)
		result, err := cd.deployHyprlandConfig("ghostty", true)
		require.NoError(t, err)

		assert.Equal(t, "Hyprland", result.ConfigType)
		assert.True(t, result.Deployed)
		assert.Empty(t, result.BackupPath)
		assert.FileExists(t, result.Path)

		content, err := os.ReadFile(result.Path)
		require.NoError(t, err)
		assert.Contains(t, string(content), `require("dms.binds")`)
		assert.Contains(t, string(content), "DMS_STARTUP_BEGIN")
		assert.Contains(t, string(content), "hl.config(")
	})

	t.Run("deploy hyprland config backs up the existing hyprland.lua", func(t *testing.T) {
		td, err := os.MkdirTemp("", "duxinstall-hyprland-backup")
		require.NoError(t, err)
		defer os.RemoveAll(td)
		os.Setenv("HOME", td)
		existing := "hl.config({ autogenerated = true })\n"
		luaPath := filepath.Join(td, ".config", "hypr", "hyprland.lua")
		require.NoError(t, os.MkdirAll(filepath.Dir(luaPath), 0o755))
		require.NoError(t, os.WriteFile(luaPath, []byte(existing), 0o644))

		result, err := cd.deployHyprlandConfig("kitty", true)
		require.NoError(t, err)

		assert.Contains(t, result.BackupPath, hyprlandBackupDirName)
		backup, err := os.ReadFile(result.BackupPath)
		require.NoError(t, err)
		assert.Equal(t, existing, string(backup))
		content, err := os.ReadFile(result.Path)
		require.NoError(t, err)
		assert.Contains(t, string(content), `require("dms.binds")`)
		assert.NotContains(t, string(content), "autogenerated")
	})

	t.Run("deploy hyprland config refreshes managed binds but preserves user binds", func(t *testing.T) {
		td, err := os.MkdirTemp("", "duxinstall-hyprland-refresh-binds")
		require.NoError(t, err)
		defer os.RemoveAll(td)
		os.Setenv("HOME", td)

		dmsDir := filepath.Join(td, ".config", "hypr", "dms")
		require.NoError(t, os.MkdirAll(dmsDir, 0o755))
		require.NoError(t, os.WriteFile(filepath.Join(dmsDir, "binds.lua"), []byte("-- stale managed binds\n"), 0o644))
		userBinds := "-- custom user binds\n"
		require.NoError(t, os.WriteFile(filepath.Join(dmsDir, "binds-user.lua"), []byte(userBinds), 0o644))

		_, err = cd.deployHyprlandConfig("kitty", true)
		require.NoError(t, err)

		managed, err := os.ReadFile(filepath.Join(dmsDir, "binds.lua"))
		require.NoError(t, err)
		assert.Contains(t, string(managed), `hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))`)
		assert.Contains(t, string(managed), `hl.bind("SUPER + minus", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true })`)

		user, err := os.ReadFile(filepath.Join(dmsDir, "binds-user.lua"))
		require.NoError(t, err)
		assert.Equal(t, userBinds, string(user))
	})
}

func TestKittyConfigDeployment(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "duxinstall-kitty-test")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", tempDir)
	defer os.Setenv("HOME", originalHome)

	logChan := make(chan string, 100)
	cd := NewConfigDeployer(logChan)

	t.Run("deploy kitty config to empty directory", func(t *testing.T) {
		results, err := cd.deployKittyConfig()
		require.NoError(t, err)
		require.Len(t, results, 3)

		mainResult := results[0]
		assert.Equal(t, "Kitty", mainResult.ConfigType)
		assert.True(t, mainResult.Deployed)
		assert.FileExists(t, mainResult.Path)

		content, err := os.ReadFile(mainResult.Path)
		require.NoError(t, err)
		assert.Contains(t, string(content), "include dank-theme.conf")

		themeResult := results[1]
		assert.Equal(t, "Kitty Theme", themeResult.ConfigType)
		assert.True(t, themeResult.Deployed)
		assert.FileExists(t, themeResult.Path)

		tabsResult := results[2]
		assert.Equal(t, "Kitty Tabs", tabsResult.ConfigType)
		assert.True(t, tabsResult.Deployed)
		assert.FileExists(t, tabsResult.Path)
	})
}

func TestAlacrittyConfigDeployment(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "duxinstall-alacritty-test")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", tempDir)
	defer os.Setenv("HOME", originalHome)

	logChan := make(chan string, 100)
	cd := NewConfigDeployer(logChan)

	t.Run("deploy alacritty config to empty directory", func(t *testing.T) {
		results, err := cd.deployAlacrittyConfig()
		require.NoError(t, err)
		require.Len(t, results, 2)

		mainResult := results[0]
		assert.Equal(t, "Alacritty", mainResult.ConfigType)
		assert.True(t, mainResult.Deployed)
		assert.FileExists(t, mainResult.Path)

		content, err := os.ReadFile(mainResult.Path)
		require.NoError(t, err)
		assert.Contains(t, string(content), "~/.config/alacritty/dank-theme.toml")
		assert.Contains(t, string(content), "[window]")

		themeResult := results[1]
		assert.Equal(t, "Alacritty Theme", themeResult.ConfigType)
		assert.True(t, themeResult.Deployed)
		assert.FileExists(t, themeResult.Path)

		themeContent, err := os.ReadFile(themeResult.Path)
		require.NoError(t, err)
		assert.Contains(t, string(themeContent), "[colors.primary]")
		assert.Contains(t, string(themeContent), "background = '#101418'")
	})

	t.Run("deploy alacritty config with existing file", func(t *testing.T) {
		existingContent := "# Old alacritty config\n[window]\nopacity = 0.9\n"
		alacrittyPath := filepath.Join(tempDir, ".config", "alacritty", "alacritty.toml")
		err := os.MkdirAll(filepath.Dir(alacrittyPath), 0o755)
		require.NoError(t, err)
		err = os.WriteFile(alacrittyPath, []byte(existingContent), 0o644)
		require.NoError(t, err)

		results, err := cd.deployAlacrittyConfig()
		require.NoError(t, err)
		require.Len(t, results, 2)

		mainResult := results[0]
		assert.True(t, mainResult.Deployed)
		assert.NotEmpty(t, mainResult.BackupPath)
		assert.FileExists(t, mainResult.BackupPath)

		backupContent, err := os.ReadFile(mainResult.BackupPath)
		require.NoError(t, err)
		assert.Equal(t, existingContent, string(backupContent))

		newContent, err := os.ReadFile(mainResult.Path)
		require.NoError(t, err)
		assert.NotContains(t, string(newContent), "# Old alacritty config")
		assert.Contains(t, string(newContent), "decorations = \"None\"")
	})
}

func TestShouldReplaceConfigDeployIfMissing(t *testing.T) {
	allFalse := map[string]bool{
		"Niri":      false,
		"Hyprland":  false,
		"Ghostty":   false,
		"Kitty":     false,
		"Alacritty": false,
	}

	t.Run("replaceConfigs nil deploys config", func(t *testing.T) {
		tempDir, err := os.MkdirTemp("", "duxinstall-replace-nil-test")
		require.NoError(t, err)
		defer os.RemoveAll(tempDir)

		originalHome := os.Getenv("HOME")
		os.Setenv("HOME", tempDir)
		defer os.Setenv("HOME", originalHome)

		logChan := make(chan string, 100)
		cd := NewConfigDeployer(logChan)

		results, err := cd.DeployConfigurationsSelectiveWithReinstalls(
			context.Background(),
			deps.WindowManagerNiri,
			deps.TerminalGhostty,
			nil, // installedDeps
			nil, // replaceConfigs
			nil, // reinstallItems
		)
		require.NoError(t, err)

		// With replaceConfigs=nil, all configs should be deployed
		hasDeployed := false
		for _, r := range results {
			if r.Deployed {
				hasDeployed = true
				break
			}
		}
		assert.True(t, hasDeployed, "expected at least one config to be deployed when replaceConfigs is nil")
	})

	t.Run("replaceConfigs all false and config missing deploys config", func(t *testing.T) {
		tempDir, err := os.MkdirTemp("", "duxinstall-replace-missing-test")
		require.NoError(t, err)
		defer os.RemoveAll(tempDir)

		originalHome := os.Getenv("HOME")
		os.Setenv("HOME", tempDir)
		defer os.Setenv("HOME", originalHome)

		logChan := make(chan string, 100)
		cd := NewConfigDeployer(logChan)

		results, err := cd.DeployConfigurationsSelectiveWithReinstalls(
			context.Background(),
			deps.WindowManagerNiri,
			deps.TerminalGhostty,
			nil,      // installedDeps
			allFalse, // replaceConfigs — all false
			nil,      // reinstallItems
		)
		require.NoError(t, err)

		// Config files don't exist on disk, so they should still be deployed
		hasDeployed := false
		for _, r := range results {
			if r.Deployed {
				hasDeployed = true
				break
			}
		}
		assert.True(t, hasDeployed, "expected configs to be deployed when files are missing, even with replaceConfigs all false")
	})

	t.Run("replaceConfigs false and config exists skips config", func(t *testing.T) {
		tempDir, err := os.MkdirTemp("", "duxinstall-replace-exists-test")
		require.NoError(t, err)
		defer os.RemoveAll(tempDir)

		originalHome := os.Getenv("HOME")
		os.Setenv("HOME", tempDir)
		defer os.Setenv("HOME", originalHome)

		// Create the Ghostty primary config file so shouldReplaceConfig returns false
		ghosttyPath := filepath.Join(tempDir, ".config", "ghostty", "config")
		err = os.MkdirAll(filepath.Dir(ghosttyPath), 0o755)
		require.NoError(t, err)
		err = os.WriteFile(ghosttyPath, []byte("# existing ghostty config\n"), 0o644)
		require.NoError(t, err)

		// Also create the Niri primary config file
		niriPath := filepath.Join(tempDir, ".config", "niri", "config.kdl")
		err = os.MkdirAll(filepath.Dir(niriPath), 0o755)
		require.NoError(t, err)
		err = os.WriteFile(niriPath, []byte("// existing niri config\n"), 0o644)
		require.NoError(t, err)

		logChan := make(chan string, 100)
		cd := NewConfigDeployer(logChan)

		results, err := cd.DeployConfigurationsSelectiveWithReinstalls(
			context.Background(),
			deps.WindowManagerNiri,
			deps.TerminalGhostty,
			nil,      // installedDeps
			allFalse, // replaceConfigs — all false
			nil,      // reinstallItems
		)
		require.NoError(t, err)

		// Both Niri and Ghostty config files exist, so with all false they should be skipped
		for _, r := range results {
			assert.Fail(t, "expected no configs to be deployed", "got deployed config: %s", r.ConfigType)
		}
	})

	t.Run("replaceConfigs true and config exists deploys config", func(t *testing.T) {
		tempDir, err := os.MkdirTemp("", "duxinstall-replace-true-test")
		require.NoError(t, err)
		defer os.RemoveAll(tempDir)

		originalHome := os.Getenv("HOME")
		os.Setenv("HOME", tempDir)
		defer os.Setenv("HOME", originalHome)

		// Create the Ghostty primary config file
		ghosttyPath := filepath.Join(tempDir, ".config", "ghostty", "config")
		err = os.MkdirAll(filepath.Dir(ghosttyPath), 0o755)
		require.NoError(t, err)
		err = os.WriteFile(ghosttyPath, []byte("# existing ghostty config\n"), 0o644)
		require.NoError(t, err)

		logChan := make(chan string, 100)
		cd := NewConfigDeployer(logChan)

		replaceConfigs := map[string]bool{
			"Niri":      false,
			"Hyprland":  false,
			"Ghostty":   true, // explicitly true
			"Kitty":     false,
			"Alacritty": false,
		}

		results, err := cd.DeployConfigurationsSelectiveWithReinstalls(
			context.Background(),
			deps.WindowManagerNiri,
			deps.TerminalGhostty,
			nil,            // installedDeps
			replaceConfigs, // Ghostty=true, rest=false
			nil,            // reinstallItems
		)
		require.NoError(t, err)

		// Ghostty should be deployed because replaceConfigs["Ghostty"]=true
		foundGhostty := false
		for _, r := range results {
			if r.ConfigType == "Ghostty" && r.Deployed {
				foundGhostty = true
			}
		}
		assert.True(t, foundGhostty, "expected Ghostty config to be deployed when replaceConfigs is true")
	})

}

func TestBackupHyprlandConfigFileKeepsExistingBackups(t *testing.T) {
	backupDir := t.TempDir()
	dst := filepath.Join(backupDir, "hyprland.lua")
	require.NoError(t, os.WriteFile(dst, []byte("-- first\n"), 0o644))

	written, err := backupHyprlandConfigFile(dst, []byte("-- second\n"))
	require.NoError(t, err)
	assert.Equal(t, dst+".1", written)

	first, err := os.ReadFile(dst)
	require.NoError(t, err)
	assert.Equal(t, "-- first\n", string(first))
}

func TestDeployHyprlandConfigSystemdAutostart(t *testing.T) {
	cases := []struct {
		name       string
		useSystemd bool
		addWants   error
		wantExec   bool
		wantCalls  int
		wantLink   bool
	}{
		{"systemd", true, nil, false, 1, true},
		{"add-wants fails", true, errors.New("no user bus"), true, 1, true},
		{"no systemd", false, nil, true, 0, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			home := t.TempDir()
			t.Setenv("HOME", home)
			calls := stubAddWants(t, tc.addWants)
			link := WantsLink(HyprlandSessionTarget)
			require.NoError(t, os.MkdirAll(filepath.Dir(link), 0o755))
			require.NoError(t, os.Symlink("/dev/null", link))

			result, err := NewConfigDeployer(nil).deployHyprlandConfig("kitty", tc.useSystemd)
			require.NoError(t, err)
			content, err := os.ReadFile(result.Path)
			require.NoError(t, err)
			assert.Equal(t, tc.wantExec, strings.Contains(string(content), `hl.exec_cmd("dms run")`))
			assert.Equal(t, !tc.wantExec, strings.Contains(string(content), "systemctl --user start hyprland-session.target"))
			assert.Equal(t, tc.wantCalls, *calls)
			_, statErr := os.Lstat(link)
			assert.Equal(t, tc.wantLink, statErr == nil)
		})
	}
}

func TestDeployHyprlandStartsShellInLiveSession(t *testing.T) {
	cases := []struct {
		name        string
		instance    string
		unitActive  bool
		useSystemd  bool
		wantStarted bool
	}{
		{"live session", "sig", true, true, true},
		{"session unit inactive", "sig", false, true, false},
		{"other session", "", true, true, false},
		{"no systemd", "sig", true, false, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("HOME", t.TempDir())
			t.Setenv("HYPRLAND_INSTANCE_SIGNATURE", tc.instance)
			t.Setenv("NIRI_SOCKET", "")
			t.Setenv("MANGO_INSTANCE_SIGNATURE", "")
			started := false
			prev := systemctlUser
			systemctlUser = func(args ...string) error {
				switch args[0] {
				case "is-active":
					if !tc.unitActive {
						return errors.New("inactive")
					}
				case "start":
					started = true
				}
				return nil
			}
			t.Cleanup(func() { systemctlUser = prev })

			_, err := NewConfigDeployer(nil).deployHyprlandConfig("kitty", tc.useSystemd)
			require.NoError(t, err)
			assert.Equal(t, tc.wantStarted, started)
		})
	}
}

func TestDeployNiriConfigSystemdAutostart(t *testing.T) {
	cases := []struct {
		name       string
		useSystemd bool
		addWants   error
		wantSpawn  bool
		wantCalls  int
	}{
		{"systemd", true, nil, false, 1},
		{"add-wants fails", true, errors.New("no user bus"), true, 1},
		{"no systemd", false, nil, true, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("HOME", t.TempDir())
			calls := stubAddWants(t, tc.addWants)
			result, err := NewConfigDeployer(nil).deployNiriConfig("kitty", tc.useSystemd)
			require.NoError(t, err)
			content, err := os.ReadFile(result.Path)
			require.NoError(t, err)
			assert.Equal(t, tc.wantSpawn, strings.Contains(string(content), `spawn-at-startup "dms" "run"`))
			assert.Equal(t, tc.wantCalls, *calls)
		})
	}
}

func TestHyprlandLuaUnsupported(t *testing.T) {
	for ver, refuse := range map[string]bool{
		"0.54.2": true,
		"0.55.0": false,
		"":       false,
	} {
		err := hyprlandLuaUnsupported(ver)
		assert.Equal(t, refuse, err != nil, ver)
	}
}

func TestNiriDeployBindsChoiceAlwaysBacksUp(t *testing.T) {
	for _, replace := range []bool{false, true} {
		home := t.TempDir()
		t.Setenv("HOME", home)
		dms := filepath.Join(home, ".config", "niri", "dms")
		require.NoError(t, os.MkdirAll(dms, 0o755))
		user := "binds {\n    Mod+X { close-window; }\n}\n"
		require.NoError(t, os.WriteFile(filepath.Join(dms, "binds.kdl"), []byte(user), 0o644))

		cd := NewConfigDeployer(nil)
		cd.SetReplaceBinds(replace)
		_, err := cd.DeployCompositor(deps.WindowManagerNiri, "kitty", false)
		require.NoError(t, err)

		backups, _ := filepath.Glob(filepath.Join(dms, "binds.kdl.backup.*"))
		assert.Len(t, backups, 1, "replace=%v", replace)
		got, err := os.ReadFile(filepath.Join(dms, "binds.kdl"))
		require.NoError(t, err)
		assert.Equal(t, !replace, string(got) == user, "replace=%v", replace)
		if replace {
			assert.Contains(t, string(got), "spawn \"kitty\"")
		}
	}
}

func TestNiriReplaceBindsKeepsMainConfig(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dmsDir := filepath.Join(home, ".config", "niri", "dms")
	require.NoError(t, os.MkdirAll(dmsDir, 0o755))
	mainPath := filepath.Join(filepath.Dir(dmsDir), "config.kdl")
	main := "// user config\ninclude \"dms/binds.kdl\"\n"
	require.NoError(t, os.WriteFile(mainPath, []byte(main), 0o644))
	bindsPath := filepath.Join(dmsDir, "binds.kdl")
	userBinds := "binds { Mod+X { close-window; } }\n"
	require.NoError(t, os.WriteFile(bindsPath, []byte(userBinds), 0o644))
	colorsPath := filepath.Join(dmsDir, "colors.kdl")
	colors := "// user colors\n"
	require.NoError(t, os.WriteFile(colorsPath, []byte(colors), 0o644))
	kittyPath := filepath.Join(home, ".config", "kitty", "kitty.conf")
	require.NoError(t, os.MkdirAll(filepath.Dir(kittyPath), 0o755))
	require.NoError(t, os.WriteFile(kittyPath, []byte("# user terminal\n"), 0o644))

	cd := NewConfigDeployer(nil)
	results, err := cd.DeployConfigurationsSelectiveWithReinstallsAndSystemd(
		context.Background(), deps.WindowManagerNiri, deps.TerminalKitty, nil,
		map[string]bool{"Niri": false, "Kitty": false, BindsConfigType: true}, nil, false,
	)
	require.NoError(t, err)
	got, err := os.ReadFile(bindsPath)
	require.NoError(t, err)
	assert.Equal(t, strings.ReplaceAll(NiriBindsConfig, "{{TERMINAL_COMMAND}}", "kitty"), string(got))
	backups, err := filepath.Glob(bindsPath + ".backup.*")
	require.NoError(t, err)
	require.Len(t, backups, 1)
	backup, err := os.ReadFile(backups[0])
	require.NoError(t, err)
	assert.Equal(t, userBinds, string(backup))
	for path, want := range map[string]string{mainPath: main, colorsPath: colors} {
		got, err := os.ReadFile(path)
		require.NoError(t, err)
		assert.Equal(t, want, string(got), path)
	}
	mainBackups, err := filepath.Glob(mainPath + ".backup.*")
	require.NoError(t, err)
	assert.Empty(t, mainBackups)
	require.Len(t, results, 1)
	assert.Equal(t, BindsConfigType, results[0].ConfigType)
	assert.True(t, results[0].Deployed)
}

func TestDeployBindsFileReadErrorPreservesExistingFile(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root can read files without read permission")
	}
	for _, replace := range []bool{false, true} {
		path := filepath.Join(t.TempDir(), "binds.kdl")
		user := "binds { Mod+X { close-window; } }\n"
		require.NoError(t, os.WriteFile(path, []byte(user), 0o200))
		_, err := os.ReadFile(path)
		require.ErrorIs(t, err, os.ErrPermission)

		cd := NewConfigDeployer(nil)
		cd.SetReplaceBinds(replace)
		assert.ErrorIs(t, cd.deployBindsFile(path, "stock binds\n"), os.ErrPermission, "replace=%v", replace)
		require.NoError(t, os.Chmod(path, 0o600))
		got, err := os.ReadFile(path)
		require.NoError(t, err)
		assert.Equal(t, user, string(got), "replace=%v", replace)
		backups, err := filepath.Glob(path + ".backup.*")
		require.NoError(t, err)
		assert.Empty(t, backups)
	}
}
