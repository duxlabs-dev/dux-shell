package distros

import (
	"context"
	"fmt"
	"maps"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

// VariantSwap replaces the installed variant of a dependency with its other variant.
type VariantSwap struct {
	Dep  string
	From PackageMapping
	To   PackageMapping
}

// VariantSwapper is implemented by distros that can replace an installed package with its other variant.
type VariantSwapper interface {
	InstalledVariant(stable, git PackageMapping) (deps.PackageVariant, bool)
	SwapVariants(ctx context.Context, swaps []VariantSwap, sudoPassword string, progressChan chan<- InstallProgressMsg) error
	packageInstalled(pkg string) bool
}

type SwapStatus int

const (
	SwapNeeded SwapStatus = iota
	SwapAlreadyOnTarget
	SwapNotInstalled
	SwapNoVariant
	SwapUnsupported
)

func PlanVariantSwap(d Distribution, wm deps.WindowManager, dep string, target deps.PackageVariant) (VariantSwap, SwapStatus) {
	swapper, ok := d.(VariantSwapper)
	if !ok {
		return VariantSwap{}, SwapUnsupported
	}
	stable, ok := d.GetPackageMappingWithVariants(wm, map[string]deps.PackageVariant{dep: deps.VariantStable})[dep]
	if !ok {
		return VariantSwap{}, SwapNoVariant
	}
	git := d.GetPackageMappingWithVariants(wm, map[string]deps.PackageVariant{dep: deps.VariantGit})[dep]
	if stable == git {
		return VariantSwap{}, SwapNoVariant
	}

	current, installed := swapper.InstalledVariant(stable, git)
	switch {
	case !installed:
		return VariantSwap{}, SwapNotInstalled
	case current == target:
		return VariantSwap{}, SwapAlreadyOnTarget
	case target == deps.VariantGit:
		return VariantSwap{Dep: dep, From: installedAs(swapper, stable), To: git}, SwapNeeded
	default:
		return VariantSwap{Dep: dep, From: installedAs(swapper, git), To: stable}, SwapNeeded
	}
}

// installedAs names the package the remove step must target, which is the old name on hosts not yet upgraded past a rename.
func installedAs(swapper VariantSwapper, m PackageMapping) PackageMapping {
	if name, ok := installedName(swapper.packageInstalled, m.Name); ok {
		m.Name = name
	}
	return m
}

// installedVariantByName works when the two variants ship under different package names.
func installedVariantByName(installed func(string) bool, stable, git PackageMapping) (deps.PackageVariant, bool) {
	if _, ok := installedName(installed, packageBaseName(git.Name)); ok {
		return deps.VariantGit, true
	}
	if _, ok := installedName(installed, packageBaseName(stable.Name)); ok {
		return deps.VariantStable, true
	}
	return deps.VariantStable, false
}

// packageBaseName drops an apt target release suffix such as "quickshell/trixie-backports".
func packageBaseName(name string) string {
	base, _, _ := strings.Cut(name, "/")
	return base
}

// swapReinstalledVariants swaps reinstall-marked deps whose other variant is installed, since the
// package managers refuse to install over it. The returned flags keep them out of the install pass.
func swapReinstalledVariants(ctx context.Context, d Distribution, dependencies []deps.Dependency, wm deps.WindowManager, reinstallFlags, disabledFlags map[string]bool, sudoPassword string, progressChan chan<- InstallProgressMsg) (map[string]bool, error) {
	var swaps []VariantSwap
	for _, dep := range dependencies {
		if !reinstallFlags[dep.Name] || disabledFlags[dep.Name] {
			continue
		}
		if swap, status := PlanVariantSwap(d, wm, dep.Name, dep.Variant); status == SwapNeeded {
			swaps = append(swaps, swap)
		}
	}
	if len(swaps) == 0 {
		return disabledFlags, nil
	}

	if err := d.(VariantSwapper).SwapVariants(ctx, swaps, sudoPassword, progressChan); err != nil {
		return nil, fmt.Errorf("failed to switch package variants: %w", err)
	}

	skip := maps.Clone(disabledFlags)
	if skip == nil {
		skip = make(map[string]bool, len(swaps))
	}
	for _, swap := range swaps {
		skip[swap.Dep] = true
	}
	return skip, nil
}

func swapNames(swaps []VariantSwap) (from, to []string) {
	for _, swap := range swaps {
		from = append(from, swap.From.Name)
		to = append(to, swap.To.Name)
	}
	return from, to
}

func swapTargets(swaps []VariantSwap, repo RepositoryType) []PackageMapping {
	var targets []PackageMapping
	for _, swap := range swaps {
		if swap.To.Repository == repo {
			targets = append(targets, swap.To)
		}
	}
	return targets
}
