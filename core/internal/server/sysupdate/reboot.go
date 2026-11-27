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

func needsReboot(p Package) bool {
	if p.Repo == RepoFlatpak || p.Repo == RepoAUR || p.Repo == RepoHomebrew {
		return false
	}
	return rebootPackageRe.MatchString(strings.ToLower(p.Name))
}

func markRebootPackages(pkgs []Package) {
	for i := range pkgs {
		pkgs[i].NeedsReboot = needsReboot(pkgs[i])
	}
}

func rebootPackages(pkgs []Package) []string {
	var out []string
	for _, p := range pkgs {
		if needsReboot(p) {
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
