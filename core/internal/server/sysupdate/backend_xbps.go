package sysupdate

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"syscall"
)

func init() {
	RegisterSystemBackend(func() Backend { return &xbpsBackend{} })
}

type xbpsBackend struct{}

func (xbpsBackend) ID() string                         { return "xbps" }
func (xbpsBackend) DisplayName() string                { return "XBPS" }
func (xbpsBackend) Repo() RepoKind                     { return RepoSystem }
func (xbpsBackend) NeedsAuth() bool                    { return true }
func (xbpsBackend) RunsInTerminal() bool               { return false }
func (xbpsBackend) IsAvailable(_ context.Context) bool { return commandExists("xbps-install") }

func (b xbpsBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	// -M syncs repodata into memory only, so the check is fresh without root
	out, err := exec.CommandContext(ctx, "xbps-install", "-Mun").Output()
	if err != nil {
		// EBUSY: xbps refuses a full update while xbps itself is outdated
		exitErr, ok := errors.AsType[*exec.ExitError](err)
		if !ok || exitErr.ExitCode() != int(syscall.EBUSY) {
			return nil, err
		}
		if out, err = exec.CommandContext(ctx, "xbps-install", "-Mun", "xbps").Output(); err != nil {
			return nil, err
		}
	}
	installed, err := exec.CommandContext(ctx, "xbps-query", "-l").Output()
	if err != nil {
		return nil, err
	}
	return parseXbpsDryRun(string(out), parseXbpsInstalled(string(installed))), nil
}

func (xbpsBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	if opts.DryRun {
		return Run(ctx, []string{"xbps-install", "-Mun"}, RunOptions{OnLine: onLine})
	}
	if !BackendHasTargets(xbpsBackend{}, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}
	return Run(ctx, xbpsUpgradeArgv(opts), RunOptions{OnLine: onLine, AttachStdio: opts.AttachStdio})
}

func xbpsUpgradeArgv(opts UpgradeOptions) []string {
	ignored := shellSafeNames(opts.Ignored)
	selfUpdate := xbpsSelfUpdatePending(opts.Targets)
	if len(ignored) == 0 && !selfUpdate {
		return privilegedArgv(opts, withAutoYes(opts, []string{"xbps-install", "-Syu"}, "-y")...)
	}
	return privilegedArgv(opts, "sh", "-c", xbpsUpgradeScript(ignored, selfUpdate, opts.Interactive))
}

func xbpsSelfUpdatePending(targets []Package) bool {
	for _, p := range targets {
		if p.Backend == "xbps" && p.Name == "xbps" {
			return true
		}
	}
	return false
}

// One script = one auth prompt: xbps updates itself first (Void requires it); ignored packages are
// held only for this run, pre-existing user holds stay.
func xbpsUpgradeScript(ignored []string, selfUpdate, interactive bool) string {
	yes := " -y"
	if interactive {
		yes = ""
	}
	var sb strings.Builder
	if len(ignored) > 0 {
		fmt.Fprintf(&sb,
			`new=""; for p in %s; do xbps-query -H | sed 's/-[^-]*$//' | grep -qxF "$p" || new="$new $p"; done; `+
				`[ -n "$new" ] && xbps-pkgdb -m hold $new; `,
			strings.Join(ignored, " "))
	}
	if selfUpdate {
		fmt.Fprintf(&sb, `xbps-install -Syu%s xbps && xbps-install -u%s; rc=$?; `, yes, yes)
	} else {
		fmt.Fprintf(&sb, `xbps-install -Syu%s; rc=$?; `, yes)
	}
	if len(ignored) > 0 {
		sb.WriteString(`[ -n "$new" ] && xbps-pkgdb -m unhold $new; `)
	}
	sb.WriteString(`exit $rc`)
	return sb.String()
}

// pkgver is "name-version_revision"; names may contain '-', versions never do.
func splitPkgver(pkgver string) (name, version string, ok bool) {
	idx := strings.LastIndex(pkgver, "-")
	if idx <= 0 || idx == len(pkgver)-1 {
		return "", "", false
	}
	return pkgver[:idx], pkgver[idx+1:], true
}

// `xbps-query -l`: "<state> <pkgver> <description>"
func parseXbpsInstalled(text string) map[string]string {
	installed := make(map[string]string)
	for line := range strings.SplitSeq(text, "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		if name, version, ok := splitPkgver(fields[1]); ok {
			installed[name] = version
		}
	}
	return installed
}

// `xbps-install -n`: "<pkgver> <action> <arch> <repository> <installedsize> <downloadsize>"
func parseXbpsDryRun(text string, installed map[string]string) []Package {
	var pkgs []Package
	for line := range strings.SplitSeq(text, "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 || fields[1] != "update" {
			continue
		}
		name, version, ok := splitPkgver(fields[0])
		if !ok {
			continue
		}
		pkgs = append(pkgs, Package{
			Name:        name,
			Repo:        RepoSystem,
			Backend:     "xbps",
			FromVersion: installed[name],
			ToVersion:   version,
		})
	}
	return pkgs
}
