package sysupdate

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

func init() {
	RegisterSystemBackend(func() Backend { return &dnfBackend{bin: "dnf5"} })
	RegisterSystemBackend(func() Backend { return &dnfBackend{bin: "dnf"} })
}

type dnfBackend struct {
	bin string
}

func (b dnfBackend) ID() string           { return b.bin }
func (b dnfBackend) DisplayName() string  { return strings.ToUpper(b.bin) }
func (b dnfBackend) Repo() RepoKind       { return RepoSystem }
func (b dnfBackend) NeedsAuth() bool      { return true }
func (b dnfBackend) RunsInTerminal() bool { return false }

func (b dnfBackend) IsAvailable(ctx context.Context) bool {
	if !commandExists(b.bin) {
		return false
	}
	if commandExists("rpm-ostree") && ostreeBooted(ctx) {
		return false
	}
	return true
}

func (b dnfBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	out, err := dnfListUpgrades(ctx, b.bin)
	if err != nil {
		return nil, err
	}
	installed := rpmInstalledVersions(ctx)
	return parseDnfList(out, b.bin, installed), nil
}

func (b dnfBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	if opts.DryRun {
		return Run(ctx, []string{b.bin, "upgrade", "--assumeno"}, RunOptions{OnLine: onLine})
	}
	if !BackendHasTargets(b, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}
	return Run(ctx, dnfUpgradeArgv(b.bin, opts), RunOptions{OnLine: onLine, AttachStdio: opts.AttachStdio})
}

func dnfUpgradeArgv(bin string, opts UpgradeOptions) []string {
	argv := withAutoYes(opts, []string{bin, "upgrade", "--refresh"}, "-y")
	if len(opts.Ignored) > 0 {
		argv = append(argv, "--exclude="+strings.Join(opts.Ignored, ","))
	}
	return privilegedArgv(opts, argv...)
}

func dnfListUpgrades(ctx context.Context, bin string) (string, error) {
	argv := dnfCheckUpdatesArgv(bin)
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	out, err := cmd.CombinedOutput()
	if err == nil {
		return string(out), nil
	}
	if exitErr, ok := errors.AsType[*exec.ExitError](err); ok && exitErr.ExitCode() == 100 {
		return string(out), nil
	}
	if detail := lastNonEmptyLine(string(out)); detail != "" {
		return "", fmt.Errorf("%w: %s", err, detail)
	}
	return "", err
}

func lastNonEmptyLine(text string) string {
	lines := strings.Split(text, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if line := strings.TrimSpace(lines[i]); line != "" {
			return line
		}
	}
	return ""
}

func dnfCheckUpdatesArgv(bin string) []string {
	subcommand := "check-update"
	if bin == "dnf5" {
		subcommand = "check-upgrade"
	}
	return []string{bin, subcommand, "--refresh", "--quiet"}
}

func rpmInstalledVersions(ctx context.Context) map[string]string {
	out, err := exec.CommandContext(ctx, "rpm", "-qa", "--qf", `%{NAME}\t%{VERSION}-%{RELEASE}\n`).Output()
	if err != nil {
		return nil
	}
	m := make(map[string]string)
	for line := range strings.SplitSeq(string(out), "\n") {
		name, ver, ok := strings.Cut(line, "\t")
		if !ok {
			continue
		}
		m[name] = ver
	}
	return m
}

func parseDnfList(text, backendID string, installed map[string]string) []Package {
	if text == "" {
		return nil
	}
	var pkgs []Package
	seen := make(map[string]struct{})
	for line := range strings.SplitSeq(text, "\n") {
		// indented rows are packages being obsoleted, which are removals rather than upgrades
		if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		nameArch := fields[0]
		version := fields[1]
		dot := strings.LastIndex(nameArch, ".")
		if dot <= 0 {
			continue
		}
		if !looksLikeRpmVersion(version) {
			continue
		}
		// dnf prints one row per (package, repo), so one version in two repos appears twice
		key := nameArch + "\t" + version
		if _, dup := seen[key]; dup {
			continue
		}
		seen[key] = struct{}{}
		name := nameArch[:dot]
		pkgs = append(pkgs, Package{
			Name:        nameArch,
			Repo:        RepoSystem,
			Backend:     backendID,
			FromVersion: installed[name],
			ToVersion:   version,
		})
	}
	return pkgs
}

func looksLikeRpmVersion(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r >= '0' && r <= '9' {
			return true
		}
	}
	return false
}
