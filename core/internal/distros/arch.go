package distros

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

func init() {
	Register("arch", "#1793D1", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("archarm", "#1793D1", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("archcraft", "#1793D1", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("cachyos", "#08A283", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("catos", "#1793D1", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("endeavouros", "#7F3FBF", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("manjaro", "#35BF5C", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("obarun", "#2494be", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("garuda", "#cba6f7", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("artix", "#1793D1", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
	Register("XeroLinux", "#888fe2", FamilyArch, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewArchDistribution(config, logChan)
	})
}

type ArchDistribution struct {
	*BaseDistribution
	*ManualPackageInstaller
	config DistroConfig
}

func NewArchDistribution(config DistroConfig, logChan chan<- string) *ArchDistribution {
	base := NewBaseDistribution(logChan)
	return &ArchDistribution{
		BaseDistribution:       base,
		ManualPackageInstaller: &ManualPackageInstaller{BaseDistribution: base},
		config:                 config,
	}
}

func (a *ArchDistribution) GetID() string {
	return a.config.ID
}

func (a *ArchDistribution) GetColorHex() string {
	return a.config.ColorHex
}

func (a *ArchDistribution) GetFamily() DistroFamily {
	return a.config.Family
}

func (a *ArchDistribution) GetPackageManager() PackageManagerType {
	return PackageManagerPacman
}

func (a *ArchDistribution) DetectDependencies(ctx context.Context, wm deps.WindowManager) ([]deps.Dependency, error) {
	return a.DetectDependenciesWithTerminal(ctx, wm, deps.TerminalGhostty)
}

func (a *ArchDistribution) DetectDependenciesWithTerminal(ctx context.Context, wm deps.WindowManager, terminal deps.Terminal) ([]deps.Dependency, error) {
	var dependencies []deps.Dependency

	// DMS at the top (shell is prominent)
	dependencies = append(dependencies, a.detectDMS())

	// Terminal with choice support
	dependencies = append(dependencies, a.detectSpecificTerminal(terminal))

	// Common detections using base methods
	dependencies = append(dependencies, a.detectGit())
	dependencies = append(dependencies, a.detectWindowManager(wm))
	dependencies = append(dependencies, a.detectQuickshell())
	dependencies = append(dependencies, a.detectDMSGreeter())
	dependencies = append(dependencies, a.detectXDGPortal())
	dependencies = append(dependencies, a.detectAccountsService())

	// Hyprland-specific tools
	if wm == deps.WindowManagerHyprland {
		dependencies = append(dependencies, a.detectHyprlandTools()...)
		dependencies = append(dependencies, a.detectHyprlandGuiutils())
	}

	// Niri-specific tools
	if wm == deps.WindowManagerNiri {
		dependencies = append(dependencies, a.detectXwaylandSatellite())
	}

	// Mango-specific tools (dwl-based, uses xwayland-satellite like niri)
	if wm == deps.WindowManagerMango {
		dependencies = append(dependencies, a.detectXwaylandSatellite())
	}

	dependencies = append(dependencies, a.detectMatugen())
	dependencies = append(dependencies, a.detectDanksearch())
	dependencies = append(dependencies, a.detectDankCalendar())

	return dependencies, nil
}

func (a *ArchDistribution) detectDanksearch() deps.Dependency {
	dep := a.BaseDistribution.detectDanksearch()
	dep.CanToggle = true
	if a.packageInstalled("dux-search-git") {
		dep.Variant = deps.VariantGit
	}
	return dep
}

func (a *ArchDistribution) detectDMS() deps.Dependency {
	dep := a.BaseDistribution.detectDMS()
	if a.packageInstalled("dux-shell-git") {
		dep.Variant = deps.VariantGit
	}
	return dep
}

func (a *ArchDistribution) detectDankCalendar() deps.Dependency {
	return withGitVariant(a.BaseDistribution.detectDankCalendar(), a.packageInstalled("dux-calendar-git"))
}

func (a *ArchDistribution) detectXDGPortal() deps.Dependency {
	return a.detectPackage("xdg-desktop-portal-gtk", "Desktop integration portal for GTK", a.packageInstalled("xdg-desktop-portal-gtk"))
}

func (a *ArchDistribution) detectAccountsService() deps.Dependency {
	return a.detectPackage("accountsservice", "D-Bus interface for user account query and manipulation", a.packageInstalled("accountsservice"))
}

func (a *ArchDistribution) detectDMSGreeter() deps.Dependency {
	installed := a.packageInstalled("dux-greeter-git") || a.packageInstalled("dux-greeter-bin")
	dep := a.detectOptionalPackage("dms-greeter", "Dux Shell greetd greeter", installed)
	dep.CanToggle = true
	if a.packageInstalled("dux-greeter-git") {
		dep.Variant = deps.VariantGit
	}
	return dep
}

func (a *ArchDistribution) packageInstalled(pkg string) bool {
	return exec.Command("pacman", "-Q", pkg).Run() == nil
}

// parseSRCINFODeps reads a .SRCINFO file and returns runtime dep and makedep package
func parseSRCINFODeps(srcinfoPath string) (deps []string, makedeps []string, err error) {
	data, err := os.ReadFile(srcinfoPath)
	if err != nil {
		return nil, nil, err
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		line = strings.TrimSpace(line)
		var pkg string
		var target *[]string
		switch {
		case strings.HasPrefix(line, "makedepends = "):
			pkg = strings.TrimPrefix(line, "makedepends = ")
			target = &makedeps
		case strings.HasPrefix(line, "depends = "):
			pkg = strings.TrimPrefix(line, "depends = ")
			target = &deps
		default:
			continue
		}
		// Strip version constraint (>=, <=, >, <, =) and colon-descriptions
		if idx := strings.IndexAny(pkg, "><:="); idx >= 0 {
			pkg = pkg[:idx]
		}
		pkg = strings.TrimSpace(pkg)
		if pkg != "" {
			*target = append(*target, pkg)
		}
	}
	return deps, makedeps, nil
}

func (a *ArchDistribution) isInSystemRepo(pkg string) bool {
	return exec.Command("pacman", "-Si", pkg).Run() == nil
}

// isSonameProvides reports whether dep is a shared-library soname
func isSonameProvides(dep string) bool {
	return strings.HasSuffix(dep, ".so") || strings.Contains(dep, ".so.")
}

func (a *ArchDistribution) GetPackageMapping(wm deps.WindowManager) map[string]PackageMapping {
	return a.GetPackageMappingWithVariants(wm, make(map[string]deps.PackageVariant))
}

func (a *ArchDistribution) GetPackageMappingWithVariants(wm deps.WindowManager, variants map[string]deps.PackageVariant) map[string]PackageMapping {
	packages := map[string]PackageMapping{
		"dms (Dux Shell)":        a.getDMSMapping(variants["dms (Dux Shell)"]),
		"git":                    {Name: "git", Repository: RepoTypeSystem},
		"quickshell":             a.getQuickshellMapping(variants["quickshell"]),
		"dms-greeter":            a.getDMSGreeterMapping(variants["dms-greeter"]),
		"matugen":                a.getMatugenMapping(variants["matugen"]),
		"ghostty":                {Name: "ghostty", Repository: RepoTypeSystem},
		"kitty":                  {Name: "kitty", Repository: RepoTypeSystem},
		"alacritty":              {Name: "alacritty", Repository: RepoTypeSystem},
		"xdg-desktop-portal-gtk": {Name: "xdg-desktop-portal-gtk", Repository: RepoTypeSystem},
		"accountsservice":        {Name: "accountsservice", Repository: RepoTypeSystem},
		"danksearch":             a.getDanksearchMapping(variants["danksearch"]),
		"dankcalendar":           a.getDankCalendarMapping(variants["dankcalendar"]),
	}

	switch wm {
	case deps.WindowManagerHyprland:
		packages["hyprland"] = a.getHyprlandMapping(variants["hyprland"])
		packages["hyprctl"] = a.getHyprlandMapping(variants["hyprland"])
		packages["jq"] = PackageMapping{Name: "jq", Repository: RepoTypeSystem}
		packages["hyprland-guiutils"] = PackageMapping{Name: "hyprland-guiutils", Repository: RepoTypeSystem}
	case deps.WindowManagerNiri:
		packages["niri"] = a.getNiriMapping(variants["niri"])
		packages["xwayland-satellite"] = PackageMapping{Name: "xwayland-satellite", Repository: RepoTypeSystem}
	case deps.WindowManagerMango:
		packages["mango"] = a.getMangoMapping(variants["mango"])
		packages["xwayland-satellite"] = PackageMapping{Name: "xwayland-satellite", Repository: RepoTypeSystem}
	}

	return packages
}

func (a *ArchDistribution) getQuickshellMapping(variant deps.PackageVariant) PackageMapping {
	if forceQuickshellGit || variant == deps.VariantGit {
		return PackageMapping{Name: "quickshell-git", Repository: RepoTypeAUR}
	}
	return PackageMapping{Name: "quickshell", Repository: RepoTypeSystem}
}

func (a *ArchDistribution) getHyprlandMapping(_ deps.PackageVariant) PackageMapping {
	return PackageMapping{Name: "hyprland", Repository: RepoTypeSystem}
}

func (a *ArchDistribution) getNiriMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "niri-git", Repository: RepoTypeAUR}
	}
	return PackageMapping{Name: "niri", Repository: RepoTypeSystem}
}

func (a *ArchDistribution) getMangoMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "mangowm-git", Repository: RepoTypeAUR}
	}
	return PackageMapping{Name: "mangowm", Repository: RepoTypeSystem}
}

func (a *ArchDistribution) getMatugenMapping(variant deps.PackageVariant) PackageMapping {
	if runtime.GOARCH == "arm64" {
		return PackageMapping{Name: "matugen-git", Repository: RepoTypeAUR}
	}

	if variant == deps.VariantGit {
		return PackageMapping{Name: "matugen-git", Repository: RepoTypeAUR}
	}
	return PackageMapping{Name: "matugen", Repository: RepoTypeSystem}
}

func (a *ArchDistribution) getDanksearchMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "dux-search-git", Repository: RepoTypeAUR}
	}
	return PackageMapping{Name: "dux-search-bin", Repository: RepoTypeAUR}
}

func (a *ArchDistribution) getDankCalendarMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "dux-calendar-git", Repository: RepoTypeAUR}
	}
	return PackageMapping{Name: "dux-calendar-bin", Repository: RepoTypeAUR}
}

func (a *ArchDistribution) getDMSGreeterMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "dux-greeter-git", Repository: RepoTypeAUR}
	}
	return PackageMapping{Name: "dux-greeter-bin", Repository: RepoTypeAUR}
}

func (a *ArchDistribution) getDMSMapping(variant deps.PackageVariant) PackageMapping {
	if forceDMSGit || variant == deps.VariantGit {
		return PackageMapping{Name: "dux-shell-git", Repository: RepoTypeAUR}
	}
	return PackageMapping{Name: "dux-shell", Repository: RepoTypeSystem}
}

func (a *ArchDistribution) detectXwaylandSatellite() deps.Dependency {
	status := deps.StatusMissing
	if a.commandExists("xwayland-satellite") {
		status = deps.StatusInstalled
	}

	return deps.Dependency{
		Name:        "xwayland-satellite",
		Status:      status,
		Description: "Xwayland support",
		Required:    true,
	}
}

func (a *ArchDistribution) InstallPrerequisites(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.06,
		Step:       "Checking base-devel...",
		IsComplete: false,
		LogOutput:  "Checking if base-devel is installed",
	}

	checkCmd := exec.CommandContext(ctx, "pacman", "-Qq", "base-devel")
	if err := checkCmd.Run(); err == nil {
		a.log("base-devel already installed")
		progressChan <- InstallProgressMsg{
			Phase:      PhasePrerequisites,
			Progress:   0.10,
			Step:       "base-devel already installed",
			IsComplete: false,
			LogOutput:  "base-devel is already installed on the system",
		}
		return nil
	}

	a.log("Installing base-devel...")
	progressChan <- InstallProgressMsg{
		Phase:       PhasePrerequisites,
		Progress:    0.08,
		Step:        "Installing base-devel...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: "sudo pacman -S --needed --noconfirm base-devel",
		LogOutput:   "Installing base-devel development tools",
	}

	cmd := privesc.ExecCommand(ctx, sudoPassword, "pacman -S --needed --noconfirm base-devel")
	if err := a.runWithProgress(cmd, progressChan, PhasePrerequisites, 0.08, 0.10); err != nil {
		return fmt.Errorf("failed to install base-devel: %w", err)
	}

	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.12,
		Step:       "base-devel installation complete",
		IsComplete: false,
		LogOutput:  "base-devel successfully installed",
	}

	return nil
}

func (a *ArchDistribution) InstallPackages(ctx context.Context, dependencies []deps.Dependency, wm deps.WindowManager, sudoPassword string, reinstallFlags map[string]bool, disabledFlags map[string]bool, skipGlobalUseFlags bool, progressChan chan<- InstallProgressMsg) error {
	// Phase 1: Check Prerequisites
	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.05,
		Step:       "Checking system prerequisites...",
		IsComplete: false,
		LogOutput:  "Starting prerequisite check...",
	}

	if err := a.InstallPrerequisites(ctx, sudoPassword, progressChan); err != nil {
		return fmt.Errorf("failed to install prerequisites: %w", err)
	}

	skipFlags, err := swapReinstalledVariants(ctx, a, dependencies, wm, reinstallFlags, disabledFlags, sudoPassword, progressChan)
	if err != nil {
		return err
	}

	systemPkgs, aurPkgs, manualPkgs, variantMap := a.categorizePackages(dependencies, wm, reinstallFlags, skipFlags)

	if slices.Contains(aurPkgs, "quickshell-git") && slices.Contains(systemPkgs, "dux-shell") {
		if err := a.preinstallQuickshellGit(ctx, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to preinstall quickshell-git: %w", err)
		}
		aurPkgs = slices.DeleteFunc(aurPkgs, func(p string) bool { return p == "quickshell-git" })
	}

	if slices.Contains(systemPkgs, "quickshell") && a.packageInstalled("quickshell-git") {
		if err := a.removeQuickshellGit(ctx, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to remove quickshell-git: %w", err)
		}
	}

	// Phase 3: System Packages
	if len(systemPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.35,
			Step:       fmt.Sprintf("Installing %d system packages...", len(systemPkgs)),
			IsComplete: false,
			NeedsSudo:  true,
			LogOutput:  fmt.Sprintf("Installing system packages: %s", strings.Join(systemPkgs, ", ")),
		}
		if err := a.installSystemPackages(ctx, systemPkgs, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install system packages: %w", err)
		}
	}

	// Phase 4: AUR Packages
	if len(aurPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseAURPackages,
			Progress:   0.65,
			Step:       fmt.Sprintf("Installing %d AUR packages...", len(aurPkgs)),
			IsComplete: false,
			LogOutput:  fmt.Sprintf("Installing AUR packages: %s", strings.Join(aurPkgs, ", ")),
		}
		if err := a.installAURPackages(ctx, aurPkgs, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install AUR packages: %w", err)
		}
	}

	// Phase 5: Manual Builds
	if len(manualPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.85,
			Step:       fmt.Sprintf("Building %d packages from source...", len(manualPkgs)),
			IsComplete: false,
			LogOutput:  fmt.Sprintf("Building from source: %s", strings.Join(manualPkgs, ", ")),
		}
		if err := a.InstallManualPackages(ctx, manualPkgs, variantMap, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install manual packages: %w", err)
		}
	}

	// Phase 6: Configuration
	progressChan <- InstallProgressMsg{
		Phase:      PhaseConfiguration,
		Progress:   0.90,
		Step:       "Configuring system...",
		IsComplete: false,
		LogOutput:  "Starting post-installation configuration...",
	}

	terminal := a.DetectTerminalFromDeps(dependencies)
	if err := a.WriteEnvironmentConfig(terminal); err != nil {
		a.log(fmt.Sprintf("Warning: failed to write environment config: %v", err))
	}

	if err := a.WriteWindowManagerConfig(wm); err != nil {
		a.log(fmt.Sprintf("Warning: failed to write window manager config: %v", err))
	}

	if err := a.EnableDMSService(ctx, wm); err != nil {
		a.log(fmt.Sprintf("Warning: failed to enable dms service: %v", err))
	}

	// Phase 7: Complete
	progressChan <- InstallProgressMsg{
		Phase:      PhaseComplete,
		Progress:   1.0,
		Step:       "Installation complete!",
		IsComplete: true,
		LogOutput:  "All packages installed and configured successfully",
	}

	return nil
}

func (a *ArchDistribution) categorizePackages(dependencies []deps.Dependency, wm deps.WindowManager, reinstallFlags map[string]bool, disabledFlags map[string]bool) ([]string, []string, []string, map[string]deps.PackageVariant) {
	systemPkgs := []string{}
	aurPkgs := []string{}
	manualPkgs := []string{}

	variantMap := make(map[string]deps.PackageVariant)
	for _, dep := range dependencies {
		variantMap[dep.Name] = dep.Variant
	}

	packageMap := a.GetPackageMappingWithVariants(wm, variantMap)

	for _, dep := range dependencies {
		if disabledFlags[dep.Name] {
			continue
		}

		if dep.Status == deps.StatusInstalled && !reinstallFlags[dep.Name] {
			continue
		}

		pkgInfo, exists := packageMap[dep.Name]
		if !exists {
			manualPkgs = append(manualPkgs, dep.Name)
			continue
		}

		switch pkgInfo.Repository {
		case RepoTypeAUR:
			aurPkgs = append(aurPkgs, pkgInfo.Name)
		case RepoTypeSystem:
			systemPkgs = append(systemPkgs, pkgInfo.Name)
		case RepoTypeManual:
			manualPkgs = append(manualPkgs, dep.Name)
		}
	}

	return systemPkgs, aurPkgs, manualPkgs, variantMap
}

func (a *ArchDistribution) removeQuickshellGit(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.33,
		Step:        "Removing quickshell-git...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: "sudo pacman -Rdd --noconfirm quickshell-git",
		LogOutput:   "Removing quickshell-git so stable quickshell can be installed",
	}
	cmd := privesc.ExecCommand(ctx, sudoPassword, "pacman -Rdd --noconfirm quickshell-git")
	return a.runWithProgress(cmd, progressChan, PhaseSystemPackages, 0.33, 0.35)
}

func (a *ArchDistribution) preinstallQuickshellGit(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if a.packageInstalled("quickshell-git") {
		return nil
	}

	if a.packageInstalled("quickshell") {
		progressChan <- InstallProgressMsg{
			Phase:       PhaseAURPackages,
			Progress:    0.15,
			Step:        "Removing stable quickshell...",
			IsComplete:  false,
			NeedsSudo:   true,
			CommandInfo: "sudo pacman -Rdd --noconfirm quickshell",
			LogOutput:   "Removing stable quickshell so quickshell-git can be installed",
		}
		cmd := privesc.ExecCommand(ctx, sudoPassword, "pacman -Rdd --noconfirm quickshell")
		if err := a.runWithProgress(cmd, progressChan, PhaseAURPackages, 0.15, 0.18); err != nil {
			return fmt.Errorf("failed to remove stable quickshell: %w", err)
		}
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhaseAURPackages,
		Progress:    0.18,
		Step:        "Building quickshell-git before system packages...",
		IsComplete:  false,
		CommandInfo: "Installing quickshell-git ahead of dux-shell to avoid conflict",
	}
	return a.installSingleAURPackage(ctx, "quickshell-git", sudoPassword, progressChan, 0.18, 0.32)
}

func (a *ArchDistribution) InstalledVariant(stable, git PackageMapping) (deps.PackageVariant, bool) {
	return installedVariantByName(a.packageInstalled, stable, git)
}

// SwapVariants builds AUR targets before removing the old variant. Repo targets go through one
// pacman transaction: --noconfirm answers the conflict prompt "no" and -Sw still runs the conflict
// check, so --ask=4 pre-answers ALPM_QUESTION_CONFLICT_PKG instead.
func (a *ArchDistribution) SwapVariants(ctx context.Context, swaps []VariantSwap, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	for _, swap := range swaps {
		progressChan <- InstallProgressMsg{
			Phase:    PhaseAURPackages,
			Progress: 0.40,
			Step:     fmt.Sprintf("Switching %s to %s...", swap.From.Name, swap.To.Name),
		}

		if swap.To.Repository == RepoTypeAUR {
			from := swap.From.Name
			if err := a.installSingleAURPackageInternal(ctx, swap.To.Name, from, sudoPassword, progressChan, 0.40, 0.85, make(map[string]bool)); err != nil {
				return err
			}
			continue
		}

		command := "pacman -S --noconfirm --ask=4 " + swap.To.Name
		if err := a.runWithProgress(privesc.ExecCommand(ctx, sudoPassword, command), progressChan, PhaseSystemPackages, 0.40, 0.85); err != nil {
			return fmt.Errorf("failed to switch %s to %s: %w", swap.From.Name, swap.To.Name, err)
		}
	}
	return nil
}

func (a *ArchDistribution) installSystemPackages(ctx context.Context, packages []string, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if len(packages) == 0 {
		return nil
	}

	a.log(fmt.Sprintf("Installing system packages: %s", strings.Join(packages, ", ")))

	args := append([]string{"pacman", "-S", "--needed", "--noconfirm"}, packages...)

	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.40,
		Step:        "Installing system packages...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: fmt.Sprintf("sudo %s", strings.Join(args, " ")),
	}

	cmd := privesc.ExecCommand(ctx, sudoPassword, strings.Join(args, " "))
	return a.runWithProgress(cmd, progressChan, PhaseSystemPackages, 0.40, 0.60)
}

func (a *ArchDistribution) installAURPackages(ctx context.Context, packages []string, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if len(packages) == 0 {
		return nil
	}

	a.log(fmt.Sprintf("Installing AUR packages manually: %s", strings.Join(packages, ", ")))

	hasNiri := false
	for _, pkg := range packages {
		if pkg == "niri-git" {
			hasNiri = true
		}
	}

	// If niri is in the list, install makepkg-git-lfs-proto first if not already installed
	if hasNiri {
		if !a.packageInstalled("makepkg-git-lfs-proto") {
			progressChan <- InstallProgressMsg{
				Phase:       PhaseAURPackages,
				Progress:    0.65,
				Step:        "Installing makepkg-git-lfs-proto for niri...",
				IsComplete:  false,
				CommandInfo: "Installing prerequisite for niri-git",
			}

			if err := a.installSingleAURPackage(ctx, "makepkg-git-lfs-proto", sudoPassword, progressChan, 0.65, 0.67); err != nil {
				return fmt.Errorf("failed to install makepkg-git-lfs-proto prerequisite for niri: %w", err)
			}
		}
	}

	// Reorder packages to ensure dux-shell-git dependencies are installed first
	orderedPackages := a.reorderAURPackages(packages)

	baseProgress := 0.67
	progressStep := 0.13 / float64(len(orderedPackages))

	for i, pkg := range orderedPackages {
		currentProgress := baseProgress + (float64(i) * progressStep)

		progressChan <- InstallProgressMsg{
			Phase:       PhaseAURPackages,
			Progress:    currentProgress,
			Step:        fmt.Sprintf("Installing AUR package %s (%d/%d)...", pkg, i+1, len(packages)),
			IsComplete:  false,
			CommandInfo: fmt.Sprintf("Building and installing %s", pkg),
		}

		if err := a.installSingleAURPackage(ctx, pkg, sudoPassword, progressChan, currentProgress, currentProgress+progressStep); err != nil {
			return fmt.Errorf("failed to install AUR package %s: %w", pkg, err)
		}
	}

	progressChan <- InstallProgressMsg{
		Phase:      PhaseAURPackages,
		Progress:   0.80,
		Step:       "All AUR packages installed successfully",
		IsComplete: false,
		LogOutput:  fmt.Sprintf("Successfully installed AUR packages: %s", strings.Join(packages, ", ")),
	}

	return nil
}

func (a *ArchDistribution) reorderAURPackages(packages []string) []string {
	dmsDepencies := []string{"quickshell", "quickshell-git"}

	var deps []string
	var others []string
	var dmsShell []string

	for _, pkg := range packages {
		if pkg == "dux-shell-git" {
			dmsShell = append(dmsShell, pkg)
		} else {
			isDep := false
			if slices.Contains(dmsDepencies, pkg) {
				deps = append(deps, pkg)
				isDep = true
			}
			if !isDep {
				others = append(others, pkg)
			}
		}
	}

	result := append(deps, others...)
	result = append(result, dmsShell...)
	return result
}

func (a *ArchDistribution) installSingleAURPackage(ctx context.Context, pkg, sudoPassword string, progressChan chan<- InstallProgressMsg, startProgress, endProgress float64) error {
	return a.installSingleAURPackageInternal(ctx, pkg, "", sudoPassword, progressChan, startProgress, endProgress, make(map[string]bool))
}

// installSingleAURPackageInternal removes replaces only after pkg built, so a failed build keeps the old variant.
func (a *ArchDistribution) installSingleAURPackageInternal(ctx context.Context, pkg, replaces, sudoPassword string, progressChan chan<- InstallProgressMsg, startProgress, endProgress float64, visited map[string]bool) error {
	if visited[pkg] {
		a.log(fmt.Sprintf("Skipping %s (already being installed, cycle detected)", pkg))
		return nil
	}
	visited[pkg] = true

	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("failed to get user home directory: %w", err)
	}

	buildDir := filepath.Join(homeDir, ".cache", "duxinstall", "aur-builds", pkg)

	// Clean up any existing cache first
	if err := os.RemoveAll(buildDir); err != nil {
		a.log(fmt.Sprintf("Warning: failed to clean existing cache for %s: %v", pkg, err))
	}

	if err := os.MkdirAll(buildDir, 0o755); err != nil {
		return fmt.Errorf("failed to create build directory: %w", err)
	}
	defer func() {
		if removeErr := os.RemoveAll(buildDir); removeErr != nil {
			a.log(fmt.Sprintf("Warning: failed to cleanup build directory %s: %v", buildDir, removeErr))
		}
	}()

	// Clone the AUR package
	progressChan <- InstallProgressMsg{
		Phase:       PhaseAURPackages,
		Progress:    startProgress + 0.1*(endProgress-startProgress),
		Step:        fmt.Sprintf("Cloning %s from AUR...", pkg),
		IsComplete:  false,
		CommandInfo: fmt.Sprintf("git clone https://aur.archlinux.org/%s.git", pkg),
	}

	cloneCmd := exec.CommandContext(ctx, "git", "clone", fmt.Sprintf("https://aur.archlinux.org/%s.git", pkg), filepath.Join(buildDir, pkg))
	if err := a.runWithProgress(cloneCmd, progressChan, PhaseAURPackages, startProgress+0.1*(endProgress-startProgress), startProgress+0.2*(endProgress-startProgress)); err != nil {
		return fmt.Errorf("failed to clone %s: %w", pkg, err)
	}

	packageDir := filepath.Join(buildDir, pkg)

	if pkg == "niri-git" {
		pkgbuildPath := filepath.Join(packageDir, "PKGBUILD")
		sedCmd := exec.CommandContext(ctx, "sed", "-i", "s/makepkg-git-lfs-proto//g", pkgbuildPath)
		if err := sedCmd.Run(); err != nil {
			return fmt.Errorf("failed to patch PKGBUILD for niri-git: %w", err)
		}

		srcinfoPath := filepath.Join(packageDir, ".SRCINFO")
		sedCmd2 := exec.CommandContext(ctx, "sed", "-i", "/makedepends = makepkg-git-lfs-proto/d", srcinfoPath)
		if err := sedCmd2.Run(); err != nil {
			return fmt.Errorf("failed to patch .SRCINFO for niri-git: %w", err)
		}
	}

	if pkg == "dux-shell-git" {
		srcinfoPath := filepath.Join(packageDir, ".SRCINFO")
		// extra ships dgop only as dux-gop (provides dgop), which makepkg resolves but pacman -Si does not
		srcinfoEdits := []string{
			"/depends = quickshell/d",
			`s/^\(\s*depends = \)dgop$/\1dux-gop/`,
		}

		for _, edit := range srcinfoEdits {
			sedCmd := exec.CommandContext(ctx, "sed", "-i", edit, srcinfoPath)
			if err := sedCmd.Run(); err != nil {
				return fmt.Errorf("failed to patch .SRCINFO for %s: %w", pkg, err)
			}
		}
	}

	// Remove all optdepends from .SRCINFO for all packages
	srcinfoPath := filepath.Join(packageDir, ".SRCINFO")
	optdepsCmd := exec.CommandContext(ctx, "sed", "-i", "/^[[:space:]]*optdepends = /d", srcinfoPath)
	if err := optdepsCmd.Run(); err != nil {
		return fmt.Errorf("failed to remove optdepends from .SRCINFO for %s: %w", pkg, err)
	}

	srcinfoPath = filepath.Join(packageDir, ".SRCINFO")
	{
		progressChan <- InstallProgressMsg{
			Phase:       PhaseAURPackages,
			Progress:    startProgress + 0.3*(endProgress-startProgress),
			Step:        fmt.Sprintf("Resolving dependencies for %s...", pkg),
			IsComplete:  false,
			CommandInfo: "Classifying dependencies as system or AUR",
		}

		runtimeDeps, makeDeps, err := parseSRCINFODeps(srcinfoPath)
		if err != nil {
			return fmt.Errorf("failed to parse .SRCINFO for %s: %w", pkg, err)
		}

		seen := make(map[string]bool)
		var systemPkgs []string
		var aurPkgs []string

		for _, dep := range append(runtimeDeps, makeDeps...) {
			if seen[dep] || a.packageInstalled(dep) {
				continue
			}
			seen[dep] = true
			if isSonameProvides(dep) || a.isInSystemRepo(dep) {
				systemPkgs = append(systemPkgs, dep)
			} else {
				aurPkgs = append(aurPkgs, dep)
			}
		}

		if len(systemPkgs) > 0 {
			progressChan <- InstallProgressMsg{
				Phase:       PhaseAURPackages,
				Progress:    startProgress + 0.32*(endProgress-startProgress),
				Step:        fmt.Sprintf("Installing %d system dependencies for %s...", len(systemPkgs), pkg),
				IsComplete:  false,
				CommandInfo: fmt.Sprintf("sudo pacman -S --needed --noconfirm %s", strings.Join(systemPkgs, " ")),
			}
			if err := a.installSystemPackages(ctx, systemPkgs, sudoPassword, progressChan); err != nil {
				return fmt.Errorf("failed to install system dependencies for %s: %w", pkg, err)
			}
		}

		for _, aurDep := range aurPkgs {
			a.log(fmt.Sprintf("Dependency %s is AUR-only, building from source...", aurDep))
			progressChan <- InstallProgressMsg{
				Phase:       PhaseAURPackages,
				Progress:    startProgress + 0.35*(endProgress-startProgress),
				Step:        fmt.Sprintf("Installing AUR dependency %s for %s...", aurDep, pkg),
				IsComplete:  false,
				CommandInfo: fmt.Sprintf("Building AUR dependency: %s", aurDep),
			}
			if err := a.installSingleAURPackageInternal(ctx, aurDep, "", sudoPassword, progressChan,
				startProgress+0.35*(endProgress-startProgress),
				startProgress+0.39*(endProgress-startProgress),
				visited,
			); err != nil {
				return fmt.Errorf("failed to install AUR dependency %s for %s: %w", aurDep, pkg, err)
			}
		}
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhaseAURPackages,
		Progress:    startProgress + 0.4*(endProgress-startProgress),
		Step:        fmt.Sprintf("Building %s...", pkg),
		IsComplete:  false,
		CommandInfo: "makepkg --noconfirm",
	}

	buildCmd := exec.CommandContext(ctx, "makepkg", "--noconfirm")
	buildCmd.Dir = packageDir
	buildCmd.Env = append(os.Environ(), "PKGEXT=.pkg.tar")

	if err := a.runWithProgress(buildCmd, progressChan, PhaseAURPackages, startProgress+0.4*(endProgress-startProgress), startProgress+0.7*(endProgress-startProgress)); err != nil {
		return fmt.Errorf("failed to build %s: %w", pkg, err)
	}

	// Find built package file
	progressChan <- InstallProgressMsg{
		Phase:       PhaseAURPackages,
		Progress:    startProgress + 0.7*(endProgress-startProgress),
		Step:        fmt.Sprintf("Installing %s...", pkg),
		IsComplete:  false,
		CommandInfo: "sudo pacman -U built-package",
	}

	var files []string
	matches, _ := filepath.Glob(filepath.Join(packageDir, "*.pkg.tar*"))
	files = matches

	if len(files) == 0 {
		return fmt.Errorf("no package files found after building %s", pkg)
	}

	installArgs := []string{"pacman", "-U", "--noconfirm"}
	installArgs = append(installArgs, files...)

	command := strings.Join(installArgs, " ")
	if replaces != "" {
		command = fmt.Sprintf("sh -c '%s'", privesc.EscapeSingleQuotes("pacman -Rdd --noconfirm "+replaces+" && "+command))
	}
	installCmd := privesc.ExecCommand(ctx, sudoPassword, command)

	fileNames := make([]string, len(files))
	for i, f := range files {
		fileNames[i] = filepath.Base(f)
	}

	progressChan <- InstallProgressMsg{
		Phase:     PhaseAURPackages,
		Progress:  startProgress + 0.7*(endProgress-startProgress),
		LogOutput: fmt.Sprintf("Installing packages: %s", strings.Join(fileNames, ", ")),
	}

	if err := a.runWithProgress(installCmd, progressChan, PhaseAURPackages, startProgress+0.7*(endProgress-startProgress), endProgress); err != nil {
		progressChan <- InstallProgressMsg{
			Phase:     PhaseAURPackages,
			Progress:  startProgress,
			LogOutput: fmt.Sprintf("ERROR: pacman -U failed for %s with error: %v", pkg, err),
			Error:     err,
		}
		return fmt.Errorf("failed to install built package %s: %w", pkg, err)
	}

	a.log(fmt.Sprintf("Successfully installed AUR package: %s", pkg))
	return nil
}
