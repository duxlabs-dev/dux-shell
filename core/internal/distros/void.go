package distros

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

const (
	VoidDMSRepo      = voidHost + "/" + projectDMS + "/current"
	VoidDepsRepo     = voidHost + "/" + projectDeps + "/current"
	VoidHyprlandRepo = "https://mirror.black-hole.dev/x86_64"

	voidDepsConf = "/etc/xbps.d/dux.conf"

	voidRunitSvDir      = "/etc/sv"
	voidRunitServiceDir = "/var/service"
)

func init() {
	Register("void", "#478061", FamilyVoid, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewVoidDistribution(config, logChan)
	})
}

type VoidDistribution struct {
	*BaseDistribution
	config DistroConfig
}

func NewVoidDistribution(config DistroConfig, logChan chan<- string) *VoidDistribution {
	return &VoidDistribution{
		BaseDistribution: NewBaseDistribution(logChan),
		config:           config,
	}
}

func (v *VoidDistribution) GetID() string {
	return v.config.ID
}

func (v *VoidDistribution) GetColorHex() string {
	return v.config.ColorHex
}

func (v *VoidDistribution) GetFamily() DistroFamily {
	return v.config.Family
}

func (v *VoidDistribution) GetPackageManager() PackageManagerType {
	return PackageManagerXBPS
}

func (v *VoidDistribution) DetectDependencies(ctx context.Context, wm deps.WindowManager) ([]deps.Dependency, error) {
	return v.DetectDependenciesWithTerminal(ctx, wm, deps.TerminalGhostty)
}

func (v *VoidDistribution) DetectDependenciesWithTerminal(ctx context.Context, wm deps.WindowManager, terminal deps.Terminal) ([]deps.Dependency, error) {
	var dependencies []deps.Dependency

	dependencies = append(dependencies, v.detectDMS())
	dependencies = append(dependencies, v.detectSpecificTerminal(terminal))
	dependencies = append(dependencies, v.detectGit())
	dependencies = append(dependencies, v.detectWindowManager(wm))
	dependencies = append(dependencies, v.detectQuickshell())
	dependencies = append(dependencies, v.detectGreeterPackage(v.packageInstalled))
	dependencies = append(dependencies, v.detectXDGPortal())
	dependencies = append(dependencies, v.detectAccountsService())
	dependencies = append(dependencies, v.detectDBus())
	dependencies = append(dependencies, v.detectElogind())
	dependencies = append(dependencies, v.detectMesaDri())

	if wm == deps.WindowManagerHyprland {
		dependencies = append(dependencies, v.detectHyprlandTools()...)
		dependencies = append(dependencies, v.detectHyprlandGuiutils())
	}

	if wm == deps.WindowManagerNiri || wm == deps.WindowManagerMango {
		dependencies = append(dependencies, v.detectXwaylandSatellite())
	}

	dependencies = append(dependencies, v.detectMatugen())
	dependencies = append(dependencies, v.detectDanksearch())
	dependencies = append(dependencies, v.detectDankCalendar())

	return dependencies, nil
}

func (v *VoidDistribution) detectDMS() deps.Dependency {
	status := deps.StatusMissing
	version := ""
	variant := deps.VariantStable

	if v.packageInstalled("dms-git") {
		status = deps.StatusInstalled
		version = v.packageVersion("dms-git")
		variant = deps.VariantGit
	} else if v.packageInstalled("dms") {
		status = deps.StatusInstalled
		version = v.packageVersion("dms")
	} else if v.commandExists("dms") {
		status = deps.StatusInstalled
	}

	return deps.Dependency{
		Name:        "dms (Dux Shell)",
		Status:      status,
		Version:     version,
		Description: "Desktop Management System package",
		Required:    true,
		Variant:     variant,
		CanToggle:   true,
	}
}

func (v *VoidDistribution) detectQuickshell() deps.Dependency {
	dep := v.BaseDistribution.detectQuickshell()
	dep.CanToggle = false
	return dep
}

func (v *VoidDistribution) detectXDGPortal() deps.Dependency {
	return v.detectPackage("xdg-desktop-portal-gtk", "Desktop integration portal for GTK", v.packageInstalled("xdg-desktop-portal-gtk"))
}

func (v *VoidDistribution) detectAccountsService() deps.Dependency {
	return v.detectPackage("accountsservice", "D-Bus interface for user account query and manipulation", v.packageInstalled("accountsservice"))
}

func (v *VoidDistribution) detectDBus() deps.Dependency {
	return v.detectPackage("dbus", "D-Bus system and session message bus", v.packageInstalled("dbus"))
}

func (v *VoidDistribution) detectElogind() deps.Dependency {
	return v.detectPackage("elogind", "loginctl/logind provider for power management and session tracking", v.packageInstalled("elogind") || v.commandExists("loginctl"))
}

func (v *VoidDistribution) detectMesaDri() deps.Dependency {
	return v.detectPackage("mesa-dri", "Mesa DRI/EGL drivers (GPU rendering; compositors find no outputs without it)", v.packageInstalled("mesa-dri"))
}

func (v *VoidDistribution) detectXwaylandSatellite() deps.Dependency {
	return v.detectPackage("xwayland-satellite", "Xwayland support", v.packageInstalled("xwayland-satellite"))
}

func (v *VoidDistribution) packageInstalled(pkg string) bool {
	return exec.Command("xbps-query", pkg).Run() == nil
}

func (v *VoidDistribution) InstalledVariant(stable, git PackageMapping) (deps.PackageVariant, bool) {
	return installedVariantByName(v.packageInstalled, stable, git)
}

// SwapVariants removes before installing because xbps has no replace-in-place; a failed install
// puts the old packages back from the local cache so the greeter is never left missing.
func (v *VoidDistribution) SwapVariants(ctx context.Context, swaps []VariantSwap, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if err := v.enableXBPSRepos(ctx, swapTargets(swaps, RepoTypeXBPS), sudoPassword, progressChan); err != nil {
		return err
	}

	from, to := swapNames(swaps)
	remove := "xbps-remove -Fy " + strings.Join(from, " ")
	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.40,
		Step:        "Removing current package variants...",
		NeedsSudo:   true,
		CommandInfo: "sudo " + remove,
	}
	if err := v.runWithProgress(privesc.ExecCommand(ctx, sudoPassword, remove), progressChan, PhaseSystemPackages, 0.40, 0.50); err != nil {
		return fmt.Errorf("failed to remove %s: %w", strings.Join(from, ", "), err)
	}

	installErr := v.installXBPSPackages(ctx, to, sudoPassword, progressChan)
	if installErr == nil {
		return nil
	}
	restore := privesc.ExecCommand(ctx, sudoPassword, "xbps-install -y "+strings.Join(from, " "))
	if err := v.runWithProgress(restore, progressChan, PhaseSystemPackages, 0.85, 0.90); err != nil {
		return fmt.Errorf("failed to install %s (%w) and to restore %s: %v", strings.Join(to, ", "), installErr, strings.Join(from, ", "), err)
	}
	return fmt.Errorf("failed to install %s, restored %s: %w", strings.Join(to, ", "), strings.Join(from, ", "), installErr)
}

func (v *VoidDistribution) RepoMoves() []RepoMove {
	var moves []RepoMove
	legacy, hasDeps := false, false
	for _, path := range repoGlob(voidConfGlob) {
		for _, url := range xbpsRepositoryLines(path) {
			move, ok := voidRepoMove(path, url)
			if !ok {
				continue
			}
			legacy = legacy || move.OldPresent
			hasDeps = hasDeps || strings.HasPrefix(move.New, voidHost+"/"+projectDeps+"/")
			moves = append(moves, move)
		}
	}
	// Greeter-only hosts got dms-greeter from dms/current, which no longer carries it.
	if legacy && !hasDeps {
		moves = append(moves, RepoMove{Kind: RepoTypeXBPS, New: VoidDepsRepo, NewPath: voidDepsConf})
	}
	return moves
}

// Matches on the repository line because older installs named the conf files differently.
func xbpsRepositoryLines(path string) []string {
	content, err := repoReadFile(path)
	if err != nil {
		return nil
	}
	var urls []string
	for line := range strings.Lines(string(content)) {
		key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok || strings.TrimSpace(key) != "repository" {
			continue
		}
		urls = append(urls, strings.TrimSpace(value))
	}
	return urls
}

func voidRepoMove(path, url string) (RepoMove, bool) {
	if strings.HasPrefix(url, voidHost+"/") {
		return RepoMove{Kind: RepoTypeXBPS, New: url, NewPath: path, NewPresent: true}, true
	}
	rest, ok := strings.CutPrefix(url, legacyVoidHost+"/")
	if !ok {
		return RepoMove{}, false
	}
	if deps, ok := strings.CutPrefix(rest, legacyProjectDeps+"/"); ok {
		rest = projectDeps + "/" + deps
	}
	return RepoMove{Kind: RepoTypeXBPS, Old: url, New: voidHost + "/" + rest, OldPath: path, NewPath: path, OldPresent: true}, true
}

func voidAddsRepo(move RepoMove) bool {
	return !move.OldPresent && !move.NewPresent && move.NewPath != ""
}

func voidMoveCommands(moves []RepoMove) []string {
	var commands []string
	for _, move := range moves {
		switch {
		case move.OldPresent:
			commands = append(commands, fmt.Sprintf("sed -i 's|repository=%s|repository=%s|' %s", move.Old, move.New, move.OldPath))
		case voidAddsRepo(move):
			// Appends so an unrelated file that happens to share the name is not clobbered.
			commands = append(commands, fmt.Sprintf("sh -c 'echo repository=%s >> %s'", move.New, move.NewPath))
		}
	}
	if len(commands) > 0 {
		commands = append(commands, "xbps-install -S")
	}
	return commands
}

func (v *VoidDistribution) ApplyRepoMoves(ctx context.Context, moves []RepoMove, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	for _, command := range voidMoveCommands(moves) {
		progressChan <- InstallProgressMsg{
			Phase:       PhaseSystemPackages,
			Progress:    0.30,
			Step:        "Moving XBPS repositories...",
			NeedsSudo:   true,
			CommandInfo: "sudo " + command,
		}
		if err := v.runWithProgress(privescExec(ctx, sudoPassword, command), progressChan, PhaseSystemPackages, 0.30, 0.40); err != nil {
			return fmt.Errorf("failed to run %s: %w", command, err)
		}
	}
	return nil
}

func (v *VoidDistribution) RepoMoveCommands(moves []RepoMove) []string {
	var commands []string
	for _, command := range voidMoveCommands(moves) {
		commands = append(commands, "sudo "+command)
	}
	return commands
}

func (v *VoidDistribution) packageVersion(pkg string) string {
	output, err := exec.Command("xbps-query", "-p", "pkgver", pkg).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func (v *VoidDistribution) GetPackageMapping(wm deps.WindowManager) map[string]PackageMapping {
	return v.GetPackageMappingWithVariants(wm, make(map[string]deps.PackageVariant))
}

func (v *VoidDistribution) GetPackageMappingWithVariants(wm deps.WindowManager, variants map[string]deps.PackageVariant) map[string]PackageMapping {
	packages := map[string]PackageMapping{
		"git":                    {Name: "git", Repository: RepoTypeSystem},
		"ghostty":                {Name: "ghostty", Repository: RepoTypeSystem},
		"kitty":                  {Name: "kitty", Repository: RepoTypeSystem},
		"alacritty":              {Name: "alacritty", Repository: RepoTypeSystem},
		"xdg-desktop-portal-gtk": {Name: "xdg-desktop-portal-gtk", Repository: RepoTypeSystem},
		"accountsservice":        {Name: "accountsservice", Repository: RepoTypeSystem},
		"dbus":                   {Name: "dbus", Repository: RepoTypeSystem},
		"elogind":                {Name: "elogind", Repository: RepoTypeSystem},
		"mesa-dri":               {Name: "mesa-dri", Repository: RepoTypeSystem},

		"quickshell":      {Name: "quickshell", Repository: RepoTypeSystem},
		"matugen":         {Name: "matugen", Repository: RepoTypeSystem},
		"dms (Dux Shell)": v.getDmsMapping(variants["dms (Dux Shell)"]),
		"dms-greeter":     variantMapping("dux-greeter", variants["dms-greeter"], RepoTypeXBPS, VoidDepsRepo),
		"danksearch":      {Name: "dux-search", Repository: RepoTypeXBPS, RepoURL: VoidDepsRepo},
		"dankcalendar":    {Name: "dux-calendar", Repository: RepoTypeXBPS, RepoURL: VoidDepsRepo},
	}

	switch wm {
	case deps.WindowManagerHyprland:
		packages["hyprland"] = PackageMapping{Name: "hyprland", Repository: RepoTypeXBPS, RepoURL: VoidHyprlandRepo}
		packages["hyprctl"] = PackageMapping{Name: "hyprland", Repository: RepoTypeXBPS, RepoURL: VoidHyprlandRepo}
		packages["jq"] = PackageMapping{Name: "jq", Repository: RepoTypeSystem}
		packages["hyprland-guiutils"] = PackageMapping{Name: "hyprland-guiutils", Repository: RepoTypeXBPS, RepoURL: VoidHyprlandRepo}
	case deps.WindowManagerNiri:
		packages["niri"] = PackageMapping{Name: "niri", Repository: RepoTypeSystem}
		packages["xwayland-satellite"] = PackageMapping{Name: "xwayland-satellite", Repository: RepoTypeSystem}
	case deps.WindowManagerMango:
		packages["mango"] = PackageMapping{Name: "mangowc", Repository: RepoTypeSystem}
		packages["xwayland-satellite"] = PackageMapping{Name: "xwayland-satellite", Repository: RepoTypeSystem}
	}

	return packages
}

func (v *VoidDistribution) getDmsMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantStable {
		return PackageMapping{Name: "dms", Repository: RepoTypeXBPS, RepoURL: VoidDMSRepo}
	}
	return PackageMapping{Name: "dms-git", Repository: RepoTypeXBPS, RepoURL: VoidDMSRepo}
}

func (v *VoidDistribution) InstallPrerequisites(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.06,
		Step:       "Checking XBPS...",
		IsComplete: false,
		LogOutput:  "Checking for xbps-install",
	}

	if _, err := exec.LookPath("xbps-install"); err != nil {
		return fmt.Errorf("xbps-install not found; Void Linux package tools are required: %w", err)
	}

	return nil
}

func (v *VoidDistribution) InstallPackages(ctx context.Context, dependencies []deps.Dependency, wm deps.WindowManager, sudoPassword string, reinstallFlags map[string]bool, disabledFlags map[string]bool, skipGlobalUseFlags bool, progressChan chan<- InstallProgressMsg) error {
	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.05,
		Step:       "Checking system prerequisites...",
		IsComplete: false,
		LogOutput:  "Starting prerequisite check...",
	}

	if wm == deps.WindowManagerHyprland {
		arch, err := v.xbpsArch(ctx)
		if err != nil {
			return fmt.Errorf("failed to detect XBPS architecture for Hyprland repository selection: %w", err)
		}
		if arch != "x86_64" {
			return fmt.Errorf("hyprland on Void Linux is installed from %s, which currently provides x86_64 packages only (detected %s)", VoidHyprlandRepo, arch)
		}
	}

	if err := v.InstallPrerequisites(ctx, sudoPassword, progressChan); err != nil {
		return fmt.Errorf("failed to install prerequisites: %w", err)
	}

	skipFlags, err := swapReinstalledVariants(ctx, v, dependencies, wm, reinstallFlags, disabledFlags, sudoPassword, progressChan)
	if err != nil {
		return err
	}

	systemPkgs, xbpsPkgs := v.categorizePackages(dependencies, wm, reinstallFlags, skipFlags)

	if len(xbpsPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.15,
			Step:       "Enabling DMS XBPS repositories...",
			IsComplete: false,
			NeedsSudo:  true,
			LogOutput:  "Setting up custom XBPS repositories for DMS packages",
		}
		if err := v.enableXBPSRepos(ctx, xbpsPkgs, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to enable XBPS repositories: %w", err)
		}
	}

	allPkgs := v.uniquePackageNames(systemPkgs, v.extractPackageNames(xbpsPkgs))
	if len(allPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.35,
			Step:       fmt.Sprintf("Installing %d XBPS packages...", len(allPkgs)),
			IsComplete: false,
			NeedsSudo:  true,
			LogOutput:  fmt.Sprintf("Installing XBPS packages: %s", strings.Join(allPkgs, ", ")),
		}
		if err := v.installXBPSPackages(ctx, allPkgs, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install XBPS packages: %w", err)
		}
	}

	progressChan <- InstallProgressMsg{
		Phase:      PhaseConfiguration,
		Progress:   0.90,
		Step:       "Configuring system...",
		IsComplete: false,
		LogOutput:  "Starting post-installation configuration...",
	}

	v.log("Void Linux detected; DMS environment and autostart will be configured in the compositor config instead of systemd")
	if err := v.ensureSessionServices(ctx, sudoPassword, progressChan); err != nil {
		return fmt.Errorf("failed to enable Void session services: %w", err)
	}

	progressChan <- InstallProgressMsg{
		Phase:      PhaseComplete,
		Progress:   1.0,
		Step:       "Installation complete!",
		IsComplete: true,
		LogOutput:  "All packages installed and configured successfully",
	}

	return nil
}

func (v *VoidDistribution) ensureSessionServices(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if !v.isRunitSystem() {
		v.log("Void runit service directory not detected; skipping dbus/elogind service enablement")
		return nil
	}

	// D-Bus activation alone starts elogind without its wrapper mounts; the runit service is required.
	for _, service := range []string{"dbus", "elogind"} {
		if !v.runitServiceInstalled(service) {
			v.log(fmt.Sprintf("Warning: %s runit service not found in %s; power/session actions may not work until %s is installed", service, voidRunitSvDir, service))
			continue
		}
		if v.runitServiceEnabled(service) {
			v.log(fmt.Sprintf("Void runit service %s already enabled", service))
			continue
		}

		progressChan <- InstallProgressMsg{
			Phase:       PhaseConfiguration,
			Progress:    0.92,
			Step:        fmt.Sprintf("Enabling %s runit service...", service),
			IsComplete:  false,
			NeedsSudo:   true,
			CommandInfo: fmt.Sprintf("sudo ln -sf %s %s", filepath.Join(voidRunitSvDir, service), filepath.Join(voidRunitServiceDir, service)),
			LogOutput:   fmt.Sprintf("Enabling Void runit service: %s", service),
		}

		cmd := privesc.ExecCommand(ctx, sudoPassword, fmt.Sprintf("ln -sf %s %s", filepath.Join(voidRunitSvDir, service), filepath.Join(voidRunitServiceDir, service)))
		if err := v.runWithProgress(cmd, progressChan, PhaseConfiguration, 0.92, 0.95); err != nil {
			return fmt.Errorf("failed to enable %s runit service: %w", service, err)
		}
		v.log(fmt.Sprintf("✓ Enabled %s runit service", service))
	}

	return nil
}

func (v *VoidDistribution) isRunitSystem() bool {
	if fi, err := os.Stat("/run/runit"); err == nil && fi.IsDir() {
		return true
	}
	if _, err := os.Stat("/run/systemd/system"); err == nil {
		return false
	}
	if fi, err := os.Stat(voidRunitServiceDir); err == nil && fi.IsDir() {
		return true
	}
	return false
}

func (v *VoidDistribution) runitServiceInstalled(name string) bool {
	fi, err := os.Stat(filepath.Join(voidRunitSvDir, name))
	return err == nil && fi.IsDir()
}

func (v *VoidDistribution) runitServiceEnabled(name string) bool {
	_, err := os.Lstat(filepath.Join(voidRunitServiceDir, name))
	return err == nil
}

func (v *VoidDistribution) categorizePackages(dependencies []deps.Dependency, wm deps.WindowManager, reinstallFlags map[string]bool, disabledFlags map[string]bool) ([]string, []PackageMapping) {
	systemPkgs := []string{}
	xbpsPkgs := []PackageMapping{}

	variantMap := make(map[string]deps.PackageVariant)
	for _, dep := range dependencies {
		variantMap[dep.Name] = dep.Variant
	}

	packageMap := v.GetPackageMappingWithVariants(wm, variantMap)

	for _, dep := range dependencies {
		if disabledFlags[dep.Name] {
			continue
		}

		if dep.Status == deps.StatusInstalled && !reinstallFlags[dep.Name] {
			continue
		}

		pkgInfo, exists := packageMap[dep.Name]
		if !exists {
			v.log(fmt.Sprintf("Warning: No package mapping for %s", dep.Name))
			continue
		}

		switch pkgInfo.Repository {
		case RepoTypeXBPS:
			xbpsPkgs = append(xbpsPkgs, pkgInfo)
		case RepoTypeSystem:
			systemPkgs = append(systemPkgs, pkgInfo.Name)
		}
	}

	return systemPkgs, xbpsPkgs
}

func (v *VoidDistribution) enableXBPSRepos(ctx context.Context, xbpsPkgs []PackageMapping, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	enabledRepos := make(map[string]bool)
	enabledRepoURLs := []string{}

	for _, pkg := range xbpsPkgs {
		if pkg.RepoURL == "" || enabledRepos[pkg.RepoURL] {
			continue
		}

		repoName := v.xbpsRepoName(pkg.RepoURL)
		confPath := filepath.Join("/etc/xbps.d", repoName+".conf")
		repoLine := fmt.Sprintf("repository=%s", pkg.RepoURL)
		repoFileContent := repoLine + "\n"

		if content, err := os.ReadFile(confPath); err == nil && string(content) == repoFileContent {
			v.log(fmt.Sprintf("XBPS repo %s already configured, skipping", pkg.RepoURL))
			enabledRepos[pkg.RepoURL] = true
			enabledRepoURLs = append(enabledRepoURLs, pkg.RepoURL)
			continue
		}

		progressChan <- InstallProgressMsg{
			Phase:       PhaseSystemPackages,
			Progress:    0.18,
			Step:        fmt.Sprintf("Adding XBPS repo %s...", repoName),
			IsComplete:  false,
			NeedsSudo:   true,
			CommandInfo: fmt.Sprintf("echo 'repository=%s' | sudo tee %s", pkg.RepoURL, confPath),
			LogOutput:   fmt.Sprintf("Adding XBPS repository: %s", pkg.RepoURL),
		}

		mkdirCmd := privesc.ExecCommand(ctx, sudoPassword, "mkdir -p /etc/xbps.d")
		if err := v.runWithProgress(mkdirCmd, progressChan, PhaseSystemPackages, 0.18, 0.19); err != nil {
			return fmt.Errorf("failed to create /etc/xbps.d: %w", err)
		}

		writeCmd := privesc.ExecCommand(ctx, sudoPassword,
			fmt.Sprintf("bash -c 'printf \"%%s\\n\" %q > %s'", repoLine, confPath))
		if err := v.runWithProgress(writeCmd, progressChan, PhaseSystemPackages, 0.19, 0.22); err != nil {
			return fmt.Errorf("failed to add XBPS repo %s: %w", pkg.RepoURL, err)
		}

		enabledRepos[pkg.RepoURL] = true
		enabledRepoURLs = append(enabledRepoURLs, pkg.RepoURL)
	}

	if len(enabledRepos) > 0 {
		syncArgs := []string{"xbps-install", "-Sy", "-i"}
		for _, repoURL := range enabledRepoURLs {
			syncArgs = append(syncArgs, "--repository", repoURL)
		}
		syncCommand := strings.Join(syncArgs, " ")

		progressChan <- InstallProgressMsg{
			Phase:       PhaseSystemPackages,
			Progress:    0.25,
			Step:        "Synchronizing XBPS repositories...",
			IsComplete:  false,
			NeedsSudo:   true,
			CommandInfo: "sudo sh -c 'yes y | " + syncCommand + "'",
			LogOutput:   "Synchronizing XBPS repository indexes",
		}

		syncCmd := privesc.ExecCommand(ctx, sudoPassword, "sh -c 'yes y | "+syncCommand+"'")
		if err := v.runWithProgress(syncCmd, progressChan, PhaseSystemPackages, 0.25, 0.30); err != nil {
			return fmt.Errorf("failed to synchronize XBPS repositories: %w", err)
		}
	}

	return nil
}

func (v *VoidDistribution) xbpsRepoName(repoURL string) string {
	switch repoURL {
	case VoidDMSRepo:
		return "dms"
	case VoidDepsRepo:
		return "dux"
	case VoidHyprlandRepo:
		return "hyprland"
	default:
		name := strings.TrimPrefix(repoURL, "https://")
		name = strings.TrimPrefix(name, "http://")
		name = strings.NewReplacer("/", "-", ".", "-").Replace(name)
		return name
	}
}

func (v *VoidDistribution) xbpsArch(ctx context.Context) (string, error) {
	output, err := exec.CommandContext(ctx, "xbps-uhelper", "arch").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(output)), nil
}

func (v *VoidDistribution) installXBPSPackages(ctx context.Context, packages []string, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if len(packages) == 0 {
		return nil
	}

	args := append([]string{"xbps-install", "-Sy"}, packages...)
	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.40,
		Step:        "Installing XBPS packages...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: fmt.Sprintf("sudo %s", strings.Join(args, " ")),
	}

	cmd := privesc.ExecCommand(ctx, sudoPassword, strings.Join(args, " "))
	return v.runWithProgress(cmd, progressChan, PhaseSystemPackages, 0.40, 0.85)
}

func (v *VoidDistribution) extractPackageNames(packages []PackageMapping) []string {
	names := make([]string, len(packages))
	for i, pkg := range packages {
		names[i] = pkg.Name
	}
	return names
}

func (v *VoidDistribution) uniquePackageNames(groups ...[]string) []string {
	seen := make(map[string]bool)
	var unique []string
	for _, group := range groups {
		for _, pkg := range group {
			if pkg == "" || seen[pkg] {
				continue
			}
			seen[pkg] = true
			unique = append(unique, pkg)
		}
	}
	return unique
}
