package sysupdate

import (
	"os"
	"regexp"
	"strings"
)

// Upgrades that only take effect after a reboot: kernels (linux*, kernel*, linux-image-*), systemd, glibc, firmware.
var rebootPackageRe = regexp.MustCompile(`^(linux(-[a-z0-9]+)*|linux-image-.*|kernel(-.*)?|systemd(-[a-z]+)?|glibc|libc6|linux-firmware|dracut|mesa)$`)

type RebootInfo struct {
	Recommended bool     `json:"recommended"`
	Packages    []string `json:"packages,omitempty"`
}

func rebootPackages(pkgs []Package) []string {
	var out []string
	for _, p := range pkgs {
		if p.Repo == RepoFlatpak || p.Repo == RepoAUR {
			continue
		}
		if rebootPackageRe.MatchString(strings.ToLower(p.Name)) {
			out = append(out, p.Name)
		}
	}
	return out
}

func bootID() string {
	data, err := os.ReadFile("/proc/sys/kernel/random/boot_id")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}
