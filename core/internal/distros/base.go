package distros

import (
	"bufio"
	"context"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/netfetch"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
	"github.com/duxlabs-dev/dux-shell/core/internal/version"
)

const (
	forceQuickshellGit = false
	forceDMSGit        = false
)

// BaseDistribution provides common functionality for all distributions
type BaseDistribution struct {
	logChan chan<- string
}

// NewBaseDistribution creates a new base distribution
func NewBaseDistribution(logChan chan<- string) *BaseDistribution {
	return &BaseDistribution{
		logChan: logChan,
	}
}

// Common helper methods
func (b *BaseDistribution) commandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

func (b *BaseDistribution) CommandExists(cmd string) bool {
	return b.commandExists(cmd)
}

func (b *BaseDistribution) log(message string) {
	if b.logChan != nil {
		b.logChan <- message
	}
}

func (b *BaseDistribution) logError(message string, err error) {
	errorMsg := fmt.Sprintf("ERROR: %s: %v", message, err)
	b.log(errorMsg)
}

func (b *BaseDistribution) detectCommand(name, description string) deps.Dependency {
	status := deps.StatusMissing
	if b.commandExists(name) {
		status = deps.StatusInstalled
	}
	return deps.Dependency{
		Name:        name,
		Status:      status,
		Description: description,
		Required:    true,
	}
}

func (b *BaseDistribution) detectPackage(name, description string, installed bool) deps.Dependency {
	status := deps.StatusMissing
	if installed {
		status = deps.StatusInstalled
	}
	return deps.Dependency{
		Name:        name,
		Status:      status,
		Description: description,
		Required:    true,
	}
}

func (b *BaseDistribution) detectOptionalPackage(name, description string, installed bool) deps.Dependency {
	status := deps.StatusMissing
	if installed {
		status = deps.StatusInstalled
	}
	return deps.Dependency{
		Name:        name,
		Status:      status,
		Description: description,
		Required:    false,
	}
}

func (b *BaseDistribution) detectGit() deps.Dependency {
	return b.detectCommand("git", "Version control system")
}

func (b *BaseDistribution) detectMatugen() deps.Dependency {
	return b.detectCommand("matugen", "Material Design color generation tool")
}

func (b *BaseDistribution) detectDanksearch() deps.Dependency {
	return b.detectOptionalPackage("danksearch", "File indexing and search service", b.commandExists("dsearch") || b.commandExists("danksearch"))
}

func (b *BaseDistribution) detectDankCalendar() deps.Dependency {
	return b.detectOptionalPackage("dankcalendar", "Calendar application", b.commandExists("dcal") || b.commandExists("dankcalendar"))
}

// renamedPackages maps distro packages to their pre-rename names. rpm -q, dpkg-query and xbps-query
// ignore Provides, so hosts that have not upgraded since the rename only match the old name.
var renamedPackages = map[string]string{
	"dux-greeter":      "dms-greeter",
	"dux-greeter-git":  "dms-greeter-git",
	"dux-search":       "danksearch",
	"dux-calendar":     "dankcalendar",
	"dux-calendar-git": "dankcalendar-git",
	"dux-gop":          "dgop",
}

func installedName(installed func(string) bool, pkg string) (string, bool) {
	if installed(pkg) {
		return pkg, true
	}
	if old, ok := renamedPackages[pkg]; ok && installed(old) {
		return old, true
	}
	return "", false
}

func (b *BaseDistribution) detectGreeterPackage(installed func(string) bool) deps.Dependency {
	_, gitInstalled := installedName(installed, "dux-greeter-git")
	_, stableInstalled := installedName(installed, "dux-greeter")
	dep := b.detectOptionalPackage("dms-greeter", "Dux Shell greetd greeter", gitInstalled || stableInstalled)
	return withGitVariant(dep, gitInstalled)
}

func (b *BaseDistribution) detectCalendarPackage(installed func(string) bool) deps.Dependency {
	_, gitInstalled := installedName(installed, "dux-calendar-git")
	return withGitVariant(b.detectDankCalendar(), gitInstalled)
}

func withGitVariant(dep deps.Dependency, gitInstalled bool) deps.Dependency {
	dep.CanToggle = true
	if gitInstalled {
		dep.Variant = deps.VariantGit
	}
	return dep
}

// variantMapping is for packages whose git build is published as "<name>-git" in the same repo.
func variantMapping(name string, variant deps.PackageVariant, repo RepositoryType, repoURL string) PackageMapping {
	if variant == deps.VariantGit {
		name += "-git"
	}
	return PackageMapping{Name: name, Repository: repo, RepoURL: repoURL}
}

func (b *BaseDistribution) detectDMS() deps.Dependency {
	dmsPath := filepath.Join(os.Getenv("HOME"), ".config/quickshell/dms")

	status := deps.StatusMissing
	currentVersion := ""

	if _, err := os.Stat(dmsPath); err == nil {
		status = deps.StatusInstalled

		// Only get current version, don't check for updates (lazy loading)
		current, err := version.GetCurrentDMSVersion()
		if err == nil {
			currentVersion = current
		}
	}

	dep := deps.Dependency{
		Name:        "dms (Dux Shell)",
		Status:      status,
		Description: "Desktop Management System configuration",
		Required:    true,
		CanToggle:   true,
	}

	if currentVersion != "" {
		dep.Version = currentVersion
	}

	return dep
}

func (b *BaseDistribution) detectSpecificTerminal(terminal deps.Terminal) deps.Dependency {
	switch terminal {
	case deps.TerminalGhostty:
		status := deps.StatusMissing
		if b.commandExists("ghostty") {
			status = deps.StatusInstalled
		}
		return deps.Dependency{
			Name:        "ghostty",
			Status:      status,
			Description: "A fast, native terminal emulator built in Zig.",
			Required:    true,
		}
	case deps.TerminalKitty:
		status := deps.StatusMissing
		if b.commandExists("kitty") {
			status = deps.StatusInstalled
		}
		return deps.Dependency{
			Name:        "kitty",
			Status:      status,
			Description: "A feature-rich, customizable terminal emulator.",
			Required:    true,
		}
	case deps.TerminalAlacritty:
		status := deps.StatusMissing
		if b.commandExists("alacritty") {
			status = deps.StatusInstalled
		}
		return deps.Dependency{
			Name:        "alacritty",
			Status:      status,
			Description: "A simple terminal emulator. (No dynamic theming)",
			Required:    true,
		}
	default:
		return b.detectSpecificTerminal(deps.TerminalGhostty)
	}
}

func (b *BaseDistribution) detectHyprlandTools() []deps.Dependency {
	var dependencies []deps.Dependency

	tools := []struct {
		name        string
		description string
	}{
		{"hyprctl", "Hyprland control utility"},
		{"jq", "JSON processor"},
	}

	for _, tool := range tools {
		status := deps.StatusMissing
		if b.commandExists(tool.name) {
			status = deps.StatusInstalled
		}

		dependencies = append(dependencies, deps.Dependency{
			Name:        tool.name,
			Status:      status,
			Description: tool.description,
			Required:    true,
		})
	}

	return dependencies
}

// Hyprland 0.52+ calls hyprland-dialog and friends from hyprland-guiutils and complains when they are missing.
func (b *BaseDistribution) detectHyprlandGuiutils() deps.Dependency {
	return b.detectPackage("hyprland-guiutils", "Hyprland dialogs and helper apps", b.commandExists("hyprland-dialog"))
}

func (b *BaseDistribution) detectQuickshell() deps.Dependency {
	if !b.commandExists("qs") {
		return deps.Dependency{
			Name:        "quickshell",
			Status:      deps.StatusMissing,
			Description: "QtQuick based desktop shell toolkit",
			Required:    true,
			Variant:     deps.VariantStable,
			CanToggle:   true,
		}
	}

	cmd := exec.Command("qs", "--version")
	output, err := cmd.Output()
	if err != nil {
		return deps.Dependency{
			Name:        "quickshell",
			Status:      deps.StatusNeedsReinstall,
			Description: "QtQuick based desktop shell toolkit (version check failed)",
			Required:    true,
			Variant:     deps.VariantStable,
			CanToggle:   true,
		}
	}

	versionStr := string(output)
	versionRegex := regexp.MustCompile(`(?i)quickshell (\d+\.\d+\.\d+)`)
	matches := versionRegex.FindStringSubmatch(versionStr)

	if len(matches) < 2 {
		return deps.Dependency{
			Name:        "quickshell",
			Status:      deps.StatusNeedsReinstall,
			Description: "QtQuick based desktop shell toolkit (unknown version)",
			Required:    true,
			Variant:     deps.VariantStable,
			CanToggle:   true,
		}
	}

	installedVersion := matches[1]
	variant := deps.VariantStable
	if strings.Contains(versionStr, "git") || strings.Contains(versionStr, "+") {
		variant = deps.VariantGit
	}

	if version.CompareVersions(installedVersion, "0.2.0") >= 0 {
		return deps.Dependency{
			Name:        "quickshell",
			Status:      deps.StatusInstalled,
			Version:     installedVersion,
			Description: "QtQuick based desktop shell toolkit",
			Required:    true,
			Variant:     variant,
			CanToggle:   true,
		}
	}

	return deps.Dependency{
		Name:        "quickshell",
		Status:      deps.StatusNeedsUpdate,
		Variant:     variant,
		CanToggle:   true,
		Version:     installedVersion,
		Description: "QtQuick based desktop shell toolkit (needs 0.2.0+)",
		Required:    true,
	}
}

var (
	hyprlandTagRegex     = regexp.MustCompile(`Tag: v?(\d+\.\d+\.\d+)`)
	hyprlandVersionRegex = regexp.MustCompile(`v?(\d+\.\d+\.\d+)`)
)

// ParseHyprlandVersion prefers the Tag: line because main-branch builds print a stale version first.
func ParseHyprlandVersion(out string) string {
	if m := hyprlandTagRegex.FindStringSubmatch(out); m != nil {
		return m[1]
	}
	if m := hyprlandVersionRegex.FindStringSubmatch(out); m != nil {
		return m[1]
	}
	return ""
}

func (b *BaseDistribution) detectWindowManager(wm deps.WindowManager) deps.Dependency {
	switch wm {
	case deps.WindowManagerHyprland:
		status := deps.StatusMissing
		variant := deps.VariantStable
		version := ""

		if b.commandExists("hyprland") || b.commandExists("Hyprland") {
			status = deps.StatusInstalled
			cmd := exec.Command("hyprctl", "version")
			if output, err := cmd.Output(); err == nil {
				outStr := string(output)
				if strings.Contains(outStr, "git") || strings.Contains(outStr, "dirty") {
					variant = deps.VariantGit
				}
				version = ParseHyprlandVersion(outStr)
			}
		}
		return deps.Dependency{
			Name:        "hyprland",
			Status:      status,
			Version:     version,
			Description: "Dynamic tiling Wayland compositor",
			Required:    true,
			Variant:     variant,
			CanToggle:   true,
		}
	case deps.WindowManagerNiri:
		status := deps.StatusMissing
		variant := deps.VariantStable
		version := ""

		if b.commandExists("niri") {
			status = deps.StatusInstalled
			cmd := exec.Command("niri", "--version")
			if output, err := cmd.Output(); err == nil {
				outStr := string(output)
				if strings.Contains(outStr, "git") || strings.Contains(outStr, "+") {
					variant = deps.VariantGit
				}
				if versionRegex := regexp.MustCompile(`niri (\d+\.\d+)`); versionRegex.MatchString(outStr) {
					matches := versionRegex.FindStringSubmatch(outStr)
					if len(matches) > 1 {
						version = matches[1]
					}
				}
			}
		}
		return deps.Dependency{
			Name:        "niri",
			Status:      status,
			Version:     version,
			Description: "Scrollable-tiling Wayland compositor",
			Required:    true,
			Variant:     variant,
			CanToggle:   true,
		}
	case deps.WindowManagerMango:
		status := deps.StatusMissing
		variant := deps.VariantStable
		version := ""

		if b.commandExists("mango") {
			status = deps.StatusInstalled
			cmd := exec.Command("mango", "-v")
			if output, err := cmd.Output(); err == nil {
				outStr := string(output)
				if strings.Contains(outStr, "git") || strings.Contains(outStr, "dirty") {
					variant = deps.VariantGit
				}
				if versionRegex := regexp.MustCompile(`(\d+\.\d+\.\d+)`); versionRegex.MatchString(outStr) {
					matches := versionRegex.FindStringSubmatch(outStr)
					if len(matches) > 1 {
						version = matches[1]
					}
				}
			}
		}
		return deps.Dependency{
			Name:        "mango",
			Status:      status,
			Version:     version,
			Description: "dwl-based dynamic tiling Wayland compositor",
			Required:    true,
			Variant:     variant,
			CanToggle:   true,
		}
	default:
		return deps.Dependency{
			Name:        "unknown-wm",
			Status:      deps.StatusMissing,
			Description: "Unknown window manager",
			Required:    true,
		}
	}
}

// Common installation helper
func (b *BaseDistribution) runWithProgress(cmd *exec.Cmd, progressChan chan<- InstallProgressMsg, phase InstallPhase, startProgress, endProgress float64) error {
	return b.runWithProgressTimeout(cmd, progressChan, phase, startProgress, endProgress, 20*time.Minute)
}

func (b *BaseDistribution) runWithProgressTimeout(cmd *exec.Cmd, progressChan chan<- InstallProgressMsg, phase InstallPhase, startProgress, endProgress float64, timeout time.Duration) error {
	return b.runWithProgressStepTimeout(cmd, progressChan, phase, startProgress, endProgress, "Installing...", timeout)
}

func (b *BaseDistribution) runWithProgressStep(cmd *exec.Cmd, progressChan chan<- InstallProgressMsg, phase InstallPhase, startProgress, endProgress float64, stepMessage string) error {
	return b.runWithProgressStepTimeout(cmd, progressChan, phase, startProgress, endProgress, stepMessage, 20*time.Minute)
}

func (b *BaseDistribution) runWithProgressStepTimeout(cmd *exec.Cmd, progressChan chan<- InstallProgressMsg, phase InstallPhase, startProgress, endProgress float64, stepMessage string, timeoutDuration time.Duration) error {
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to create stdout pipe: %w", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("failed to create stderr pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return err
	}

	outputChan := make(chan string, 100)
	done := make(chan error, 1)

	go func() {
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			line := scanner.Text()
			b.log(line)
			outputChan <- line
		}
	}()

	go func() {
		scanner := bufio.NewScanner(stderr)
		for scanner.Scan() {
			line := scanner.Text()
			b.log(line)
			outputChan <- line
		}
	}()

	go func() {
		done <- cmd.Wait()
		close(outputChan)
	}()

	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()

	progress := startProgress
	progressStep := (endProgress - startProgress) / 50
	lastOutput := ""

	var timeout *time.Timer
	var timeoutChan <-chan time.Time
	if timeoutDuration > 0 {
		timeout = time.NewTimer(timeoutDuration)
		defer timeout.Stop()
		timeoutChan = timeout.C
	}

	for {
		select {
		case err := <-done:
			if err != nil {
				b.logError("Command execution failed", err)
				b.log(fmt.Sprintf("Last output before failure: %s", lastOutput))
				progressChan <- InstallProgressMsg{
					Phase:      phase,
					Progress:   startProgress,
					Step:       "Command failed",
					IsComplete: false,
					LogOutput:  lastOutput,
					Error:      err,
				}
				return err
			}
			progressChan <- InstallProgressMsg{
				Phase:      phase,
				Progress:   endProgress,
				Step:       stepMessage,
				IsComplete: false,
				LogOutput:  lastOutput,
			}
			return nil
		case output, ok := <-outputChan:
			if ok {
				lastOutput = output
				progressChan <- InstallProgressMsg{
					Phase:      phase,
					Progress:   progress,
					Step:       stepMessage,
					IsComplete: false,
					LogOutput:  output,
				}
				if timeout != nil {
					timeout.Reset(timeoutDuration)
				}
			}
		case <-timeoutChan:
			if cmd.Process != nil {
				cmd.Process.Kill()
			}
			err := fmt.Errorf("installation timed out after %v", timeoutDuration)
			progressChan <- InstallProgressMsg{
				Phase:      phase,
				Progress:   startProgress,
				Step:       "Installation timed out",
				IsComplete: false,
				LogOutput:  lastOutput,
				Error:      err,
			}
			return err
		case <-ticker.C:
			if progress < endProgress-0.01 {
				progress += progressStep
				progressChan <- InstallProgressMsg{
					Phase:      phase,
					Progress:   progress,
					Step:       stepMessage,
					IsComplete: false,
					LogOutput:  lastOutput,
				}
			}
		}
	}
}

func (b *BaseDistribution) DetectTerminalFromDeps(dependencies []deps.Dependency) deps.Terminal {
	for _, dep := range dependencies {
		switch dep.Name {
		case "ghostty":
			return deps.TerminalGhostty
		case "kitty":
			return deps.TerminalKitty
		case "alacritty":
			return deps.TerminalAlacritty
		}
	}
	return deps.TerminalGhostty
}

func (b *BaseDistribution) WriteEnvironmentConfig(terminal deps.Terminal) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("failed to get home directory: %w", err)
	}

	envDir := filepath.Join(homeDir, ".config", "environment.d")
	if err := os.MkdirAll(envDir, 0o755); err != nil {
		return fmt.Errorf("failed to create environment.d directory: %w", err)
	}

	var terminalCmd string
	switch terminal {
	case deps.TerminalGhostty:
		terminalCmd = "ghostty"
	case deps.TerminalKitty:
		terminalCmd = "kitty"
	case deps.TerminalAlacritty:
		terminalCmd = "alacritty"
	default:
		terminalCmd = "ghostty"
	}

	content := fmt.Sprintf(`ELECTRON_OZONE_PLATFORM_HINT=auto
TERMINAL=%s
`, terminalCmd)

	envFile := filepath.Join(envDir, "90-dms.conf")
	if err := os.WriteFile(envFile, []byte(content), 0o644); err != nil {
		return fmt.Errorf("failed to write environment config: %w", err)
	}

	b.log(fmt.Sprintf("Wrote environment config to %s", envFile))
	return nil
}

func (b *BaseDistribution) EnableDMSService(_ context.Context, wm deps.WindowManager) error {
	unit, err := config.EnableSession(wm)
	if err != nil {
		b.log(fmt.Sprintf("Warning: %v", err))
		return nil
	}
	b.log("dms.service starts with " + unit)
	return nil
}

func (b *BaseDistribution) WriteWindowManagerConfig(wm deps.WindowManager) error {
	if wm == deps.WindowManagerHyprland {
		if err := b.WriteHyprlandSessionTarget(); err != nil {
			return fmt.Errorf("failed to write hyprland session target: %w", err)
		}
	}
	return nil
}

func (b *BaseDistribution) WriteHyprlandSessionTarget() error {
	targetPath, err := config.EnsureHyprlandSessionTarget()
	if err != nil {
		return fmt.Errorf("failed to write hyprland-session.target: %w", err)
	}

	b.log(fmt.Sprintf("Using hyprland-session.target at %s", targetPath))
	return nil
}

// installDMSBinary installs the DMS binary from GitHub releases
func (b *BaseDistribution) installDMSBinary(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	b.log("Installing/updating DMS binary...")

	// Detect architecture
	arch := runtime.GOARCH
	switch arch {
	case "amd64":
	case "arm64":
	default:
		return fmt.Errorf("unsupported architecture for DMS: %s", arch)
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhaseConfiguration,
		Progress:    0.80,
		Step:        "Downloading DMS binary...",
		IsComplete:  false,
		CommandInfo: fmt.Sprintf("Downloading dms-%s.gz", arch),
	}

	version, err := netfetch.LatestReleaseTag(ctx)
	if err != nil {
		return fmt.Errorf("failed to get latest DMS version: %w", err)
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("failed to get user home directory: %w", err)
	}
	tmpDir := filepath.Join(homeDir, ".cache", "duxinstall", "manual-builds")
	if err := os.MkdirAll(tmpDir, 0o755); err != nil {
		return fmt.Errorf("failed to create temp directory: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	// Download the gzipped binary
	downloadURL := fmt.Sprintf("https://github.com/duxlabs-dev/dux-shell/releases/download/%s/dms-cli-%s.gz", version, arch)
	gzPath := filepath.Join(tmpDir, "dms.gz")

	if err := netfetch.ToFile(ctx, downloadURL, netfetch.Options{Timeout: 5 * time.Minute}, gzPath); err != nil {
		return fmt.Errorf("failed to download DMS binary: %w", err)
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhaseConfiguration,
		Progress:    0.85,
		Step:        "Extracting DMS binary...",
		IsComplete:  false,
		CommandInfo: "gunzip dms.gz",
	}

	// Extract the binary
	extractCmd := exec.CommandContext(ctx, "gunzip", gzPath)
	if err := extractCmd.Run(); err != nil {
		return fmt.Errorf("failed to extract DMS binary: %w", err)
	}

	binaryPath := filepath.Join(tmpDir, "dms")

	// Make it executable
	chmodCmd := exec.CommandContext(ctx, "chmod", "+x", binaryPath)
	if err := chmodCmd.Run(); err != nil {
		return fmt.Errorf("failed to make DMS binary executable: %w", err)
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhaseConfiguration,
		Progress:    0.88,
		Step:        "Installing DMS to /usr/local/bin...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: "sudo cp dms /usr/local/bin/",
	}

	// Install to /usr/local/bin
	installCmd := privesc.ExecCommand(ctx, sudoPassword,
		fmt.Sprintf("cp %s /usr/local/bin/dms", binaryPath))
	if err := installCmd.Run(); err != nil {
		return fmt.Errorf("failed to install DMS binary: %w", err)
	}

	b.log("DMS binary installed successfully")
	return nil
}
