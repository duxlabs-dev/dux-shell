package distros

import (
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"os/exec"
	"slices"
	"strings"
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

func init() {
	Register("fedora", "#0B57A4", FamilyFedora, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewFedoraDistribution(config, logChan)
	})
	Register("evernight", "#72B8DC", FamilyFedora, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewFedoraDistribution(config, logChan)
	})
	Register("nobara", "#0B57A4", FamilyFedora, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewFedoraDistribution(config, logChan)
	})
	Register("fedora-asahi-remix", "#0B57A4", FamilyFedora, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewFedoraDistribution(config, logChan)
	})
	Register("ultramarine", "#00078b", FamilyFedora, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewFedoraDistribution(config, logChan)
	})
	Register("rhel", "#EE0000", FamilyFedora, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewFedoraDistribution(config, logChan)
	})
	Register("centos", "#9CCD2A", FamilyFedora, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewFedoraDistribution(config, logChan)
	})
	Register("rocky", "#10B981", FamilyFedora, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewFedoraDistribution(config, logChan)
	})
	Register("almalinux", "#0069DA", FamilyFedora, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewFedoraDistribution(config, logChan)
	})
}

var enterpriseLinuxIDs = map[string]bool{"rhel": true, "centos": true, "rocky": true, "almalinux": true}

// IsEnterpriseLinux reports whether id is RHEL or a rebuild; EL 10 installs from EPEL 10 and the COPRs' epel-10 chroots.
func IsEnterpriseLinux(id string) bool {
	return enterpriseLinuxIDs[id]
}

type FedoraDistribution struct {
	*BaseDistribution
	*ManualPackageInstaller
	config DistroConfig

	rpmInstalled    func(pkg string) bool
	ostreeRequested func() []string
}

func NewFedoraDistribution(config DistroConfig, logChan chan<- string) *FedoraDistribution {
	base := NewBaseDistribution(logChan)
	return &FedoraDistribution{
		BaseDistribution:       base,
		ManualPackageInstaller: &ManualPackageInstaller{BaseDistribution: base},
		config:                 config,
	}
}

func (f *FedoraDistribution) GetID() string {
	return f.config.ID
}

func (f *FedoraDistribution) GetColorHex() string {
	return f.config.ColorHex
}

func (f *FedoraDistribution) GetFamily() DistroFamily {
	return f.config.Family
}

func (f *FedoraDistribution) GetPackageManager() PackageManagerType {
	return PackageManagerDNF
}

func (f *FedoraDistribution) isEL() bool {
	return IsEnterpriseLinux(f.config.ID)
}

func (f *FedoraDistribution) DetectDependencies(ctx context.Context, wm deps.WindowManager) ([]deps.Dependency, error) {
	return f.DetectDependenciesWithTerminal(ctx, wm, deps.TerminalGhostty)
}

func (f *FedoraDistribution) DetectDependenciesWithTerminal(ctx context.Context, wm deps.WindowManager, terminal deps.Terminal) ([]deps.Dependency, error) {
	var dependencies []deps.Dependency

	// DMS at the top (shell is prominent)
	dependencies = append(dependencies, f.detectDMS())

	// Terminal with choice support
	dependencies = append(dependencies, f.detectSpecificTerminal(terminal))

	// Common detections using base methods
	dependencies = append(dependencies, f.detectGit())
	wmDep := f.detectWindowManager(wm)
	if wm == deps.WindowManagerMango {
		wmDep.Description = "MangoWM (Wayland compositor) — the Terra repo will be enabled automatically to install it"
	}
	dependencies = append(dependencies, wmDep)
	dependencies = append(dependencies, f.detectQuickshell())
	dependencies = append(dependencies, f.detectGreeterPackage(f.packageInstalled))
	dependencies = append(dependencies, f.detectXDGPortal())
	dependencies = append(dependencies, f.detectAccountsService())

	// Hyprland-specific tools
	if wm == deps.WindowManagerHyprland {
		dependencies = append(dependencies, f.detectHyprlandTools()...)
		dependencies = append(dependencies, f.detectHyprlandGuiutils())
	}

	// Niri-specific tools
	if wm == deps.WindowManagerNiri {
		dependencies = append(dependencies, f.detectXwaylandSatellite())
	}

	// Mango-specific tools (dwl-based, uses xwayland-satellite like niri)
	if wm == deps.WindowManagerMango {
		dependencies = append(dependencies, f.detectXwaylandSatellite())
	}

	dependencies = append(dependencies, f.detectMatugen())
	dependencies = append(dependencies, f.detectDanksearch())
	dependencies = append(dependencies, f.detectCalendarPackage(f.packageInstalled))

	return dependencies, nil
}

func (f *FedoraDistribution) detectXDGPortal() deps.Dependency {
	return f.detectPackage("xdg-desktop-portal-gtk", "Desktop integration portal for GTK", f.packageInstalled("xdg-desktop-portal-gtk"))
}

func (f *FedoraDistribution) packageInstalled(pkg string) bool {
	if f.rpmInstalled != nil {
		return f.rpmInstalled(pkg)
	}
	cmd := exec.Command("rpm", "-q", pkg)
	err := cmd.Run()
	return err == nil
}

func (f *FedoraDistribution) InstalledVariant(stable, git PackageMapping) (deps.PackageVariant, bool) {
	if stable.Name != git.Name {
		return installedVariantByName(f.packageInstalled, stable, git)
	}
	if !f.packageInstalled(stable.Name) {
		return deps.VariantStable, false
	}
	if git.Repository == RepoTypeCOPR && installedFromCOPR(stable.Name, git.RepoURL) {
		return deps.VariantGit, true
	}
	return deps.VariantStable, true
}

var installedFromCOPR = fedoraInstalledFromCOPR

// fedoraInstalledFromCOPR tells same-named variants apart (dms, niri), which only differ by COPR.
func fedoraInstalledFromCOPR(pkg, coprRepo string) bool {
	out, err := exec.Command("dnf", "repoquery", "--installed", "--qf", "%{from_repo}", pkg).Output()
	if err != nil {
		return rpmLooksLikeGitBuild(pkg)
	}
	return coprFromRepoMatches(string(out), coprRepo)
}

// niri-git carries "git" in its version; dms-git only differs by its Epoch of 2.
func rpmLooksLikeGitBuild(pkg string) bool {
	out, err := exec.Command("rpm", "-q", "--qf", "%{EPOCH} %{VERSION}-%{RELEASE}", pkg).Output()
	if err != nil {
		return false
	}
	epoch, versionRelease, _ := strings.Cut(strings.TrimSpace(string(out)), " ")
	return strings.Contains(versionRelease, "git") || (pkg == "dms" && epoch == "2")
}

func (f *FedoraDistribution) SwapVariants(ctx context.Context, swaps []VariantSwap, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if err := f.enableCOPRRepos(ctx, swapTargets(swaps, RepoTypeCOPR), sudoPassword, progressChan); err != nil {
		return err
	}

	for _, swap := range swaps {
		command := fmt.Sprintf("dnf swap -y %s %s", swap.From.Name, swap.To.Name)
		var disabledRepos []string
		if swap.From.Name == swap.To.Name {
			// Left enabled, the old COPR wins distro-sync whenever its version sorts higher (dms-git has Epoch 2).
			// An un-migrated host still has it under the legacy owner, so every alias goes.
			if swap.From.Repository == RepoTypeCOPR {
				for _, repo := range coprAliases(swap.From.RepoURL) {
					if !repoPathExists(coprRepoFile(repo)) {
						continue
					}
					if err := f.coprRepoOp(ctx, "disable", repo, sudoPassword, progressChan); err != nil {
						return err
					}
					disabledRepos = append(disabledRepos, repo)
				}
			}
			command = "dnf distro-sync -y " + swap.To.Name
		}

		progressChan <- InstallProgressMsg{
			Phase:       PhaseSystemPackages,
			Progress:    0.40,
			Step:        fmt.Sprintf("Switching %s to %s...", swap.From.Name, swap.To.Name),
			NeedsSudo:   true,
			CommandInfo: "sudo " + command,
		}
		if err := f.runWithProgress(privescExec(ctx, sudoPassword, command), progressChan, PhaseSystemPackages, 0.40, 0.85); err != nil {
			for _, repo := range disabledRepos {
				if reErr := privescExec(ctx, sudoPassword, "dnf copr enable -y "+repo).Run(); reErr != nil {
					f.log(fmt.Sprintf("Warning: could not re-enable COPR repo %s: %v", repo, reErr))
				}
			}
			return fmt.Errorf("failed to switch %s to %s: %w", swap.From.Name, swap.To.Name, err)
		}
	}
	return nil
}

func (f *FedoraDistribution) coprRepoOp(ctx context.Context, verb, repo, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	command := fmt.Sprintf("dnf copr %s -y %s", verb, repo)
	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.30,
		Step:        fmt.Sprintf("Running dnf copr %s %s...", verb, repo),
		NeedsSudo:   true,
		CommandInfo: "sudo " + command,
	}
	if err := f.runWithProgress(privescExec(ctx, sudoPassword, command), progressChan, PhaseSystemPackages, 0.30, 0.35); err != nil {
		return fmt.Errorf("failed to %s COPR repo %s: %w", verb, repo, err)
	}
	return nil
}

func (f *FedoraDistribution) RepoMoves() []RepoMove {
	return coprChannel.moves(repoPathExists)
}

func (f *FedoraDistribution) ApplyRepoMoves(ctx context.Context, moves []RepoMove, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if err := f.enableCOPRRepos(ctx, repoMoveAdds(moves), sudoPassword, progressChan); err != nil {
		return err
	}
	for _, move := range repoMoveRemoves(moves) {
		if err := f.coprRepoOp(ctx, "remove", move.Old, sudoPassword, progressChan); err != nil {
			return err
		}
	}
	return nil
}

func (f *FedoraDistribution) RepoMoveCommands(moves []RepoMove) []string {
	var commands []string
	for _, add := range repoMoveAdds(moves) {
		commands = append(commands, "sudo dnf copr enable -y "+add.RepoURL)
	}
	for _, move := range repoMoveRemoves(moves) {
		commands = append(commands, "sudo dnf copr remove -y "+move.Old)
	}
	return commands
}

// Shown to the user, never run: image-based Fedora has no dnf copr.
func (f *FedoraDistribution) ImageRepoMoveCommands(moves []RepoMove) []string {
	var commands []string
	for _, add := range repoMoveAdds(moves) {
		commands = append(commands, f.coprRepoFileCommand(add.RepoURL))
	}
	for _, move := range repoMoveRemoves(moves) {
		commands = append(commands, "sudo rm -f "+move.OldPath)
	}
	return commands
}

func (f *FedoraDistribution) GetPackageMapping(wm deps.WindowManager) map[string]PackageMapping {
	return f.GetPackageMappingWithVariants(wm, make(map[string]deps.PackageVariant))
}

func (f *FedoraDistribution) GetPackageMappingWithVariants(wm deps.WindowManager, variants map[string]deps.PackageVariant) map[string]PackageMapping {
	packages := map[string]PackageMapping{
		// Standard DNF packages
		"git":                    {Name: "git", Repository: RepoTypeSystem},
		"ghostty":                {Name: "ghostty", Repository: RepoTypeCOPR, RepoURL: coprDeps},
		"kitty":                  {Name: "kitty", Repository: RepoTypeSystem},
		"alacritty":              {Name: "alacritty", Repository: RepoTypeSystem},
		"xdg-desktop-portal-gtk": {Name: "xdg-desktop-portal-gtk", Repository: RepoTypeSystem},
		"accountsservice":        {Name: "accountsservice", Repository: RepoTypeSystem},

		// COPR packages
		"quickshell":      f.getQuickshellMapping(variants["quickshell"]),
		"dms-greeter":     variantMapping("dux-greeter", variants["dms-greeter"], RepoTypeCOPR, coprDeps),
		"matugen":         {Name: "matugen", Repository: RepoTypeCOPR, RepoURL: coprDeps},
		"dms (Dux Shell)": f.getDmsMapping(variants["dms (Dux Shell)"]),
		"danksearch":      {Name: "dux-search", Repository: RepoTypeCOPR, RepoURL: coprDeps},
		"dankcalendar":    variantMapping("dux-calendar", variants["dankcalendar"], RepoTypeCOPR, coprDeps),
	}

	switch wm {
	case deps.WindowManagerHyprland:
		packages["hyprland"] = f.getHyprlandMapping(variants["hyprland"])
		packages["hyprctl"] = f.getHyprlandMapping(variants["hyprland"])
		packages["jq"] = PackageMapping{Name: "jq", Repository: RepoTypeSystem}
		packages["hyprland-guiutils"] = PackageMapping{Name: "hyprland-guiutils", Repository: RepoTypeCOPR, RepoURL: "lionheartp/Hyprland"}
	case deps.WindowManagerNiri:
		packages["niri"] = f.getNiriMapping(variants["niri"])
		packages["xwayland-satellite"] = PackageMapping{Name: "xwayland-satellite", Repository: RepoTypeSystem}
	case deps.WindowManagerMango:
		// mangowm resolves via Terra, enabled automatically by enableTerraRepo.
		packages["mango"] = PackageMapping{Name: "mangowm", Repository: RepoTypeSystem}
		packages["xwayland-satellite"] = PackageMapping{Name: "xwayland-satellite", Repository: RepoTypeSystem}
	}

	if f.isEL() {
		// EPEL 10 has neither, so the deps COPR builds them for the epel-10 chroots.
		for _, name := range []string{"alacritty", "xwayland-satellite"} {
			if _, ok := packages[name]; ok {
				packages[name] = PackageMapping{Name: name, Repository: RepoTypeCOPR, RepoURL: coprDeps}
			}
		}
	}

	return packages
}

func (f *FedoraDistribution) getQuickshellMapping(variant deps.PackageVariant) PackageMapping {
	if forceQuickshellGit || variant == deps.VariantGit {
		return PackageMapping{Name: "quickshell-git", Repository: RepoTypeCOPR, RepoURL: coprDeps}
	}
	return PackageMapping{Name: "quickshell", Repository: RepoTypeCOPR, RepoURL: coprDeps}
}

func (f *FedoraDistribution) getDmsMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "dms", Repository: RepoTypeCOPR, RepoURL: coprDMSGit}
	}
	return PackageMapping{Name: "dms", Repository: RepoTypeCOPR, RepoURL: coprDMS}
}

func (f *FedoraDistribution) getHyprlandMapping(_ deps.PackageVariant) PackageMapping {
	return PackageMapping{Name: "hyprland", Repository: RepoTypeCOPR, RepoURL: "lionheartp/Hyprland"}
}

func (f *FedoraDistribution) getNiriMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "niri", Repository: RepoTypeCOPR, RepoURL: "yalter/niri-git"}
	}
	return PackageMapping{Name: "niri", Repository: RepoTypeCOPR, RepoURL: "yalter/niri"}
}

func (f *FedoraDistribution) detectXwaylandSatellite() deps.Dependency {
	status := deps.StatusMissing
	if f.commandExists("xwayland-satellite") {
		status = deps.StatusInstalled
	}

	return deps.Dependency{
		Name:        "xwayland-satellite",
		Status:      status,
		Description: "Xwayland support",
		Required:    true,
	}
}

func (f *FedoraDistribution) detectAccountsService() deps.Dependency {
	status := deps.StatusMissing
	if f.packageInstalled("accountsservice") {
		status = deps.StatusInstalled
	}

	return deps.Dependency{
		Name:        "accountsservice",
		Status:      status,
		Description: "D-Bus interface for user account query and manipulation",
		Required:    true,
	}
}

func (f *FedoraDistribution) getPrerequisites() []string {
	return []string{
		"dnf-plugins-core",
		"make",
		"unzip",
		"libwayland-server",
	}
}

// enableEPEL installs epel-release on EL hosts; kitty and the COPR chroots' build deps live there.
// RHEL has no epel-release in its own repos, the rebuilds ship it in extras.
func (f *FedoraDistribution) enableEPEL(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if exec.CommandContext(ctx, "rpm", "-q", "epel-release").Run() == nil {
		f.log("EPEL already enabled, skipping")
		return nil
	}

	pkg := "epel-release"
	if f.config.ID == "rhel" {
		pkg = "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm"
	}
	progressChan <- InstallProgressMsg{
		Phase:       PhasePrerequisites,
		Progress:    0.07,
		Step:        "Enabling EPEL repository...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: "sudo dnf install -y " + pkg,
		LogOutput:   "Enabling EPEL for Enterprise Linux",
	}
	output, err := privesc.ExecCommand(ctx, sudoPassword, "dnf install -y "+pkg+" 2>&1").CombinedOutput()
	if err != nil {
		f.logError("failed to enable EPEL", err)
		f.log(fmt.Sprintf("EPEL enable output: %s", string(output)))
		return fmt.Errorf("failed to enable EPEL: %w", err)
	}
	f.log("EPEL enabled")
	return nil
}

func (f *FedoraDistribution) InstallPrerequisites(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if f.isEL() {
		if err := f.enableEPEL(ctx, sudoPassword, progressChan); err != nil {
			return err
		}
	}

	prerequisites := f.getPrerequisites()
	var missingPkgs []string

	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.06,
		Step:       "Checking prerequisites...",
		IsComplete: false,
		LogOutput:  "Checking prerequisite packages",
	}

	for _, pkg := range prerequisites {
		checkCmd := exec.CommandContext(ctx, "rpm", "-q", pkg)
		if err := checkCmd.Run(); err != nil {
			missingPkgs = append(missingPkgs, pkg)
		}
	}

	_, err := exec.LookPath("go")
	if err != nil {
		f.log("go not found in PATH, will install golang-bin")
		missingPkgs = append(missingPkgs, "golang-bin")
	} else {
		f.log("go already available in PATH")
	}

	if len(missingPkgs) == 0 {
		f.log("All prerequisites already installed")
		return nil
	}

	f.log(fmt.Sprintf("Installing prerequisites: %s", strings.Join(missingPkgs, ", ")))
	progressChan <- InstallProgressMsg{
		Phase:       PhasePrerequisites,
		Progress:    0.08,
		Step:        fmt.Sprintf("Installing %d prerequisites...", len(missingPkgs)),
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: fmt.Sprintf("sudo dnf install -y %s", strings.Join(missingPkgs, " ")),
		LogOutput:   fmt.Sprintf("Installing prerequisites: %s", strings.Join(missingPkgs, ", ")),
	}

	args := []string{"dnf", "install", "-y"}
	args = append(args, missingPkgs...)
	cmd := privesc.ExecCommand(ctx, sudoPassword, strings.Join(args, " "))
	output, err := cmd.CombinedOutput()
	if err != nil {
		f.logError("failed to install prerequisites", err)
		f.log(fmt.Sprintf("Prerequisites command output: %s", string(output)))
		return fmt.Errorf("failed to install prerequisites: %w", err)
	}
	f.log(fmt.Sprintf("Prerequisites install output: %s", string(output)))

	return nil
}

func (f *FedoraDistribution) InstallPackages(ctx context.Context, dependencies []deps.Dependency, wm deps.WindowManager, sudoPassword string, reinstallFlags map[string]bool, disabledFlags map[string]bool, skipGlobalUseFlags bool, progressChan chan<- InstallProgressMsg) error {
	// Phase 1: Check Prerequisites
	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.05,
		Step:       "Checking system prerequisites...",
		IsComplete: false,
		LogOutput:  "Starting prerequisite check...",
	}

	if err := f.InstallPrerequisites(ctx, sudoPassword, progressChan); err != nil {
		return fmt.Errorf("failed to install prerequisites: %w", err)
	}

	skipFlags, err := swapReinstalledVariants(ctx, f, dependencies, wm, reinstallFlags, disabledFlags, sudoPassword, progressChan)
	if err != nil {
		return err
	}

	dnfPkgs, coprPkgs, manualPkgs, variantMap := f.categorizePackages(dependencies, wm, reinstallFlags, skipFlags)

	// Phase 2: Enable COPR repositories
	if len(coprPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.15,
			Step:       "Enabling COPR repositories...",
			IsComplete: false,
			LogOutput:  "Setting up COPR repositories for additional packages",
		}
		if err := f.enableCOPRRepos(ctx, coprPkgs, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to enable COPR repositories: %w", err)
		}
	}

	// Phase 2b: Enable Terra repo for MangoWM (not in Fedora's repos). Must run
	// before the DNF phase so `mangowm` resolves.
	if wm == deps.WindowManagerMango {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.25,
			Step:       "Enabling Terra repository for MangoWM...",
			IsComplete: false,
			NeedsSudo:  true,
			LogOutput:  "Setting up the Terra repo (fyralabs) to provide mango",
		}
		if err := f.enableTerraRepo(ctx, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to enable Terra repository: %w", err)
		}
	}

	// Phase 3: System Packages (DNF)
	if len(dnfPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.35,
			Step:       fmt.Sprintf("Installing %d system packages...", len(dnfPkgs)),
			IsComplete: false,
			NeedsSudo:  true,
			LogOutput:  fmt.Sprintf("Installing system packages: %s", strings.Join(dnfPkgs, ", ")),
		}
		if err := f.installDNFPackages(ctx, dnfPkgs, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install DNF packages: %w", err)
		}
	}

	// Phase 4: COPR Packages
	coprPkgNames := f.extractPackageNames(coprPkgs)
	if len(coprPkgNames) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseAURPackages, // Reusing AUR phase for COPR
			Progress:   0.65,
			Step:       fmt.Sprintf("Installing %d COPR packages...", len(coprPkgNames)),
			IsComplete: false,
			LogOutput:  fmt.Sprintf("Installing COPR packages: %s", strings.Join(coprPkgNames, ", ")),
		}
		if err := f.installCOPRPackages(ctx, coprPkgNames, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install COPR packages: %w", err)
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
		if err := f.InstallManualPackages(ctx, manualPkgs, variantMap, sudoPassword, progressChan); err != nil {
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

	terminal := f.DetectTerminalFromDeps(dependencies)
	if err := f.WriteEnvironmentConfig(terminal); err != nil {
		f.log(fmt.Sprintf("Warning: failed to write environment config: %v", err))
	}

	if err := f.WriteWindowManagerConfig(wm); err != nil {
		f.log(fmt.Sprintf("Warning: failed to write window manager config: %v", err))
	}

	if err := f.EnableDMSService(ctx, wm); err != nil {
		f.log(fmt.Sprintf("Warning: failed to enable dms service: %v", err))
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

func (f *FedoraDistribution) categorizePackages(dependencies []deps.Dependency, wm deps.WindowManager, reinstallFlags map[string]bool, disabledFlags map[string]bool) ([]string, []PackageMapping, []string, map[string]deps.PackageVariant) {
	dnfPkgs := []string{}
	coprPkgs := []PackageMapping{}
	manualPkgs := []string{}

	variantMap := make(map[string]deps.PackageVariant)
	for _, dep := range dependencies {
		variantMap[dep.Name] = dep.Variant
	}

	packageMap := f.GetPackageMappingWithVariants(wm, variantMap)

	for _, dep := range dependencies {
		if disabledFlags[dep.Name] {
			continue
		}

		if dep.Status == deps.StatusInstalled && !reinstallFlags[dep.Name] {
			continue
		}

		pkgInfo, exists := packageMap[dep.Name]
		if !exists {
			f.log(fmt.Sprintf("Warning: No package mapping for %s", dep.Name))
			continue
		}

		switch pkgInfo.Repository {
		case RepoTypeSystem:
			dnfPkgs = append(dnfPkgs, pkgInfo.Name)
		case RepoTypeCOPR:
			coprPkgs = append(coprPkgs, pkgInfo)
		case RepoTypeManual:
			manualPkgs = append(manualPkgs, dep.Name)
		}
	}

	return dnfPkgs, coprPkgs, manualPkgs, variantMap
}

func (f *FedoraDistribution) extractPackageNames(packages []PackageMapping) []string {
	names := make([]string, len(packages))
	for i, pkg := range packages {
		names[i] = pkg.Name
	}
	return names
}

// enableTerraRepo registers the persistent Terra repo (via terra-release) so
// `mangowm` resolves in the DNF phase. $releasever is single-quoted so dnf, not
// the shell, expands it.
func (f *FedoraDistribution) enableTerraRepo(ctx context.Context, sudoPassword string, _ chan<- InstallProgressMsg) error {
	// Skip if Terra is already configured
	if exec.CommandContext(ctx, "sh", "-c",
		"rpm -q terra-release >/dev/null 2>&1 || test -f /etc/yum.repos.d/terra.repo").Run() == nil {
		f.log("Terra repository already configured, skipping enable")
		return nil
	}

	f.log("Enabling Terra repository (fyralabs) for mango...")
	cmd := privesc.ExecCommand(ctx, sudoPassword,
		`dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release 2>&1`)
	output, err := cmd.CombinedOutput()
	if err != nil {
		f.logError("failed to enable Terra repository", err)
		f.log(fmt.Sprintf("Terra enable output: %s", string(output)))
		return fmt.Errorf("failed to enable Terra repository: %w", err)
	}
	f.log(fmt.Sprintf("Terra repository enabled: %s", string(output)))
	return nil
}

func (f *FedoraDistribution) enableCOPRRepos(ctx context.Context, coprPkgs []PackageMapping, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	enabledRepos := make(map[string]bool)

	for _, pkg := range coprPkgs {
		if pkg.RepoURL != "" && !enabledRepos[pkg.RepoURL] {
			f.log(fmt.Sprintf("Enabling COPR repository: %s", pkg.RepoURL))
			progressChan <- InstallProgressMsg{
				Phase:       PhaseSystemPackages,
				Progress:    0.20,
				Step:        fmt.Sprintf("Enabling COPR repo %s...", pkg.RepoURL),
				IsComplete:  false,
				NeedsSudo:   true,
				CommandInfo: fmt.Sprintf("sudo dnf copr enable -y %s", pkg.RepoURL),
			}

			cmd := privescExec(ctx, sudoPassword,
				fmt.Sprintf("dnf copr enable -y %s 2>&1", pkg.RepoURL))
			output, err := cmd.CombinedOutput()
			if err != nil {
				f.logError(fmt.Sprintf("failed to enable COPR repo %s", pkg.RepoURL), err)
				f.log(fmt.Sprintf("COPR enable command output: %s", string(output)))
				return fmt.Errorf("failed to enable COPR repo %s: %w", pkg.RepoURL, err)
			}
			f.log(fmt.Sprintf("COPR repo %s enabled successfully: %s", pkg.RepoURL, string(output)))
			enabledRepos[pkg.RepoURL] = true

			// Special handling for niri COPR repo - set priority=1
			if pkg.RepoURL == "yalter/niri-git" {
				f.log("Setting priority=1 for niri-git COPR repo...")
				repoFile := coprRepoFile("yalter/niri-git")
				progressChan <- InstallProgressMsg{
					Phase:       PhaseSystemPackages,
					Progress:    0.22,
					Step:        "Setting niri COPR repo priority...",
					IsComplete:  false,
					NeedsSudo:   true,
					CommandInfo: fmt.Sprintf("echo \"priority=1\" | sudo tee -a %s", repoFile),
				}

				priorityCmd := privescExec(ctx, sudoPassword,
					fmt.Sprintf("bash -c 'echo \"priority=1\" | tee -a %s'", repoFile))
				priorityOutput, err := priorityCmd.CombinedOutput()
				if err != nil {
					f.logError("failed to set niri COPR repo priority", err)
					f.log(fmt.Sprintf("Priority command output: %s", string(priorityOutput)))
					return fmt.Errorf("failed to set niri COPR repo priority: %w", err)
				}
				f.log(fmt.Sprintf("niri COPR repo priority set successfully: %s", string(priorityOutput)))
			}
		}
	}

	return nil
}

func (f *FedoraDistribution) installDNFPackages(ctx context.Context, packages []string, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if len(packages) == 0 {
		return nil
	}

	f.log(fmt.Sprintf("Installing DNF packages: %s", strings.Join(packages, ", ")))

	return f.installDNFGroups(ctx, packages, sudoPassword, progressChan, PhaseSystemPackages, "Installing system packages...", 0.40, 0.60)
}

func (f *FedoraDistribution) installCOPRPackages(ctx context.Context, packages []string, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if len(packages) == 0 {
		return nil
	}

	f.log(fmt.Sprintf("Installing COPR packages: %s", strings.Join(packages, ", ")))

	return f.installDNFGroups(ctx, packages, sudoPassword, progressChan, PhaseAURPackages, "Installing COPR packages...", 0.70, 0.85)
}

func (f *FedoraDistribution) dnfInstallArgs(packages []string, minimal bool) []string {
	args := []string{"dnf", "install", "-y"}
	if minimal {
		args = append(args, "--setopt=install_weak_deps=False")
	}
	return append(args, packages...)
}

func (f *FedoraDistribution) installDNFGroups(ctx context.Context, packages []string, sudoPassword string, progressChan chan<- InstallProgressMsg, phase InstallPhase, step string, startProgress float64, endProgress float64) error {
	groups := orderedMinimalInstallGroups(packages)
	totalGroups := len(groups)

	groupIndex := 0
	installGroup := func(groupPackages []string, minimal bool) error {
		if len(groupPackages) == 0 {
			return nil
		}

		groupIndex++
		groupStart := startProgress
		groupEnd := endProgress
		if totalGroups > 1 {
			midpoint := startProgress + ((endProgress - startProgress) / 2)
			if groupIndex == 1 {
				groupEnd = midpoint
			} else {
				groupStart = midpoint
			}
		}

		args := f.dnfInstallArgs(groupPackages, minimal)
		progressChan <- InstallProgressMsg{
			Phase:       phase,
			Progress:    groupStart,
			Step:        step,
			IsComplete:  false,
			NeedsSudo:   true,
			CommandInfo: fmt.Sprintf("sudo %s", strings.Join(args, " ")),
		}

		cmd := privesc.ExecCommand(ctx, sudoPassword, strings.Join(args, " "))
		return f.runWithProgress(cmd, progressChan, phase, groupStart, groupEnd)
	}

	for _, group := range groups {
		if err := installGroup(group.packages, group.minimal); err != nil {
			return err
		}
	}
	return nil
}

// Image-based Fedora has rpm-ostree but no dnf, so the .repo file is fetched directly.
func (f *FedoraDistribution) coprRepoFileCommand(repo string) string {
	owner, project, _ := strings.Cut(repo, "/")
	chroot := "fedora-$(rpm -E %fedora)"
	if f.isEL() {
		chroot = "epel-$(rpm -E %rhel)"
	}
	return fmt.Sprintf("sudo curl -fsSLo %s https://copr.fedorainfracloud.org/coprs/%s/%s/repo/%s/%s-%s-%s.repo",
		coprRepoFile(repo), owner, project, chroot, owner, project, chroot)
}

// rpm-ostree status runs over D-Bus and the layer view rebuilds its commands on every render.
var rpmOstreeRequested = sync.OnceValue(func() []string {
	out, err := exec.Command("rpm-ostree", "status", "--json").Output()
	if err != nil {
		return nil
	}
	var status struct {
		Deployments []struct {
			Requested []string `json:"requested-packages"`
		} `json:"deployments"`
	}
	if json.Unmarshal(out, &status) != nil || len(status.Deployments) == 0 {
		return nil
	}
	return status.Deployments[0].Requested
})

func (f *FedoraDistribution) layeredRequests() map[string]bool {
	list := f.ostreeRequested
	if list == nil {
		list = rpmOstreeRequested
	}
	requested := map[string]bool{}
	for _, name := range list() {
		requested[name] = true
	}
	return requested
}

// layeredName is what --uninstall must name: the request, which may still be the pre-rename name
// even when its Provides already resolved to the renamed package.
func layeredName(requested map[string]bool, pkg string) string {
	if old, ok := renamedPackages[pkg]; ok && !requested[pkg] && requested[old] {
		return old
	}
	return pkg
}

// Shown to the user, never run. Terra-only packages have no rpm-ostree path.
func (f *FedoraDistribution) LayerCommands(dependencies []deps.Dependency, wm deps.WindowManager, reinstallFlags, disabledFlags map[string]bool) []string {
	var commands []string
	var uninstall []string
	skip := maps.Clone(disabledFlags)
	if skip == nil {
		skip = map[string]bool{}
	}
	requested := f.layeredRequests()
	// rpm-ostree refuses to install what is already layered, so a reinstall mark only means a variant switch.
	for _, dep := range dependencies {
		if !reinstallFlags[dep.Name] || skip[dep.Name] || dep.Status != deps.StatusInstalled {
			continue
		}
		swap, status := PlanVariantSwap(f, wm, dep.Name, dep.Variant)
		if status != SwapNeeded {
			skip[dep.Name] = true
			continue
		}
		uninstall = append(uninstall, layeredName(requested, swap.From.Name))
		if swap.From.Name == swap.To.Name && swap.From.Repository == RepoTypeCOPR {
			var files []string
			for _, repo := range coprAliases(swap.From.RepoURL) {
				files = append(files, coprRepoFile(repo))
			}
			commands = append(commands, "sudo rm -f "+strings.Join(files, " "))
		}
	}
	dnfPkgs, coprPkgs, manualPkgs, _ := f.categorizePackages(dependencies, wm, reinstallFlags, skip)

	seen := map[string]bool{}
	pkgs := append([]string{}, dnfPkgs...)
	for _, pkg := range coprPkgs {
		pkgs = append(pkgs, pkg.Name)
		if pkg.RepoURL == "" || seen[pkg.RepoURL] {
			continue
		}
		seen[pkg.RepoURL] = true
		commands = append(commands, f.coprRepoFileCommand(pkg.RepoURL))
		if pkg.RepoURL == "yalter/niri-git" {
			commands = append(commands, "echo priority=1 | sudo tee -a "+coprRepoFile("yalter/niri-git"))
		}
	}
	// A request keeps its old name forever and resolves by name before Provides, ignoring Obsoletes.
	for _, name := range slices.Sorted(maps.Keys(renamedPackages)) {
		old := renamedPackages[name]
		if !requested[old] || slices.Contains(uninstall, old) {
			continue
		}
		uninstall = append(uninstall, old)
		if !requested[name] && !slices.Contains(pkgs, name) {
			pkgs = append(pkgs, name)
		}
	}
	for _, dep := range dependencies {
		if dep.Status == deps.StatusNeedsUpdate && !disabledFlags[dep.Name] {
			commands = append(commands, "sudo rpm-ostree upgrade")
			break
		}
	}
	if len(pkgs) > 0 {
		install := "sudo rpm-ostree install " + strings.Join(pkgs, " ")
		if len(uninstall) > 0 {
			install += " --uninstall " + strings.Join(uninstall, " ")
		}
		commands = append(commands, install)
	}
	for _, name := range manualPkgs {
		commands = append(commands, fmt.Sprintf("# %s has no package for image-based Fedora", name))
	}
	return append(commands, "systemctl reboot")
}
