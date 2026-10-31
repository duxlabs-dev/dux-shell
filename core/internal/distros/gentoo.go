package distros

import (
	"context"
	"fmt"
	"os/exec"
	"runtime"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

var GentooGlobalUseFlags = []string{
	"dbus",
	"udev",
	"alsa",
	"policykit",
	"jpeg",
	"png",
	"webp",
	"gif",
	"tiff",
	"svg",
	"brotli",
	"gdbm",
	"accessibility",
	"gtk",
	"qt6",
	"egl",
	"gbm",
}

func init() {
	Register("gentoo", "#54487A", FamilyGentoo, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewGentooDistribution(config, logChan)
	})
}

type GentooDistribution struct {
	*BaseDistribution
	*ManualPackageInstaller
	config             DistroConfig
	skipGlobalUseFlags bool
}

func NewGentooDistribution(config DistroConfig, logChan chan<- string) *GentooDistribution {
	base := NewBaseDistribution(logChan)
	return &GentooDistribution{
		BaseDistribution:       base,
		ManualPackageInstaller: &ManualPackageInstaller{BaseDistribution: base},
		config:                 config,
	}
}

func emergeInstallArgs(packages []string) []string {
	args := []string{"emerge", "--ask=n", "--quiet", "--autounmask-continue=y", "--autounmask-keep-keywords=y", "--autounmask-keep-masks=y"}
	return append(args, packages...)
}

func (g *GentooDistribution) getArchKeyword() string {
	arch := runtime.GOARCH
	switch arch {
	case "amd64":
		return "~amd64"
	case "arm64":
		return "~arm64"
	default:
		return "~amd64"
	}
}

func (g *GentooDistribution) GetID() string {
	return g.config.ID
}

func (g *GentooDistribution) GetColorHex() string {
	return g.config.ColorHex
}

func (g *GentooDistribution) GetFamily() DistroFamily {
	return g.config.Family
}

func (g *GentooDistribution) GetPackageManager() PackageManagerType {
	return PackageManagerPortage
}

func (g *GentooDistribution) DetectDependencies(ctx context.Context, wm deps.WindowManager) ([]deps.Dependency, error) {
	return g.DetectDependenciesWithTerminal(ctx, wm, deps.TerminalGhostty)
}

func (g *GentooDistribution) DetectDependenciesWithTerminal(ctx context.Context, wm deps.WindowManager, terminal deps.Terminal) ([]deps.Dependency, error) {
	var dependencies []deps.Dependency

	dependencies = append(dependencies, g.detectDMS())

	dependencies = append(dependencies, g.detectSpecificTerminal(terminal))

	dependencies = append(dependencies, g.detectGit())
	dependencies = append(dependencies, g.detectWindowManager(wm))
	dependencies = append(dependencies, g.detectQuickshell())
	dependencies = append(dependencies, g.detectXDGPortal())
	dependencies = append(dependencies, g.detectAccountsService())

	if wm == deps.WindowManagerHyprland {
		dependencies = append(dependencies, g.detectHyprlandTools()...)
	}

	if wm == deps.WindowManagerNiri {
		dependencies = append(dependencies, g.detectXwaylandSatellite())
	}

	// Mango-specific tools (dwl-based, uses xwayland-satellite like niri)
	if wm == deps.WindowManagerMango {
		dependencies = append(dependencies, g.detectXwaylandSatellite())
	}

	dependencies = append(dependencies, g.detectMatugen())
	dependencies = append(dependencies, g.detectDanksearch())

	return dependencies, nil
}

func (g *GentooDistribution) detectXDGPortal() deps.Dependency {
	return g.detectPackage("xdg-desktop-portal-gtk", "Desktop integration portal for GTK", g.packageInstalled("sys-apps/xdg-desktop-portal-gtk"))
}

func (g *GentooDistribution) detectDMS() deps.Dependency {
	dep := deps.Dependency{
		Name:        "dms (Dux Shell)",
		Status:      deps.StatusMissing,
		Description: "Desktop Management System configuration",
		Required:    true,
		CanToggle:   false,
	}
	if g.packageInstalled("dux-desktop/dux-shell") {
		dep.Status = deps.StatusInstalled
	}
	return dep
}

func (g *GentooDistribution) detectXwaylandSatellite() deps.Dependency {
	return g.detectPackage("xwayland-satellite", "Xwayland support", g.packageInstalled("gui-apps/xwayland-satellite"))
}

func (g *GentooDistribution) detectAccountsService() deps.Dependency {
	return g.detectPackage("accountsservice", "D-Bus interface for user account query and manipulation", g.packageInstalled("sys-apps/accountsservice"))
}

func (g *GentooDistribution) packageInstalled(pkg string) bool {
	cmd := exec.Command("qlist", "-I", pkg)
	err := cmd.Run()
	return err == nil
}

func (g *GentooDistribution) GetPackageMapping(wm deps.WindowManager) map[string]PackageMapping {
	return g.GetPackageMappingWithVariants(wm, make(map[string]deps.PackageVariant))
}

func (g *GentooDistribution) GetPackageMappingWithVariants(wm deps.WindowManager, variants map[string]deps.PackageVariant) map[string]PackageMapping {
	archKeyword := g.getArchKeyword()
	packages := map[string]PackageMapping{
		"git":                    {Name: "dev-vcs/git", Repository: RepoTypeSystem},
		"kitty":                  {Name: "x11-terms/kitty", Repository: RepoTypeSystem, UseFlags: "X wayland"},
		"alacritty":              {Name: "x11-terms/alacritty", Repository: RepoTypeSystem, UseFlags: "X wayland"},
		"xdg-desktop-portal-gtk": {Name: "sys-apps/xdg-desktop-portal-gtk", Repository: RepoTypeSystem, UseFlags: "wayland X"},
		"accountsservice":        {Name: "sys-apps/accountsservice", Repository: RepoTypeSystem},

		"qtbase":        {Name: "dev-qt/qtbase", Repository: RepoTypeSystem, UseFlags: "wayland opengl vulkan widgets"},
		"qtdeclarative": {Name: "dev-qt/qtdeclarative", Repository: RepoTypeSystem, UseFlags: "opengl vulkan"},
		"qtwayland":     {Name: "dev-qt/qtwayland", Repository: RepoTypeSystem},
		"mesa":          {Name: "media-libs/mesa", Repository: RepoTypeSystem, UseFlags: "opengl vulkan"},

		"quickshell":      g.getQuickshellMapping(variants["quickshell"]),
		"matugen":         {Name: "x11-misc/matugen", Repository: RepoTypeGURU, AcceptKeywords: archKeyword},
		"dms (Dux Shell)": g.getDmsMapping(),
		"danksearch":      {Name: "dux-desktop/dux-search", Repository: RepoTypeGURU, AcceptKeywords: archKeyword},
	}

	switch wm {
	case deps.WindowManagerHyprland:
		packages["hyprland"] = g.getHyprlandMapping(variants["hyprland"])
		packages["hyprctl"] = g.getHyprlandMapping(variants["hyprland"])
		packages["jq"] = PackageMapping{Name: "app-misc/jq", Repository: RepoTypeSystem}
	case deps.WindowManagerNiri:
		packages["niri"] = g.getNiriMapping(variants["niri"])
		packages["xwayland-satellite"] = PackageMapping{Name: "gui-apps/xwayland-satellite", Repository: RepoTypeGURU, AcceptKeywords: archKeyword}
	case deps.WindowManagerMango:
		packages["mango"] = g.getMangoMapping(variants["mango"])
		packages["scenefx"] = PackageMapping{Name: "gui-libs/scenefx", Repository: RepoTypeGURU, AcceptKeywords: archKeyword}
		packages["xwayland-satellite"] = PackageMapping{Name: "gui-apps/xwayland-satellite", Repository: RepoTypeGURU, AcceptKeywords: archKeyword}
	}

	return packages
}

func (g *GentooDistribution) getQuickshellMapping(_ deps.PackageVariant) PackageMapping {
	return PackageMapping{Name: "gui-apps/quickshell", Repository: RepoTypeGURU, UseFlags: "breakpad jemalloc sockets wayland layer-shell session-lock toplevel-management screencopy X pipewire tray mpris pam hyprland hyprland-global-shortcuts hyprland-focus-grab i3 i3-ipc bluetooth", AcceptKeywords: "**"}
}

func (g *GentooDistribution) getDmsMapping() PackageMapping {
	return PackageMapping{Name: "dux-desktop/dux-shell", Repository: RepoTypeGURU, AcceptKeywords: g.getArchKeyword()}
}

func (g *GentooDistribution) getHyprlandMapping(_ deps.PackageVariant) PackageMapping {
	return PackageMapping{Name: "gui-wm/hyprland", Repository: RepoTypeSystem, UseFlags: "X", AcceptKeywords: g.getArchKeyword()}
}

func (g *GentooDistribution) getNiriMapping(_ deps.PackageVariant) PackageMapping {
	return PackageMapping{Name: "gui-wm/niri", Repository: RepoTypeGURU, UseFlags: "dbus screencast", AcceptKeywords: g.getArchKeyword()}
}

func (g *GentooDistribution) getMangoMapping(_ deps.PackageVariant) PackageMapping {
	return PackageMapping{Name: "gui-wm/mangowm", Repository: RepoTypeGURU, AcceptKeywords: g.getArchKeyword()}
}

func (g *GentooDistribution) getPrerequisites() []string {
	return []string{
		"app-eselect/eselect-repository",
		"dev-vcs/git",
		"dev-build/make",
		"app-arch/unzip",
		"dev-util/pkgconf",
		"dev-qt/qtdeclarative",
	}
}

func (g *GentooDistribution) setGlobalUseFlags(ctx context.Context, sudoPassword string) error {
	useFlags := strings.Join(GentooGlobalUseFlags, " ")

	checkCmd := exec.CommandContext(ctx, "grep", "-q", "^USE=", "/etc/portage/make.conf")
	hasUse := checkCmd.Run() == nil

	var cmd *exec.Cmd
	if hasUse {
		cmd = privesc.ExecCommand(ctx, sudoPassword, fmt.Sprintf("sed -i 's/^USE=\"\\(.*\\)\"/USE=\"\\1 %s\"/' /etc/portage/make.conf", useFlags))
	} else {
		cmd = privesc.ExecCommand(ctx, sudoPassword, fmt.Sprintf("bash -c \"echo 'USE=\\\"%s\\\"' >> /etc/portage/make.conf\"", useFlags))
	}

	output, err := cmd.CombinedOutput()
	if err != nil {
		g.log(fmt.Sprintf("Failed to set global USE flags: %s", string(output)))
		return err
	}

	g.log(fmt.Sprintf("Set global USE flags: %s", useFlags))
	return nil
}

func (g *GentooDistribution) InstallPrerequisites(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	prerequisites := g.getPrerequisites()
	var missingPkgs []string

	if !g.skipGlobalUseFlags {
		progressChan <- InstallProgressMsg{
			Phase:      PhasePrerequisites,
			Progress:   0.05,
			Step:       "Setting global USE flags...",
			IsComplete: false,
			LogOutput:  "Configuring global USE flags in /etc/portage/make.conf",
		}

		if err := g.setGlobalUseFlags(ctx, sudoPassword); err != nil {
			g.logError("failed to set global USE flags", err)
			return fmt.Errorf("failed to set global USE flags: %w", err)
		}
	} else {
		progressChan <- InstallProgressMsg{
			Phase:      PhasePrerequisites,
			Progress:   0.05,
			Step:       "Skipping global USE flags...",
			IsComplete: false,
			LogOutput:  "Skipping global USE flags configuration (using existing configuration)",
		}
	}

	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.06,
		Step:       "Checking prerequisites...",
		IsComplete: false,
		LogOutput:  "Checking prerequisite packages",
	}

	for _, pkg := range prerequisites {
		checkCmd := exec.CommandContext(ctx, "qlist", "-I", pkg)
		if err := checkCmd.Run(); err != nil {
			missingPkgs = append(missingPkgs, pkg)
		}
	}

	_, err := exec.LookPath("go")
	if err != nil {
		g.log("go not found in PATH, will install dev-lang/go")
		missingPkgs = append(missingPkgs, "dev-lang/go")
	} else {
		g.log("go already available in PATH")
	}

	if len(missingPkgs) == 0 {
		g.log("All prerequisites already installed")
		return nil
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhasePrerequisites,
		Progress:    0.07,
		Step:        "Syncing Portage tree...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: "sudo emerge --sync",
		LogOutput:   "Syncing Portage tree with emerge --sync",
	}

	syncCmd := privesc.ExecCommand(ctx, sudoPassword, "emerge --sync --quiet")
	syncOutput, syncErr := syncCmd.CombinedOutput()
	if syncErr != nil {
		g.log(fmt.Sprintf("emerge --sync output: %s", string(syncOutput)))
		return fmt.Errorf("failed to sync Portage tree: %w\nOutput: %s", syncErr, string(syncOutput))
	}
	g.log("Portage tree synced successfully")

	args := emergeInstallArgs(missingPkgs)
	g.log(fmt.Sprintf("Installing prerequisites: %s", strings.Join(missingPkgs, ", ")))
	progressChan <- InstallProgressMsg{
		Phase:       PhasePrerequisites,
		Progress:    0.08,
		Step:        fmt.Sprintf("Installing %d prerequisites...", len(missingPkgs)),
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: fmt.Sprintf("sudo %s", strings.Join(args, " ")),
		LogOutput:   fmt.Sprintf("Installing prerequisites: %s", strings.Join(missingPkgs, ", ")),
	}

	cmd := privesc.ExecCommand(ctx, sudoPassword, strings.Join(args, " "))
	output, err := cmd.CombinedOutput()
	if err != nil {
		g.logError("failed to install prerequisites", err)
		g.log(fmt.Sprintf("Prerequisites command output: %s", string(output)))
		return fmt.Errorf("failed to install prerequisites: %w\nOutput: %s", err, string(output))
	}
	g.log(fmt.Sprintf("Prerequisites install output: %s", string(output)))

	return nil
}

func (g *GentooDistribution) InstallPackages(ctx context.Context, dependencies []deps.Dependency, wm deps.WindowManager, sudoPassword string, reinstallFlags map[string]bool, disabledFlags map[string]bool, skipGlobalUseFlags bool, progressChan chan<- InstallProgressMsg) error {
	g.skipGlobalUseFlags = skipGlobalUseFlags

	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.05,
		Step:       "Checking system prerequisites...",
		IsComplete: false,
		LogOutput:  "Starting prerequisite check...",
	}

	if err := g.InstallPrerequisites(ctx, sudoPassword, progressChan); err != nil {
		return fmt.Errorf("failed to install prerequisites: %w", err)
	}

	systemPkgs, guruPkgs, manualPkgs, variantMap := g.categorizePackages(dependencies, wm, reinstallFlags, disabledFlags)

	g.log(fmt.Sprintf("CATEGORIZED PACKAGES: system=%d, guru=%d, manual=%d", len(systemPkgs), len(guruPkgs), len(manualPkgs)))

	if len(systemPkgs) > 0 {
		systemPkgNames := g.extractPackageNames(systemPkgs)
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.35,
			Step:       fmt.Sprintf("Installing %d system packages...", len(systemPkgs)),
			IsComplete: false,
			NeedsSudo:  true,
			LogOutput:  fmt.Sprintf("Installing system packages: %s", strings.Join(systemPkgNames, ", ")),
		}
		if err := g.installPortagePackages(ctx, systemPkgs, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install Portage packages: %w", err)
		}
	}

	if len(guruPkgs) > 0 {
		g.log(fmt.Sprintf("FOUND %d GURU PACKAGES - WILL SYNC GURU REPO", len(guruPkgs)))
		progressChan <- InstallProgressMsg{
			Phase:      PhaseAURPackages,
			Progress:   0.60,
			Step:       "Syncing GURU repository...",
			IsComplete: false,
			LogOutput:  "Syncing GURU repository to fetch latest ebuilds",
		}
		g.log("ABOUT TO CALL syncGURURepo")
		if err := g.syncGURURepo(ctx, sudoPassword, progressChan); err != nil {
			g.log(fmt.Sprintf("syncGURURepo RETURNED ERROR: %v", err))
			return fmt.Errorf("failed to sync GURU repository: %w", err)
		}
		g.log("syncGURURepo COMPLETED SUCCESSFULLY")

		guruPkgNames := g.extractPackageNames(guruPkgs)
		progressChan <- InstallProgressMsg{
			Phase:      PhaseAURPackages,
			Progress:   0.65,
			Step:       fmt.Sprintf("Installing %d GURU packages...", len(guruPkgs)),
			IsComplete: false,
			LogOutput:  fmt.Sprintf("Installing GURU packages: %s", strings.Join(guruPkgNames, ", ")),
		}
		if err := g.installGURUPackages(ctx, guruPkgs, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install GURU packages: %w", err)
		}
	}

	if len(manualPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.85,
			Step:       fmt.Sprintf("Building %d packages from source...", len(manualPkgs)),
			IsComplete: false,
			LogOutput:  fmt.Sprintf("Building from source: %s", strings.Join(manualPkgs, ", ")),
		}
		if err := g.InstallManualPackages(ctx, manualPkgs, variantMap, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install manual packages: %w", err)
		}
	}

	progressChan <- InstallProgressMsg{
		Phase:      PhaseConfiguration,
		Progress:   0.90,
		Step:       "Configuring system...",
		IsComplete: false,
		LogOutput:  "Starting post-installation configuration...",
	}

	terminal := g.DetectTerminalFromDeps(dependencies)
	if err := g.WriteEnvironmentConfig(terminal); err != nil {
		g.log(fmt.Sprintf("Warning: failed to write environment config: %v", err))
	}

	if err := g.WriteWindowManagerConfig(wm); err != nil {
		g.log(fmt.Sprintf("Warning: failed to write window manager config: %v", err))
	}

	if err := g.EnableDMSService(ctx, wm); err != nil {
		g.log(fmt.Sprintf("Warning: failed to enable dms service: %v", err))
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

func (g *GentooDistribution) categorizePackages(dependencies []deps.Dependency, wm deps.WindowManager, reinstallFlags map[string]bool, disabledFlags map[string]bool) ([]PackageMapping, []PackageMapping, []string, map[string]deps.PackageVariant) {
	systemPkgs := []PackageMapping{}
	guruPkgs := []PackageMapping{}
	manualPkgs := []string{}

	variantMap := make(map[string]deps.PackageVariant)
	for _, dep := range dependencies {
		variantMap[dep.Name] = dep.Variant
	}

	packageMap := g.GetPackageMappingWithVariants(wm, variantMap)

	for _, dep := range dependencies {
		if disabledFlags[dep.Name] {
			continue
		}

		if dep.Status == deps.StatusInstalled && !reinstallFlags[dep.Name] {
			continue
		}

		pkgInfo, exists := packageMap[dep.Name]
		if !exists {
			g.log(fmt.Sprintf("Warning: No package mapping for %s", dep.Name))
			continue
		}

		switch pkgInfo.Repository {
		case RepoTypeSystem:
			systemPkgs = append(systemPkgs, pkgInfo)
		case RepoTypeGURU:
			guruPkgs = append(guruPkgs, pkgInfo)
		case RepoTypeManual:
			manualPkgs = append(manualPkgs, dep.Name)
		}
	}

	return systemPkgs, guruPkgs, manualPkgs, variantMap
}

func (g *GentooDistribution) extractPackageNames(packages []PackageMapping) []string {
	names := make([]string, len(packages))
	for i, pkg := range packages {
		names[i] = pkg.Name
	}
	return names
}

func (g *GentooDistribution) installPortagePackages(ctx context.Context, packages []PackageMapping, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if len(packages) == 0 {
		return nil
	}

	packageNames := g.extractPackageNames(packages)
	g.log(fmt.Sprintf("Installing Portage packages: %s", strings.Join(packageNames, ", ")))

	for _, pkg := range packages {
		if pkg.AcceptKeywords != "" {
			if err := g.setPackageAcceptKeywords(ctx, pkg.Name, pkg.AcceptKeywords, sudoPassword); err != nil {
				return fmt.Errorf("failed to set accept keywords for %s: %w", pkg.Name, err)
			}
		}
		if pkg.UseFlags != "" {
			if err := g.setPackageUseFlags(ctx, pkg.Name, pkg.UseFlags, sudoPassword); err != nil {
				return fmt.Errorf("failed to set USE flags for %s: %w", pkg.Name, err)
			}
		}
	}

	args := emergeInstallArgs(packageNames)

	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.40,
		Step:        "Installing system packages...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: fmt.Sprintf("sudo %s", strings.Join(args, " ")),
	}

	cmd := privesc.ExecCommand(ctx, sudoPassword, strings.Join(args, " "))
	return g.runWithProgressTimeout(cmd, progressChan, PhaseSystemPackages, 0.40, 0.60, 0)
}

func (g *GentooDistribution) setPackageUseFlags(ctx context.Context, packageName, useFlags, sudoPassword string) error {
	packageUseDir := "/etc/portage/package.use"

	mkdirCmd := privesc.ExecCommand(ctx, sudoPassword,
		fmt.Sprintf("mkdir -p %s", packageUseDir))
	if output, err := mkdirCmd.CombinedOutput(); err != nil {
		g.log(fmt.Sprintf("mkdir output: %s", string(output)))
		return fmt.Errorf("failed to create package.use directory: %w", err)
	}

	useFlagLine := fmt.Sprintf("%s %s", packageName, useFlags)

	checkExistingCmd := exec.CommandContext(ctx, "bash", "-c",
		fmt.Sprintf("grep -q '^%s ' %s/danklinux 2>/dev/null", packageName, packageUseDir))
	if checkExistingCmd.Run() == nil {
		g.log(fmt.Sprintf("Updating USE flags for %s from existing entry", packageName))
		escapedPkg := strings.ReplaceAll(packageName, "/", "\\/")
		replaceCmd := privesc.ExecCommand(ctx, sudoPassword,
			fmt.Sprintf("sed -i '/^%s /d' %s/danklinux; exit_code=$?; exit $exit_code", escapedPkg, packageUseDir))
		if output, err := replaceCmd.CombinedOutput(); err != nil {
			g.log(fmt.Sprintf("sed delete output: %s", string(output)))
			return fmt.Errorf("failed to remove old USE flags: %w", err)
		}
	}

	appendCmd := privesc.ExecCommand(ctx, sudoPassword,
		fmt.Sprintf("bash -c \"echo '%s' >> %s/danklinux\"", useFlagLine, packageUseDir))

	output, err := appendCmd.CombinedOutput()
	if err != nil {
		g.log(fmt.Sprintf("append output: %s", string(output)))
		return fmt.Errorf("failed to write USE flags to package.use: %w", err)
	}

	g.log(fmt.Sprintf("Set USE flags for %s: %s", packageName, useFlags))
	return nil
}

func (g *GentooDistribution) syncGURURepo(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.55,
		Step:        "Enabling GURU repository...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: "sudo eselect repository enable guru",
		LogOutput:   "Enabling GURU repository with eselect",
	}

	// Enable GURU repository
	enableCmd := privesc.ExecCommand(ctx, sudoPassword,
		"eselect repository enable guru 2>&1; exit_code=$?; exit $exit_code")
	output, err := enableCmd.CombinedOutput()

	g.log(fmt.Sprintf("eselect repository enable guru output:\n%s", string(output)))
	progressChan <- InstallProgressMsg{
		Phase:     PhaseSystemPackages,
		Progress:  0.55,
		LogOutput: "GURU repository enabled",
	}

	if err != nil {
		progressChan <- InstallProgressMsg{
			Phase:     PhaseSystemPackages,
			Progress:  0.55,
			LogOutput: fmt.Sprintf("ERROR enabling GURU: %v", err),
			Error:     err,
		}
		return fmt.Errorf("failed to enable GURU repository: %w\nOutput: %s", err, string(output))
	}

	// Sync GURU repository
	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.57,
		Step:        "Syncing GURU repository...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: "sudo emaint sync --repo guru",
		LogOutput:   "Syncing GURU repository",
	}

	syncCmd := privesc.ExecCommand(ctx, sudoPassword,
		"emaint sync --repo guru 2>&1; exit_code=$?; exit $exit_code")
	syncOutput, syncErr := syncCmd.CombinedOutput()

	g.log(fmt.Sprintf("emaint sync --repo guru output:\n%s", string(syncOutput)))
	progressChan <- InstallProgressMsg{
		Phase:     PhaseSystemPackages,
		Progress:  0.57,
		LogOutput: "GURU repository synced",
	}

	if syncErr != nil {
		progressChan <- InstallProgressMsg{
			Phase:     PhaseSystemPackages,
			Progress:  0.57,
			LogOutput: fmt.Sprintf("ERROR syncing GURU: %v", syncErr),
			Error:     syncErr,
		}
		return fmt.Errorf("failed to sync GURU repository: %w\nOutput: %s", syncErr, string(syncOutput))
	}

	return nil
}

func (g *GentooDistribution) setPackageAcceptKeywords(ctx context.Context, packageName, keywords, sudoPassword string) error {
	checkCmd := exec.CommandContext(ctx, "portageq", "match", "/", packageName)
	if output, err := checkCmd.CombinedOutput(); err == nil && len(output) > 0 {
		g.log(fmt.Sprintf("Package %s is already available (may already be unmasked)", packageName))
		return nil
	}

	acceptKeywordsDir := "/etc/portage/package.accept_keywords"

	mkdirCmd := privesc.ExecCommand(ctx, sudoPassword,
		fmt.Sprintf("mkdir -p %s", acceptKeywordsDir))
	if output, err := mkdirCmd.CombinedOutput(); err != nil {
		g.log(fmt.Sprintf("mkdir output: %s", string(output)))
		return fmt.Errorf("failed to create package.accept_keywords directory: %w", err)
	}

	keywordLine := fmt.Sprintf("%s %s", packageName, keywords)

	checkExistingCmd := exec.CommandContext(ctx, "bash", "-c",
		fmt.Sprintf("grep -q '^%s ' %s/danklinux 2>/dev/null", packageName, acceptKeywordsDir))
	if checkExistingCmd.Run() == nil {
		g.log(fmt.Sprintf("Updating accept keywords for %s from existing entry", packageName))
		escapedPkg := strings.ReplaceAll(packageName, "/", "\\/")
		replaceCmd := privesc.ExecCommand(ctx, sudoPassword,
			fmt.Sprintf("sed -i '/^%s /d' %s/danklinux; exit_code=$?; exit $exit_code", escapedPkg, acceptKeywordsDir))
		if output, err := replaceCmd.CombinedOutput(); err != nil {
			g.log(fmt.Sprintf("sed delete output: %s", string(output)))
			return fmt.Errorf("failed to remove old accept keywords: %w", err)
		}
	}

	appendCmd := privesc.ExecCommand(ctx, sudoPassword,
		fmt.Sprintf("bash -c \"echo '%s' >> %s/danklinux\"", keywordLine, acceptKeywordsDir))

	output, err := appendCmd.CombinedOutput()
	if err != nil {
		g.log(fmt.Sprintf("append output: %s", string(output)))
		return fmt.Errorf("failed to write accept keywords: %w", err)
	}

	g.log(fmt.Sprintf("Set accept keywords for %s: %s", packageName, keywords))
	return nil
}

func (g *GentooDistribution) installGURUPackages(ctx context.Context, packages []PackageMapping, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if len(packages) == 0 {
		return nil
	}

	packageNames := g.extractPackageNames(packages)
	g.log(fmt.Sprintf("Installing GURU packages: %s", strings.Join(packageNames, ", ")))

	for _, pkg := range packages {
		if pkg.AcceptKeywords != "" {
			if err := g.setPackageAcceptKeywords(ctx, pkg.Name, pkg.AcceptKeywords, sudoPassword); err != nil {
				return fmt.Errorf("failed to set accept keywords for %s: %w", pkg.Name, err)
			}
		}
		if pkg.UseFlags != "" {
			if err := g.setPackageUseFlags(ctx, pkg.Name, pkg.UseFlags, sudoPassword); err != nil {
				return fmt.Errorf("failed to set USE flags for %s: %w", pkg.Name, err)
			}
		}
	}

	guruPackages := make([]string, len(packageNames))
	for i, pkg := range packageNames {
		guruPackages[i] = pkg + "::guru"
	}

	args := emergeInstallArgs(guruPackages)

	progressChan <- InstallProgressMsg{
		Phase:       PhaseAURPackages,
		Progress:    0.70,
		Step:        "Installing GURU packages...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: fmt.Sprintf("sudo %s", strings.Join(args, " ")),
	}

	cmd := privesc.ExecCommand(ctx, sudoPassword, strings.Join(args, " "))
	return g.runWithProgressTimeout(cmd, progressChan, PhaseAURPackages, 0.70, 0.85, 0)
}
