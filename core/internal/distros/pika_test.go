package distros

import (
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

func TestPikaPackageMapping_SystemRepoOnly(t *testing.T) {
	d := NewDebianDistribution(Registry["pika"], nil)
	variants := map[string]deps.PackageVariant{
		"quickshell":      deps.VariantGit,
		"dms (Dux Shell)": deps.VariantGit,
	}
	for _, wm := range []deps.WindowManager{deps.WindowManagerNiri, deps.WindowManagerHyprland} {
		packages := d.GetPackageMappingWithVariants(wm, variants)
		for name, pkg := range packages {
			if pkg.Repository != RepoTypeSystem {
				t.Errorf("%v: pika maps %s to %s, want system repo", wm, name, pkg.Repository)
			}
		}
		if packages["dms (Dux Shell)"].Name != "dms-git" {
			t.Errorf("%v: dms git variant = %s, want dms-git", wm, packages["dms (Dux Shell)"].Name)
		}
	}
	hypr := d.GetPackageMapping(deps.WindowManagerHyprland)
	if _, ok := hypr["hyprland"]; !ok {
		t.Error("pika offers hyprland but maps no package for it")
	}
	if hypr["hyprland-guiutils"].Name != "hyprland-qtutils" {
		t.Errorf("hyprland-guiutils = %s, want hyprland-qtutils", hypr["hyprland-guiutils"].Name)
	}
}
