package distros

import (
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

func TestFedoraPackageMapping_EnterpriseLinuxUsesCOPRForMissingEPELPackages(t *testing.T) {
	el := NewFedoraDistribution(Registry["rhel"], nil).GetPackageMapping(deps.WindowManagerNiri)
	for _, name := range []string{"alacritty", "xwayland-satellite"} {
		if el[name].Repository != RepoTypeCOPR || el[name].RepoURL != "duxlabs/dux-repo" {
			t.Errorf("rhel %s = %+v, want duxlabs/dux-repo COPR", name, el[name])
		}
	}

	fedora := NewFedoraDistribution(Registry["fedora"], nil).GetPackageMapping(deps.WindowManagerNiri)
	for _, name := range []string{"alacritty", "xwayland-satellite"} {
		if fedora[name].Repository != RepoTypeSystem {
			t.Errorf("fedora %s = %+v, want system repo", name, fedora[name])
		}
	}
}
