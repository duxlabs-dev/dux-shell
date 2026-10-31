package distros

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

func init() {
	Register("opensuse-tumbleweed", "#73BA25", FamilySUSE, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewOpenSUSEDistribution(config, logChan)
	})
	Register("opensuse-leap", "#73BA25", FamilySUSE, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewOpenSUSEDistribution(config, logChan)
	})
	Register("opensuse-slowroll", "#73BA25", FamilySUSE, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewOpenSUSEDistribution(config, logChan)
	})
}

type OpenSUSEDistribution struct {
	*BaseDistribution
	*ManualPackageInstaller
	config DistroConfig
}

const openSUSENiriWaylandServerPackage = "libwayland-server0"

func NewOpenSUSEDistribution(config DistroConfig, logChan chan<- string) *OpenSUSEDistribution {
	base := NewBaseDistribution(logChan)
	return &OpenSUSEDistribution{
		BaseDistribution:       base,
		ManualPackageInstaller: &ManualPackageInstaller{BaseDistribution: base},
		config:                 config,
	}
}

func (o *OpenSUSEDistribution) GetID() string {
	return o.config.ID
}

func (o *OpenSUSEDistribution) GetColorHex() string {
	return o.config.ColorHex
}

func (o *OpenSUSEDistribution) GetFamily() DistroFamily {
	return o.config.Family
}

func (o *OpenSUSEDistribution) GetPackageManager() PackageManagerType {
	return PackageManagerZypper
}

func (o *OpenSUSEDistribution) DetectDependencies(ctx context.Context, wm deps.WindowManager) ([]deps.Dependency, error) {
	return o.DetectDependenciesWithTerminal(ctx, wm, deps.TerminalGhostty)
}

func (o *OpenSUSEDistribution) DetectDependenciesWithTerminal(ctx context.Context, wm deps.WindowManager, terminal deps.Terminal) ([]deps.Dependency, error) {
	var dependencies []deps.Dependency

	// DMS at the top (shell is prominent)
	dependencies = append(dependencies, o.detectDMS())

	// Terminal with choice support
	dependencies = append(dependencies, o.detectSpecificTerminal(terminal))

	// Common detections using base methods
	dependencies = append(dependencies, o.detectGit())
	dependencies = append(dependencies, o.detectWindowManager(wm))
	dependencies = append(dependencies, o.detectQuickshell())
	dependencies = append(dependencies, o.detectGreeterPackage(o.packageInstalled))
	dependencies = append(dependencies, o.detectXDGPortal())
	dependencies = append(dependencies, o.detectAccountsService())

	// Hyprland-specific tools
	if wm == deps.WindowManagerHyprland {
		dependencies = append(dependencies, o.detectHyprlandTools()...)
		dependencies = append(dependencies, o.detectHyprlandGuiutils())
	}

	// Niri-specific tools
	if wm == deps.WindowManagerNiri {
		dependencies = append(dependencies, o.detectXwaylandSatellite())
	}

	dependencies = append(dependencies, o.detectMatugen())
	dependencies = append(dependencies, o.detectDanksearch())
	dependencies = append(dependencies, o.detectCalendarPackage(o.packageInstalled))

	return dependencies, nil
}

func (o *OpenSUSEDistribution) detectXDGPortal() deps.Dependency {
	return o.detectPackage("xdg-desktop-portal-gtk", "Desktop integration portal for GTK", o.packageInstalled("xdg-desktop-portal-gtk"))
}

func (o *OpenSUSEDistribution) packageInstalled(pkg string) bool {
	cmd := exec.Command("rpm", "-q", pkg)
	err := cmd.Run()
	return err == nil
}

func (o *OpenSUSEDistribution) InstalledVariant(stable, git PackageMapping) (deps.PackageVariant, bool) {
	return installedVariantByName(o.packageInstalled, stable, git)
}

func (o *OpenSUSEDistribution) SwapVariants(ctx context.Context, swaps []VariantSwap, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if err := o.enableOBSRepos(ctx, swapTargets(swaps, RepoTypeOBS), sudoPassword, progressChan); err != nil {
		return err
	}

	args := []string{"zypper", "install", "-y"}
	for _, swap := range swaps {
		args = append(args, swap.To.Name, "'!"+swap.From.Name+"'")
	}
	command := strings.Join(args, " ")

	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.40,
		Step:        "Switching package variants...",
		NeedsSudo:   true,
		CommandInfo: "sudo " + command,
	}
	return o.runWithProgress(privesc.ExecCommand(ctx, sudoPassword, command), progressChan, PhaseSystemPackages, 0.40, 0.85)
}

func (o *OpenSUSEDistribution) RepoMoves() []RepoMove {
	return obsZypperChannel.moves(repoPathExists)
}

func (o *OpenSUSEDistribution) ApplyRepoMoves(ctx context.Context, moves []RepoMove, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	adds := repoMoveAdds(moves)
	if err := o.enableOBSRepos(ctx, adds, sudoPassword, progressChan); err != nil {
		return err
	}
	if command := zypperVendorSwitch(moves, parseRPMDistributions(rpmQueryDistributions())); command != "" {
		if len(adds) == 0 {
			if err := o.runWithProgress(privescExec(ctx, sudoPassword, zypperKeyRefresh), progressChan, PhaseSystemPackages, 0.26, 0.28); err != nil {
				return fmt.Errorf("failed to refresh the new repositories: %w", err)
			}
		}
		progressChan <- InstallProgressMsg{
			Phase:       PhaseSystemPackages,
			Progress:    0.28,
			Step:        "Switching installed packages to the new repositories...",
			NeedsSudo:   true,
			CommandInfo: "sudo " + command,
		}
		// Runs before the legacy repos go, so a failed switch is retried on the next run.
		if err := o.runWithProgress(privescExec(ctx, sudoPassword, command), progressChan, PhaseSystemPackages, 0.28, 0.30); err != nil {
			return fmt.Errorf("failed to switch packages to the new repositories: %w", err)
		}
	}
	for _, move := range repoMoveRemoves(moves) {
		command := "zypper removerepo " + obsZypperAlias(move.Old)
		progressChan <- InstallProgressMsg{
			Phase:       PhaseSystemPackages,
			Progress:    0.30,
			Step:        fmt.Sprintf("Removing OBS repo %s...", move.Old),
			NeedsSudo:   true,
			CommandInfo: "sudo " + command,
		}
		if err := o.runWithProgress(privescExec(ctx, sudoPassword, command), progressChan, PhaseSystemPackages, 0.30, 0.35); err != nil {
			return fmt.Errorf("failed to remove OBS repo %s: %w", move.Old, err)
		}
	}
	return nil
}

func (o *OpenSUSEDistribution) RepoMoveCommands(moves []RepoMove) []string {
	osInfo, err := GetOSInfo()
	if err != nil {
		osInfo = &OSInfo{}
	}
	return opensuseRepoMoveCommands(moves, opensuseOBSDist(osInfo), parseRPMDistributions(rpmQueryDistributions()))
}

func opensuseRepoMoveCommands(moves []RepoMove, dist string, installed []rpmPackage) []string {
	var commands []string
	adds := repoMoveAdds(moves)
	for _, add := range adds {
		commands = append(commands, "sudo zypper addrepo -f "+obsZypperRepoURL(add.RepoURL, dist))
	}
	switchCommand := zypperVendorSwitch(moves, installed)
	// Repos added by hand may never have had their signing key accepted.
	if len(adds) > 0 || switchCommand != "" {
		commands = append(commands, "sudo "+zypperKeyRefresh)
	}
	if switchCommand != "" {
		commands = append(commands, "sudo "+switchCommand)
	}
	for _, move := range repoMoveRemoves(moves) {
		commands = append(commands, "sudo zypper removerepo "+obsZypperAlias(move.Old))
	}
	return commands
}

const zypperKeyRefresh = "zypper --gpg-auto-import-keys refresh"

type rpmPackage struct {
	name, version, project string
}

// OBS stamps Distribution "<project> / <repository>", which outlives the repo being removed.
func rpmQueryDistributions() string {
	out, _ := exec.Command("rpm", "-qa", "--qf", `%{NAME}\t%{VERSION}\t%{DISTRIBUTION}\n`).Output()
	return string(out)
}

func parseRPMDistributions(out string) []rpmPackage {
	var packages []rpmPackage
	for line := range strings.Lines(out) {
		fields := strings.Split(strings.TrimRight(line, "\n"), "\t")
		if len(fields) != 3 {
			continue
		}
		project, _, _ := strings.Cut(fields[2], " / ")
		packages = append(packages, rpmPackage{fields[0], fields[1], strings.TrimSpace(project)})
	}
	return packages
}

// zypper keeps packages on their vendor, so whatever a legacy project built is reinstalled from the new one.
// OBS restarts the release counter in a new project, so compare Version only.
func zypperVendorSwitch(moves []RepoMove, installed []rpmPackage) string {
	var froms, capabilities []string
	for _, move := range moves {
		if !move.newEnabled() {
			continue
		}
		from := "--from " + obsZypperAlias(move.New)
		for _, pkg := range installed {
			if pkg.project != move.Old {
				continue
			}
			name := pkg.name
			if renamed, ok := renamedTo(name); ok {
				name = renamed
			}
			capabilities = append(capabilities, fmt.Sprintf("'%s>=%s'", name, pkg.version))
			if !slices.Contains(froms, from) {
				froms = append(froms, from)
			}
		}
	}
	if len(capabilities) == 0 {
		return ""
	}
	return "zypper --non-interactive install --oldpackage --allow-vendor-change " + strings.Join(froms, " ") + " " + strings.Join(capabilities, " ")
}

func opensuseOBSDist(osInfo *OSInfo) string {
	switch osInfo.Distribution.ID {
	case "opensuse-leap":
		// The projects name their Leap repositories by bare version, e.g. 16.0.
		return osInfo.VersionID
	case "opensuse-slowroll":
		return "openSUSE_Slowroll"
	}
	return "openSUSE_Tumbleweed"
}

func obsZypperRepoURL(repo, dist string) string {
	return obsBaseURL(repo, dist) + "/" + repo + ".repo"
}

func (o *OpenSUSEDistribution) GetPackageMapping(wm deps.WindowManager) map[string]PackageMapping {
	return o.GetPackageMappingWithVariants(wm, make(map[string]deps.PackageVariant))
}

func (o *OpenSUSEDistribution) GetPackageMappingWithVariants(wm deps.WindowManager, variants map[string]deps.PackageVariant) map[string]PackageMapping {
	packages := map[string]PackageMapping{
		// Standard zypper packages
		"git":                    {Name: "git", Repository: RepoTypeSystem},
		"kitty":                  {Name: "kitty", Repository: RepoTypeSystem},
		"alacritty":              {Name: "alacritty", Repository: RepoTypeSystem},
		"xdg-desktop-portal-gtk": {Name: "xdg-desktop-portal-gtk", Repository: RepoTypeSystem},
		"accountsservice":        {Name: "accountsservice", Repository: RepoTypeSystem},

		// DMS packages from OBS
		"dms (Dux Shell)": o.getDmsMapping(variants["dms (Dux Shell)"]),
		"quickshell":      o.getQuickshellMapping(variants["quickshell"]),
		"dms-greeter":     variantMapping("dux-greeter", variants["dms-greeter"], RepoTypeOBS, obsDeps),
		"ghostty":         {Name: "ghostty", Repository: RepoTypeOBS, RepoURL: obsDeps},
		"matugen":         {Name: "matugen", Repository: RepoTypeOBS, RepoURL: obsDeps},
		"danksearch":      {Name: "dux-search", Repository: RepoTypeOBS, RepoURL: obsDeps},
		"dankcalendar":    variantMapping("dux-calendar", variants["dankcalendar"], RepoTypeOBS, obsDeps),
	}

	switch wm {
	case deps.WindowManagerHyprland:
		packages["hyprland"] = PackageMapping{Name: "hyprland", Repository: RepoTypeSystem}
		packages["hyprctl"] = PackageMapping{Name: "hyprland", Repository: RepoTypeSystem}
		packages["jq"] = PackageMapping{Name: "jq", Repository: RepoTypeSystem}
		packages["hyprland-guiutils"] = PackageMapping{Name: "hyprland-guiutils", Repository: RepoTypeSystem}
	case deps.WindowManagerNiri:
		// Niri stable has native package support on openSUSE
		niriVariant := variants["niri"]
		packages["niri"] = o.getNiriMapping(niriVariant)
		packages["xwayland-satellite"] = o.getXwaylandSatelliteMapping(niriVariant)
	}

	return packages
}

func (o *OpenSUSEDistribution) getDmsMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "dms-git", Repository: RepoTypeOBS, RepoURL: obsDMSGit}
	}
	return PackageMapping{Name: "dms", Repository: RepoTypeOBS, RepoURL: obsDMS}
}

func (o *OpenSUSEDistribution) getQuickshellMapping(variant deps.PackageVariant) PackageMapping {
	if forceQuickshellGit || variant == deps.VariantGit {
		return PackageMapping{Name: "quickshell-git", Repository: RepoTypeOBS, RepoURL: obsDeps}
	}
	return PackageMapping{Name: "quickshell", Repository: RepoTypeOBS, RepoURL: obsDeps}
}

func (o *OpenSUSEDistribution) getNiriMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "niri-git", Repository: RepoTypeOBS, RepoURL: obsDeps}
	}
	return PackageMapping{Name: "niri", Repository: RepoTypeSystem}
}

func (o *OpenSUSEDistribution) getXwaylandSatelliteMapping(variant deps.PackageVariant) PackageMapping {
	if variant == deps.VariantGit {
		return PackageMapping{Name: "xwayland-satellite-git", Repository: RepoTypeOBS, RepoURL: obsDeps}
	}
	return PackageMapping{Name: "xwayland-satellite", Repository: RepoTypeSystem}
}

func (o *OpenSUSEDistribution) detectXwaylandSatellite() deps.Dependency {
	status := deps.StatusMissing
	if o.commandExists("xwayland-satellite") {
		status = deps.StatusInstalled
	}

	return deps.Dependency{
		Name:        "xwayland-satellite",
		Status:      status,
		Description: "Xwayland support",
		Required:    true,
	}
}

func (o *OpenSUSEDistribution) detectAccountsService() deps.Dependency {
	status := deps.StatusMissing
	if o.packageInstalled("accountsservice") {
		status = deps.StatusInstalled
	}

	return deps.Dependency{
		Name:        "accountsservice",
		Status:      status,
		Description: "D-Bus interface for user account query and manipulation",
		Required:    true,
	}
}

func (o *OpenSUSEDistribution) getPrerequisites() []string {
	return []string{}
}

func (o *OpenSUSEDistribution) InstallPrerequisites(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	prerequisites := o.getPrerequisites()
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
		o.log("go not found in PATH, will install go")
		missingPkgs = append(missingPkgs, "go")
	} else {
		o.log("go already available in PATH")
	}

	if len(missingPkgs) == 0 {
		o.log("All prerequisites already installed")
		return nil
	}

	o.log(fmt.Sprintf("Installing prerequisites: %s", strings.Join(missingPkgs, ", ")))
	progressChan <- InstallProgressMsg{
		Phase:       PhasePrerequisites,
		Progress:    0.08,
		Step:        fmt.Sprintf("Installing %d prerequisites...", len(missingPkgs)),
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: fmt.Sprintf("sudo zypper install -y %s", strings.Join(missingPkgs, " ")),
		LogOutput:   fmt.Sprintf("Installing prerequisites: %s", strings.Join(missingPkgs, ", ")),
	}

	args := []string{"zypper", "install", "-y"}
	args = append(args, missingPkgs...)
	cmd := privesc.ExecCommand(ctx, sudoPassword, strings.Join(args, " "))
	output, err := cmd.CombinedOutput()
	if err != nil {
		o.logError("failed to install prerequisites", err)
		o.log(fmt.Sprintf("Prerequisites command output: %s", string(output)))
		return fmt.Errorf("failed to install prerequisites: %w", err)
	}
	o.log(fmt.Sprintf("Prerequisites install output: %s", string(output)))

	return nil
}

func (o *OpenSUSEDistribution) InstallPackages(ctx context.Context, dependencies []deps.Dependency, wm deps.WindowManager, sudoPassword string, reinstallFlags map[string]bool, disabledFlags map[string]bool, skipGlobalUseFlags bool, progressChan chan<- InstallProgressMsg) error {
	// Phase 1: Check Prerequisites
	progressChan <- InstallProgressMsg{
		Phase:      PhasePrerequisites,
		Progress:   0.05,
		Step:       "Checking system prerequisites...",
		IsComplete: false,
		LogOutput:  "Starting prerequisite check...",
	}

	if err := o.disableInstallMediaRepos(ctx, sudoPassword, progressChan); err != nil {
		return fmt.Errorf("failed to disable install media repositories: %w", err)
	}

	if err := o.InstallPrerequisites(ctx, sudoPassword, progressChan); err != nil {
		return fmt.Errorf("failed to install prerequisites: %w", err)
	}

	skipFlags, err := swapReinstalledVariants(ctx, o, dependencies, wm, reinstallFlags, disabledFlags, sudoPassword, progressChan)
	if err != nil {
		return err
	}

	systemPkgs, obsPkgs, manualPkgs, variantMap := o.categorizePackages(dependencies, wm, reinstallFlags, skipFlags)

	// Enable OBS repositories
	if len(obsPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.15,
			Step:       "Enabling OBS repositories...",
			IsComplete: false,
			LogOutput:  "Setting up OBS repositories for additional packages",
		}
		if err := o.enableOBSRepos(ctx, obsPkgs, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to enable OBS repositories: %w", err)
		}
	}

	// Phase 3: System Packages (Zypper)
	if len(systemPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.35,
			Step:       fmt.Sprintf("Installing %d system packages...", len(systemPkgs)),
			IsComplete: false,
			NeedsSudo:  true,
			LogOutput:  fmt.Sprintf("Installing system packages: %s", strings.Join(systemPkgs, ", ")),
		}
		if err := o.installZypperPackages(ctx, systemPkgs, sudoPassword, progressChan, PhaseSystemPackages, "Installing system packages...", 0.40, 0.60); err != nil {
			return fmt.Errorf("failed to install zypper packages: %w", err)
		}
	}

	// OBS Packages
	obsPkgNames := o.extractPackageNames(obsPkgs)
	if len(obsPkgNames) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseAURPackages,
			Progress:   0.65,
			Step:       fmt.Sprintf("Installing %d OBS packages...", len(obsPkgNames)),
			IsComplete: false,
			LogOutput:  fmt.Sprintf("Installing OBS packages: %s", strings.Join(obsPkgNames, ", ")),
		}
		if err := o.installZypperPackages(ctx, obsPkgNames, sudoPassword, progressChan, PhaseAURPackages, "Installing OBS packages...", 0.70, 0.85); err != nil {
			return fmt.Errorf("failed to install OBS packages: %w", err)
		}
	}

	// Manual Builds
	if len(manualPkgs) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:      PhaseSystemPackages,
			Progress:   0.85,
			Step:       fmt.Sprintf("Building %d packages from source...", len(manualPkgs)),
			IsComplete: false,
			LogOutput:  fmt.Sprintf("Building from source: %s", strings.Join(manualPkgs, ", ")),
		}
		if err := o.InstallManualPackages(ctx, manualPkgs, variantMap, sudoPassword, progressChan); err != nil {
			return fmt.Errorf("failed to install manual packages: %w", err)
		}
	}

	// Configuration
	progressChan <- InstallProgressMsg{
		Phase:      PhaseConfiguration,
		Progress:   0.90,
		Step:       "Configuring system...",
		IsComplete: false,
		LogOutput:  "Starting post-installation configuration...",
	}

	terminal := o.DetectTerminalFromDeps(dependencies)
	if err := o.WriteEnvironmentConfig(terminal); err != nil {
		o.log(fmt.Sprintf("Warning: failed to write environment config: %v", err))
	}

	if err := o.WriteWindowManagerConfig(wm); err != nil {
		o.log(fmt.Sprintf("Warning: failed to write window manager config: %v", err))
	}

	if err := o.EnableDMSService(ctx, wm); err != nil {
		o.log(fmt.Sprintf("Warning: failed to enable dms service: %v", err))
	}

	// Complete
	progressChan <- InstallProgressMsg{
		Phase:      PhaseComplete,
		Progress:   1.0,
		Step:       "Installation complete!",
		IsComplete: true,
		LogOutput:  "All packages installed and configured successfully",
	}

	return nil
}

func (o *OpenSUSEDistribution) categorizePackages(dependencies []deps.Dependency, wm deps.WindowManager, reinstallFlags map[string]bool, disabledFlags map[string]bool) ([]string, []PackageMapping, []string, map[string]deps.PackageVariant) {
	systemPkgs := []string{}
	obsPkgs := []PackageMapping{}
	manualPkgs := []string{}

	variantMap := make(map[string]deps.PackageVariant)
	for _, dep := range dependencies {
		variantMap[dep.Name] = dep.Variant
	}

	packageMap := o.GetPackageMappingWithVariants(wm, variantMap)

	for _, dep := range dependencies {
		if disabledFlags[dep.Name] {
			continue
		}

		if dep.Status == deps.StatusInstalled && !reinstallFlags[dep.Name] {
			continue
		}

		pkgInfo, exists := packageMap[dep.Name]
		if !exists {
			o.log(fmt.Sprintf("Warning: No package mapping for %s", dep.Name))
			continue
		}

		switch pkgInfo.Repository {
		case RepoTypeSystem:
			systemPkgs = append(systemPkgs, pkgInfo.Name)
		case RepoTypeOBS:
			obsPkgs = append(obsPkgs, pkgInfo)
		case RepoTypeManual:
			manualPkgs = append(manualPkgs, dep.Name)
		}
	}

	systemPkgs = o.appendMissingSystemPackages(systemPkgs, openSUSENiriRuntimePackages(wm, disabledFlags))

	return systemPkgs, obsPkgs, manualPkgs, variantMap
}

func openSUSENiriRuntimePackages(wm deps.WindowManager, disabledFlags map[string]bool) []string {
	if wm != deps.WindowManagerNiri || disabledFlags["niri"] {
		return nil
	}

	return []string{openSUSENiriWaylandServerPackage}
}

func (o *OpenSUSEDistribution) appendMissingSystemPackages(systemPkgs []string, extraPkgs []string) []string {
	for _, pkg := range extraPkgs {
		if slices.Contains(systemPkgs, pkg) || o.packageInstalled(pkg) {
			continue
		}

		o.log(fmt.Sprintf("Adding openSUSE runtime package: %s", pkg))
		systemPkgs = append(systemPkgs, pkg)
	}

	return systemPkgs
}

func (o *OpenSUSEDistribution) extractPackageNames(packages []PackageMapping) []string {
	names := make([]string, len(packages))
	for i, pkg := range packages {
		names[i] = pkg.Name
	}
	return names
}

func (o *OpenSUSEDistribution) enableOBSRepos(ctx context.Context, obsPkgs []PackageMapping, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	enabledRepos := make(map[string]bool)

	osInfo, err := GetOSInfo()
	if err != nil {
		return fmt.Errorf("failed to get OS info: %w", err)
	}

	obsDistroVersion := opensuseOBSDist(osInfo)

	for _, pkg := range obsPkgs {
		if pkg.RepoURL != "" && !enabledRepos[pkg.RepoURL] {
			o.log(fmt.Sprintf("Enabling OBS repository: %s", pkg.RepoURL))

			repoURL := obsZypperRepoURL(pkg.RepoURL, obsDistroVersion)

			// zypper stores the repo under the alias from the .repo section header, home_<owner>_<project>.
			if repoPathExists(obsZypperRepoFile(pkg.RepoURL)) {
				o.log(fmt.Sprintf("OBS repo %s already exists, skipping", pkg.RepoURL))
				enabledRepos[pkg.RepoURL] = true
				continue
			}

			progressChan <- InstallProgressMsg{
				Phase:       PhaseSystemPackages,
				Progress:    0.20,
				Step:        fmt.Sprintf("Enabling OBS repo %s...", pkg.RepoURL),
				NeedsSudo:   true,
				CommandInfo: fmt.Sprintf("sudo zypper addrepo %s", repoURL),
			}

			cmd := privesc.ExecCommand(ctx, sudoPassword,
				fmt.Sprintf("zypper addrepo -f %s", repoURL))
			if err := o.runWithProgress(cmd, progressChan, PhaseSystemPackages, 0.20, 0.22); err != nil {
				o.log(fmt.Sprintf("OBS repo %s add failed (may already exist): %v", pkg.RepoURL, err))
			}

			enabledRepos[pkg.RepoURL] = true
			o.log(fmt.Sprintf("OBS repo %s enabled successfully", pkg.RepoURL))
		}
	}

	// Refresh repositories with GPG auto-import
	if len(enabledRepos) > 0 {
		progressChan <- InstallProgressMsg{
			Phase:       PhaseSystemPackages,
			Progress:    0.25,
			Step:        "Refreshing repositories...",
			NeedsSudo:   true,
			CommandInfo: "sudo zypper --gpg-auto-import-keys refresh",
		}

		refreshCmd := privesc.ExecCommand(ctx, sudoPassword, "zypper --gpg-auto-import-keys refresh")
		if err := o.runWithProgress(refreshCmd, progressChan, PhaseSystemPackages, 0.25, 0.27); err != nil {
			return fmt.Errorf("failed to refresh repositories: %w", err)
		}
	}

	return nil
}

func isOpenSUSEInstallMediaURI(uri string) bool {
	normalizedURI := strings.ToLower(strings.TrimSpace(uri))

	return strings.HasPrefix(normalizedURI, "cd:/") ||
		strings.HasPrefix(normalizedURI, "dvd:/") ||
		strings.HasPrefix(normalizedURI, "hd:/") ||
		strings.HasPrefix(normalizedURI, "iso:/")
}

func parseZypperInstallMediaAliases(output string) []string {
	var aliases []string

	for line := range strings.SplitSeq(output, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || !strings.Contains(line, "|") {
			continue
		}

		parts := strings.Split(line, "|")
		if len(parts) < 7 {
			continue
		}

		for i := range parts {
			parts[i] = strings.TrimSpace(parts[i])
		}

		alias := parts[1]
		enabled := strings.ToLower(parts[3])
		uri := parts[len(parts)-1]

		if alias == "" || strings.EqualFold(alias, "alias") {
			continue
		}
		if enabled != "" && enabled != "yes" {
			continue
		}
		if !isOpenSUSEInstallMediaURI(uri) {
			continue
		}

		aliases = append(aliases, alias)
	}

	return aliases
}

func (o *OpenSUSEDistribution) disableInstallMediaRepos(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	listCmd := exec.CommandContext(ctx, "zypper", "repos", "-u")
	output, err := listCmd.CombinedOutput()
	if err != nil {
		o.log(fmt.Sprintf("Warning: failed to list zypper repositories: %s", strings.TrimSpace(string(output))))
		return fmt.Errorf("failed to list zypper repositories: %w", err)
	}

	aliases := parseZypperInstallMediaAliases(string(output))
	if len(aliases) == 0 {
		return nil
	}

	o.log(fmt.Sprintf("Disabling install media repositories: %s", strings.Join(aliases, ", ")))
	progressChan <- InstallProgressMsg{
		Phase:       PhasePrerequisites,
		Progress:    0.055,
		Step:        "Disabling install media repositories...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: fmt.Sprintf("sudo zypper modifyrepo -d %s", strings.Join(aliases, " ")),
		LogOutput:   fmt.Sprintf("Disabling install media repositories: %s", strings.Join(aliases, ", ")),
	}

	for _, alias := range aliases {
		cmd := privesc.ExecCommand(ctx, sudoPassword, fmt.Sprintf("zypper modifyrepo -d '%s'", privesc.EscapeSingleQuotes(alias)))
		repoOutput, err := cmd.CombinedOutput()
		if err != nil {
			o.log(fmt.Sprintf("Failed to disable install media repo %s: %s", alias, strings.TrimSpace(string(repoOutput))))
			return fmt.Errorf("failed to disable install media repo %s: %w", alias, err)
		}
		o.log(fmt.Sprintf("Disabled install media repo %s: %s", alias, strings.TrimSpace(string(repoOutput))))
	}

	return nil
}

func (o *OpenSUSEDistribution) zypperInstallArgs(packages []string, minimal bool) []string {
	args := []string{"zypper", "install", "-y"}
	if minimal {
		args = append(args, "--no-recommends")
	}
	return append(args, packages...)
}

func (o *OpenSUSEDistribution) installZypperPackages(ctx context.Context, packages []string, sudoPassword string, progressChan chan<- InstallProgressMsg, phase InstallPhase, step string, startProgress float64, endProgress float64) error {
	if len(packages) == 0 {
		return nil
	}

	o.log(fmt.Sprintf("Installing zypper packages: %s", strings.Join(packages, ", ")))

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

		args := o.zypperInstallArgs(groupPackages, minimal)
		progressChan <- InstallProgressMsg{
			Phase:       phase,
			Progress:    groupStart,
			Step:        step,
			IsComplete:  false,
			NeedsSudo:   true,
			CommandInfo: fmt.Sprintf("sudo %s", strings.Join(args, " ")),
		}

		cmd := privesc.ExecCommand(ctx, sudoPassword, strings.Join(args, " "))
		return o.runWithProgress(cmd, progressChan, phase, groupStart, groupEnd)
	}

	for _, group := range groups {
		if err := installGroup(group.packages, group.minimal); err != nil {
			return err
		}
	}
	return nil
}

func (o *OpenSUSEDistribution) installQuickshell(ctx context.Context, variant deps.PackageVariant, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	o.log("Installing quickshell from source (with openSUSE-specific build flags)...")

	homeDir := os.Getenv("HOME")
	if homeDir == "" {
		return fmt.Errorf("HOME environment variable not set")
	}

	cacheDir := filepath.Join(homeDir, ".cache", "duxinstall")
	if err := os.MkdirAll(cacheDir, 0o755); err != nil {
		return fmt.Errorf("failed to create cache directory: %w", err)
	}

	tmpDir := filepath.Join(cacheDir, "quickshell-build")
	if err := os.MkdirAll(tmpDir, 0o755); err != nil {
		return fmt.Errorf("failed to create temp directory: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.1,
		Step:        "Cloning quickshell repository...",
		IsComplete:  false,
		CommandInfo: "git clone https://github.com/quickshell-mirror/quickshell.git",
	}

	var cloneCmd *exec.Cmd
	if forceQuickshellGit || variant == deps.VariantGit {
		cloneCmd = exec.CommandContext(ctx, "git", "clone", "https://github.com/quickshell-mirror/quickshell.git", tmpDir)
	} else {
		latestTag := o.getLatestQuickshellTag(ctx)
		if latestTag != "" {
			o.log(fmt.Sprintf("Using latest quickshell tag: %s", latestTag))
			cloneCmd = exec.CommandContext(ctx, "git", "clone", "--branch", latestTag, "https://github.com/quickshell-mirror/quickshell.git", tmpDir)
		} else {
			o.log("Warning: failed to fetch latest tag, using default branch")
			cloneCmd = exec.CommandContext(ctx, "git", "clone", "https://github.com/quickshell-mirror/quickshell.git", tmpDir)
		}
	}
	if err := cloneCmd.Run(); err != nil {
		return fmt.Errorf("failed to clone quickshell: %w", err)
	}

	buildDir := tmpDir + "/build"
	if err := os.MkdirAll(buildDir, 0o755); err != nil {
		return fmt.Errorf("failed to create build directory: %w", err)
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.3,
		Step:        "Configuring quickshell build (with openSUSE flags)...",
		IsComplete:  false,
		CommandInfo: "cmake -B build -S . -G Ninja",
	}

	// Get optflags from rpm
	optflagsCmd := exec.CommandContext(ctx, "rpm", "--eval", "%{optflags}")
	optflagsOutput, err := optflagsCmd.Output()
	optflags := strings.TrimSpace(string(optflagsOutput))
	if err != nil || optflags == "" {
		o.log("Warning: Could not get optflags from rpm, using default -O2 -g")
		optflags = "-O2 -g"
	}

	// Set openSUSE-specific CFLAGS
	customCFLAGS := fmt.Sprintf("%s -I/usr/include/wayland", optflags)

	configureCmd := exec.CommandContext(ctx, "cmake", "-GNinja", "-B", "build",
		"-DCMAKE_BUILD_TYPE=RelWithDebInfo",
		"-DCRASH_REPORTER=off",
		"-DCMAKE_CXX_STANDARD=20")
	configureCmd.Dir = tmpDir
	configureCmd.Env = append(os.Environ(),
		"TMPDIR="+cacheDir,
		"CFLAGS="+customCFLAGS,
		"CXXFLAGS="+customCFLAGS)

	o.log(fmt.Sprintf("Using CFLAGS: %s", customCFLAGS))

	output, err := configureCmd.CombinedOutput()
	if err != nil {
		o.log(fmt.Sprintf("cmake configure failed. Output:\n%s", string(output)))
		return fmt.Errorf("failed to configure quickshell: %w\nCMake output:\n%s", err, string(output))
	}

	o.log(fmt.Sprintf("cmake configure successful. Output:\n%s", string(output)))

	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.4,
		Step:        "Building quickshell (this may take a while)...",
		IsComplete:  false,
		CommandInfo: "cmake --build build",
	}

	buildCmd := exec.CommandContext(ctx, "cmake", "--build", "build")
	buildCmd.Dir = tmpDir
	buildCmd.Env = append(os.Environ(),
		"TMPDIR="+cacheDir,
		"CFLAGS="+customCFLAGS,
		"CXXFLAGS="+customCFLAGS)
	if err := o.runWithProgressStep(buildCmd, progressChan, PhaseSystemPackages, 0.4, 0.8, "Building quickshell..."); err != nil {
		return fmt.Errorf("failed to build quickshell: %w", err)
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.8,
		Step:        "Installing quickshell...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: "sudo cmake --install build",
	}

	installCmd := privesc.ExecCommand(ctx, sudoPassword, "cmake --install build")
	installCmd.Dir = tmpDir
	if err := installCmd.Run(); err != nil {
		return fmt.Errorf("failed to install quickshell: %w", err)
	}

	o.log("quickshell installed successfully from source")
	return nil
}

func (o *OpenSUSEDistribution) installRust(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if o.commandExists("cargo") {
		return nil
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.82,
		Step:        "Installing rustup...",
		IsComplete:  false,
		NeedsSudo:   true,
		CommandInfo: "sudo zypper install rustup",
	}

	rustupInstallCmd := privesc.ExecCommand(ctx, sudoPassword, "zypper install -y rustup")
	if err := o.runWithProgress(rustupInstallCmd, progressChan, PhaseSystemPackages, 0.82, 0.83); err != nil {
		return fmt.Errorf("failed to install rustup: %w", err)
	}

	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.83,
		Step:        "Installing stable Rust toolchain...",
		IsComplete:  false,
		CommandInfo: "rustup install stable",
	}

	rustInstallCmd := exec.CommandContext(ctx, "bash", "-c", "rustup install stable && rustup default stable")
	if err := o.runWithProgress(rustInstallCmd, progressChan, PhaseSystemPackages, 0.83, 0.84); err != nil {
		return fmt.Errorf("failed to install Rust toolchain: %w", err)
	}

	if !o.commandExists("cargo") {
		o.log("Warning: cargo not found in PATH after Rust installation, trying to source environment")
	}

	return nil
}

func (o *OpenSUSEDistribution) InstallManualPackages(ctx context.Context, packages []string, variantMap map[string]deps.PackageVariant, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	if len(packages) == 0 {
		return nil
	}

	o.log(fmt.Sprintf("Installing manual packages: %s", strings.Join(packages, ", ")))

	for _, pkg := range packages {
		if pkg == "matugen" {
			if err := o.installRust(ctx, sudoPassword, progressChan); err != nil {
				return fmt.Errorf("failed to install Rust: %w", err)
			}
			break
		}
	}

	for _, pkg := range packages {
		variant := variantMap[pkg]
		if pkg == "quickshell" {
			if err := o.installQuickshell(ctx, variant, sudoPassword, progressChan); err != nil {
				return fmt.Errorf("failed to install quickshell: %w", err)
			}
		} else {
			if err := o.ManualPackageInstaller.InstallManualPackages(ctx, []string{pkg}, variantMap, sudoPassword, progressChan); err != nil {
				return fmt.Errorf("failed to install %s: %w", pkg, err)
			}
		}
	}

	return nil
}
