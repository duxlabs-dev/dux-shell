package distros

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/site"
	"github.com/spf13/afero"
)

// Markers only reached when /run/ostree-booted is absent, such as a chroot.
var immutableIDs = map[string]bool{
	"bluefin":          true,
	"bazzite":          true,
	"aurora":           true,
	"secureblue":       true,
	"zirconium":        true,
	"fedora-iot":       true,
	"fedora-coreos":    true,
	"opensuse-microos": true,
	"opensuse-aeon":    true,
	"steamos":          true,
	"org.gnome.os":     true,
	"blendos":          true,
	"arkane":           true,
}

var immutableVariantMarkers = []string{"silverblue", "kinoite", "sericea", "onyx", "atomic", "coreos", "iot"}

var immutableMarkerFiles = []struct {
	path   string
	reason string
}{
	{"/run/ostree-booted", "ostree-based system"},
	{"/usr/sbin/transactional-update", "transactional-update system"},
	{"/usr/bin/abroot", "ABRoot system"},
}

const ZirconiumSwitchCommand = "sudo bootc switch ghcr.io/zirconium-dev/zirconium:latest"

// The commands are shown to the user, never run.
type PackageLayerer interface {
	LayerCommands(dependencies []deps.Dependency, wm deps.WindowManager, reinstallFlags, disabledFlags map[string]bool) []string
}

func DetectImmutable() (bool, string) {
	fs := afero.NewOsFs()
	return detectImmutable(fs, readOSRelease(fs))
}

func detectImmutable(fs afero.Fs, osRelease map[string]string) (bool, string) {
	for _, marker := range immutableMarkerFiles {
		if exists, _ := afero.Exists(fs, marker.path); exists {
			return true, fmt.Sprintf("%s (%s)", marker.reason, marker.path)
		}
	}

	id := strings.ToLower(osRelease["ID"])
	if immutableIDs[id] {
		return true, "os-release ID=" + id
	}

	variantID := strings.ToLower(osRelease["VARIANT_ID"])
	for _, marker := range immutableVariantMarkers {
		if strings.Contains(variantID, marker) {
			return true, "os-release VARIANT_ID=" + variantID
		}
	}

	for _, like := range strings.Fields(strings.ToLower(osRelease["ID_LIKE"])) {
		if like == "microos" || like == "ostree" {
			return true, "os-release ID_LIKE=" + like
		}
	}

	return false, ""
}

func ImmutableGuidance(info *OSInfo) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s is an image-based system: %s.\n\n", info.PrettyName, info.ImmutableReason)
	b.WriteString("duxinstall has no package mapping for this image, so it cannot tell what is installed or deploy configuration for it. Nothing was changed on this system.\n\n")
	b.WriteString("See " + site.Docs + "/getting-started for other options.")
	return b.String()
}

func PendingDependencies(dependencies []deps.Dependency, reinstallFlags, disabledFlags map[string]bool) []deps.Dependency {
	var pending []deps.Dependency
	for _, dep := range dependencies {
		if disabledFlags[dep.Name] {
			continue
		}
		if dep.Status == deps.StatusInstalled && !reinstallFlags[dep.Name] {
			continue
		}
		pending = append(pending, dep)
	}
	return pending
}

// detectDMS keys off the clone directory; packaged hosts only have /usr/bin/dms.
func ApplyImmutableDetection(dependencies []deps.Dependency) []deps.Dependency {
	if _, err := exec.LookPath("dms"); err != nil {
		return dependencies
	}
	for i := range dependencies {
		if dependencies[i].Name != "dms (Dux Shell)" || dependencies[i].Status != deps.StatusMissing {
			continue
		}
		dependencies[i].Status = deps.StatusInstalled
		// "dms (git) v2.0.0-5333" or "dms v2.0.0"
		out, err := exec.Command("dms", "version").Output()
		if err != nil {
			continue
		}
		fields := strings.Fields(string(out))
		if len(fields) > 0 {
			dependencies[i].Version = fields[len(fields)-1]
		}
		if strings.Contains(string(out), "(git)") {
			dependencies[i].Variant = deps.VariantGit
		}
	}
	return dependencies
}
