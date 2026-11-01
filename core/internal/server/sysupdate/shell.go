package sysupdate

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

const ownerQueryTimeout = 10 * time.Second

var dmsPackageNames = map[string]bool{
	"dms": true, "dms-git": true,
	"dux-shell": true, "dux-shell-git": true,
}

// Arch/Debian/SUSE: 1.7.0+git4915.56234761; Fedora COPR: 0.0.git.4915.56234761
var gitBuildRe = regexp.MustCompile(`\+git(\d+)\.|\.git\.(\d+)\.`)

func GitBuildCount(version string) int {
	m := gitBuildRe.FindStringSubmatch(version)
	if m == nil {
		return 0
	}
	for _, s := range m[1:] {
		if s != "" {
			n, _ := strconv.Atoi(s)
			return n
		}
	}
	return 0
}

// "/usr/bin/dms (deleted)" after a package upgrade.
func dmsBinaryPath() string {
	path, err := os.Executable()
	if err != nil {
		path, err = exec.LookPath("dms")
		if err != nil {
			return ""
		}
	}
	path = strings.TrimSuffix(path, " (deleted)")
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved
	}
	return path
}

// Package managers unlink+create, so a different inode than /proc/self/exe means a new build.
func binaryReplaced(path string) bool {
	if path == "" {
		return false
	}
	running, err := os.Stat("/proc/self/exe")
	if err != nil {
		return false
	}
	onDisk, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !os.SameFile(running, onDisk)
}

func unprobedShell(running string) ShellInfo {
	info := ShellInfo{InstallMethod: InstallUnknown, Running: running, GitBuild: GitBuildCount(running)}
	info.Channel = detectChannel(info, running)
	return info
}

// Unowned binaries (manual copy, dev checkout) stay unknown: DMS only updates through packages.
func ProbeShell(ctx context.Context, running string) ShellInfo {
	info := unprobedShell(running)
	path := dmsBinaryPath()

	if strings.HasPrefix(path, "/nix/store/") {
		info.InstallMethod = InstallNix
	} else if method, name, version := packageOwner(ctx, path); method != "" {
		info.InstallMethod = method
		info.PackageName = name
		info.Installed = version
	}

	info.Channel = detectChannel(info, running)
	info.RestartPending = binaryReplaced(path)
	return info
}

func detectChannel(info ShellInfo, running string) Channel {
	switch {
	case strings.HasSuffix(info.PackageName, "-git"), GitBuildCount(running) > 0:
		return ChannelGit
	case info.InstallMethod == InstallUnknown, running == "", running == "dev":
		return ChannelUnknown
	default:
		return ChannelStable
	}
}

// Only one query runs on a normal system, but rpm can take a moment to open its database.
func packageOwner(ctx context.Context, path string) (InstallMethod, string, string) {
	if path == "" {
		return "", "", ""
	}
	ctx, cancel := context.WithTimeout(ctx, ownerQueryTimeout)
	defer cancel()

	switch {
	case commandExists("pacman"):
		// "/usr/bin/dms is owned by dux-shell-git 2.0.0+git4915-1"
		out := runOutput(ctx, "pacman", "-Qo", path)
		fields := strings.Fields(out)
		if len(fields) < 2 {
			return "", "", ""
		}
		return InstallPacman, fields[len(fields)-2], fields[len(fields)-1]
	case commandExists("rpm"):
		out := runOutput(ctx, "rpm", "-qf", "--qf", `%{NAME}\t%{VERSION}-%{RELEASE}`, path)
		name, version, _ := strings.Cut(strings.TrimSpace(out), "\t")
		if name == "" || strings.Contains(name, "not owned") {
			return "", "", ""
		}
		return InstallRPM, name, version
	case commandExists("dpkg-query"):
		// "dms: /usr/bin/dms"
		out := runOutput(ctx, "dpkg-query", "-S", path)
		name, _, ok := strings.Cut(out, ":")
		if !ok || name == "" {
			return "", "", ""
		}
		name = strings.TrimSpace(name)
		version := strings.TrimSpace(runOutput(ctx, "dpkg-query", "-W", "-f=${Version}", name))
		return InstallDpkg, name, version
	case commandExists("xbps-query"):
		// "dms-1.7_1: /usr/bin/dms (regular file)"
		out := runOutput(ctx, "xbps-query", "-o", path)
		pkgver, _, found := strings.Cut(out, ":")
		name, version, ok := splitPkgver(pkgver)
		if !found || !ok {
			return "", "", ""
		}
		return InstallXbps, name, version
	}
	return "", "", ""
}

func runOutput(ctx context.Context, name string, args ...string) string {
	out, err := exec.CommandContext(ctx, name, args...).Output()
	if err != nil {
		log.Debugf("[sysupdate] %s %v: %v", name, args, err)
		return ""
	}
	return string(out)
}

// Returns a copy: the packages slice is reused in place after upgrades.
func findShellPackage(pkgs []Package, ownerName string) *Package {
	var fallback *Package
	for i := range pkgs {
		p := pkgs[i]
		if ownerName != "" && p.Name == ownerName {
			return &p
		}
		if fallback == nil && dmsPackageNames[p.Name] {
			fallback = &p
		}
	}
	return fallback
}

func commitsBehind(shell ShellInfo, master *MasterInfo) *int {
	if master == nil || shell.Channel != ChannelGit {
		return nil
	}
	n := GitBuildCount(shell.Running)
	if n == 0 {
		return nil
	}
	behind := max(master.CommitCount-n, 0)
	return &behind
}
