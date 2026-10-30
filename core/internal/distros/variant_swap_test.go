package distros

import (
	"context"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

type swapFake struct {
	Distribution
	installed map[string]bool
	swapped   []VariantSwap
}

func (f *swapFake) GetPackageMappingWithVariants(_ deps.WindowManager, variants map[string]deps.PackageVariant) map[string]PackageMapping {
	return map[string]PackageMapping{
		"dms-greeter": variantMapping("dms-greeter", variants["dms-greeter"], RepoTypeCOPR, "duxlabs/dux-repo"),
		"matugen":     {Name: "matugen", Repository: RepoTypeSystem},
	}
}

func (f *swapFake) InstalledVariant(stable, git PackageMapping) (deps.PackageVariant, bool) {
	return installedVariantByName(func(p string) bool { return f.installed[p] }, stable, git)
}

func (f *swapFake) SwapVariants(_ context.Context, swaps []VariantSwap, _ string, _ chan<- InstallProgressMsg) error {
	f.swapped = append(f.swapped, swaps...)
	return nil
}

func TestPlanVariantSwap(t *testing.T) {
	cases := []struct {
		name      string
		dep       string
		installed string
		target    deps.PackageVariant
		want      SwapStatus
		from, to  string
	}{
		{"stable to git", "dms-greeter", "dms-greeter", deps.VariantGit, SwapNeeded, "dms-greeter", "dms-greeter-git"},
		{"git to stable", "dms-greeter", "dms-greeter-git", deps.VariantStable, SwapNeeded, "dms-greeter-git", "dms-greeter"},
		{"already on target", "dms-greeter", "dms-greeter-git", deps.VariantGit, SwapAlreadyOnTarget, "", ""},
		{"not installed", "dms-greeter", "", deps.VariantGit, SwapNotInstalled, "", ""},
		{"same mapping both ways", "matugen", "matugen", deps.VariantGit, SwapNoVariant, "", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			d := &swapFake{installed: map[string]bool{tc.installed: true}}
			swap, status := PlanVariantSwap(d, deps.WindowManagerNiri, tc.dep, tc.target)
			if status != tc.want || swap.From.Name != tc.from || swap.To.Name != tc.to {
				t.Fatalf("got %v %q→%q, want %v %q→%q", status, swap.From.Name, swap.To.Name, tc.want, tc.from, tc.to)
			}
		})
	}
}

func TestSwapReinstalledVariantsSkipsSwappedDeps(t *testing.T) {
	d := &swapFake{installed: map[string]bool{"dms-greeter": true}}
	dependencies := []deps.Dependency{
		{Name: "dms-greeter", Status: deps.StatusInstalled, Variant: deps.VariantGit},
		{Name: "matugen", Status: deps.StatusInstalled},
	}
	reinstall := map[string]bool{"dms-greeter": true, "matugen": true}
	disabled := map[string]bool{}

	skip, err := swapReinstalledVariants(context.Background(), d, dependencies, deps.WindowManagerNiri, reinstall, disabled, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(d.swapped) != 1 || d.swapped[0].To.Name != "dms-greeter-git" {
		t.Fatalf("swapped = %+v, want only dms-greeter → dms-greeter-git", d.swapped)
	}
	if !skip["dms-greeter"] || skip["matugen"] {
		t.Fatalf("skip = %v, want the swapped greeter skipped and matugen reinstalled", skip)
	}
	if len(disabled) != 0 {
		t.Fatalf("caller's disabled flags were mutated: %v", disabled)
	}
}
