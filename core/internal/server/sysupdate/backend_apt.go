package sysupdate

import (
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

func init() {
	RegisterSystemBackend(func() Backend { return &aptBackend{} })
}

var aptUpgradableLine = regexp.MustCompile(`^([^/]+)/\S+\s+(\S+)\s+\S+\s+\[upgradable from:\s+([^\]]+)\]`)

type aptBackend struct{}

func (aptBackend) ID() string           { return "apt" }
func (aptBackend) DisplayName() string  { return "APT" }
func (aptBackend) Repo() RepoKind       { return RepoSystem }
func (aptBackend) NeedsAuth() bool      { return true }
func (aptBackend) RunsInTerminal() bool { return false }
func (aptBackend) IsAvailable(_ context.Context) bool {
	return commandExists("apt") || commandExists("apt-get")
}

func (aptBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	cmd := exec.CommandContext(ctx, "apt", "list", "--upgradable")
	cmd.Env = append(cmd.Environ(), "LC_ALL=C")
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	return filterAptHeld(parseAptUpgradable(string(out)), aptHeldPackages(ctx)), nil
}

// aptHeldPackages returns held packages, which apt-get upgrade never applies.
func aptHeldPackages(ctx context.Context) map[string]bool {
	out, err := exec.CommandContext(ctx, "apt-mark", "showhold").Output()
	if err != nil {
		return nil
	}
	held := make(map[string]bool)
	for line := range strings.SplitSeq(string(out), "\n") {
		if name := strings.TrimSpace(line); name != "" {
			held[name] = true
		}
	}
	return held
}

func filterAptHeld(pkgs []Package, held map[string]bool) []Package {
	if len(held) == 0 {
		return pkgs
	}
	out := pkgs[:0]
	for _, p := range pkgs {
		if held[p.Name] {
			continue
		}
		out = append(out, p)
	}
	return out
}

func (aptBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	bin := "apt-get"
	if !commandExists(bin) {
		bin = "apt"
	}
	if opts.DryRun {
		return Run(ctx, []string{bin, "upgrade", "--dry-run"}, RunOptions{
			Env:    []string{"DEBIAN_FRONTEND=noninteractive", "LC_ALL=C"},
			OnLine: onLine,
		})
	}
	if !BackendHasTargets(aptBackend{}, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}
	return Run(ctx, aptUpgradeArgv(bin, opts), RunOptions{OnLine: onLine, AttachStdio: opts.AttachStdio})
}

func aptUpgradeArgv(bin string, opts UpgradeOptions) []string {
	ignored := shellSafeNames(opts.Ignored)
	upgrade := aptUpgradeCmd(bin, opts)
	env := []string{"env", "DEBIAN_FRONTEND=noninteractive", "LC_ALL=C"}
	if opts.Interactive {
		env = []string{"env"}
	}
	if len(ignored) == 0 {
		return privilegedArgv(opts, append(env, upgrade...)...)
	}
	return privilegedArgv(opts, append(env, "sh", "-c", aptHoldScript(strings.Join(upgrade, " "), ignored))...)
}

// DEBIAN_FRONTEND only silences debconf; dpkg still asks about modified config files and fails on EOF.
func aptUpgradeCmd(bin string, opts UpgradeOptions) []string {
	if opts.Interactive {
		return []string{bin, "upgrade"}
	}
	return []string{bin, "upgrade", "-y", "-o", "Dpkg::Options::=--force-confdef", "-o", "Dpkg::Options::=--force-confold"}
}

// aptHoldScript holds ignored packages only for the upgrade, leaving pre-existing user holds untouched.
func aptHoldScript(upgrade string, ignored []string) string {
	names := strings.Join(ignored, " ")
	return fmt.Sprintf(
		`new=""; for p in %s; do apt-mark showhold | grep -qx "$p" || new="$new $p"; done; `+
			`[ -n "$new" ] && apt-mark hold $new; `+
			`%s; rc=$?; `+
			`[ -n "$new" ] && apt-mark unhold $new; exit $rc`,
		names, upgrade)
}

func parseAptUpgradable(text string) []Package {
	if text == "" {
		return nil
	}
	var pkgs []Package
	for line := range strings.SplitSeq(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		m := aptUpgradableLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		pkgs = append(pkgs, Package{
			Name:        m[1],
			Repo:        RepoSystem,
			Backend:     "apt",
			FromVersion: m[3],
			ToVersion:   m[2],
		})
	}
	return pkgs
}
