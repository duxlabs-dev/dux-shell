package sysupdate

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

func init() {
	RegisterOverlayBackend(func() Backend { return &flatpakBackend{} })
}

type flatpakBackend struct{}

func (flatpakBackend) ID() string                         { return "flatpak" }
func (flatpakBackend) DisplayName() string                { return "Flatpak" }
func (flatpakBackend) Repo() RepoKind                     { return RepoFlatpak }
func (flatpakBackend) NeedsAuth() bool                    { return false }
func (flatpakBackend) RunsInTerminal() bool               { return false }
func (flatpakBackend) IsAvailable(_ context.Context) bool { return commandExists("flatpak") }

func (flatpakBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	// Without --no-deps an update needing an uninstalled runtime prompts first, and declining aborts before the table prints.
	cmd := exec.CommandContext(ctx, "flatpak", "update", "--no-deps")
	cmd.Stdin = strings.NewReader("n\nn\n") // decline up to 2 installation prompts
	out, err := cmd.Output()
	pkgs := parseFlatpakUpdateOutput(string(out), flatpakInstalled(ctx))
	// Declining the final prompt also exits non-zero, so only a failure without a table is an error.
	if err != nil && len(pkgs) == 0 {
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			if msg := lastNonEmptyLine(string(exitErr.Stderr)); msg != "" {
				return nil, fmt.Errorf("flatpak update: %s", msg)
			}
		}
		return nil, err
	}
	return pkgs, nil
}

type flatpakInstalledEntry struct {
	version string
	branch  string
}

func flatpakInstalled(ctx context.Context) map[string]flatpakInstalledEntry {
	m := flatpakListInstalled(ctx, false)
	if m == nil {
		m = make(map[string]flatpakInstalledEntry)
	}
	for k, v := range flatpakListInstalled(ctx, true) {
		if _, exists := m[k]; !exists {
			m[k] = v
		}
	}
	return m
}

func flatpakListInstalled(ctx context.Context, system bool) map[string]flatpakInstalledEntry {
	args := []string{"flatpak", "list", "--columns=application,version,branch"}
	if system {
		args = append(args, "--system")
	}
	out, err := exec.CommandContext(ctx, args[0], args[1:]...).Output()
	if err != nil {
		return nil
	}
	m := make(map[string]flatpakInstalledEntry)
	for line := range strings.SplitSeq(string(out), "\n") {
		if line == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) == 0 || fields[0] == "" {
			continue
		}
		appID := fields[0]
		entry := flatpakInstalledEntry{}
		if len(fields) > 1 {
			entry.version = fields[1]
		}
		if len(fields) > 2 {
			entry.branch = fields[2]
		}
		key := appID
		if entry.branch != "" {
			key = appID + "//" + entry.branch
		}
		m[key] = entry
	}
	return m
}

func (flatpakBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	if opts.DryRun {
		return Run(ctx, []string{"flatpak", "update", "--no-deploy", "-y"}, RunOptions{OnLine: onLine})
	}
	if !BackendHasTargets(flatpakBackend{}, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}
	return Run(ctx, flatpakUpgradeArgv(opts), RunOptions{OnLine: onLine})
}

func flatpakUpgradeArgv(opts UpgradeOptions) []string {
	argv := []string{"flatpak", "update", "-y", "--noninteractive"}
	if len(opts.Ignored) == 0 {
		return argv
	}
	// No exclude flag; update the already-filtered refs explicitly.
	for _, p := range opts.Targets {
		if p.Repo == RepoFlatpak && p.Ref != "" {
			argv = append(argv, p.Ref)
		}
	}
	return argv
}

func parseFlatpakUpdateOutput(text string, installed map[string]flatpakInstalledEntry) []Package {
	var pkgs []Package
	seen := make(map[string]bool)
	for line := range strings.SplitSeq(text, "\n") {
		p := parseFlatpakUpdateRow(strings.TrimRight(line, "\r"), installed)
		if p == nil || seen[p.Ref] {
			continue
		}
		seen[p.Ref] = true
		pkgs = append(pkgs, *p)
	}
	return pkgs
}

func parseFlatpakUpdateRow(line string, installed map[string]flatpakInstalledEntry) *Package {
	// Row format: " N.\t<name>\t<appID>\t<branch>\t<op>\t<remote>\t<size>"
	fields := strings.Split(line, "\t")
	if len(fields) < 5 {
		return nil
	}
	// First field must look like " N." (optional whitespace, digits, period)
	rowField := strings.TrimSpace(fields[0])
	if len(rowField) < 2 || rowField[len(rowField)-1] != '.' {
		return nil
	}
	for _, c := range rowField[:len(rowField)-1] {
		if c < '0' || c > '9' {
			return nil
		}
	}

	appID := strings.TrimSpace(fields[2])
	branch := strings.TrimSpace(fields[3])
	op := strings.TrimSpace(fields[4])
	if appID == "" || op == "" {
		return nil
	}
	switch op {
	case "i", "u", "r": // install, update, reinstall
	default:
		return nil
	}

	ref := appID
	if branch != "" {
		ref = appID + "//" + branch
	}

	name := strings.TrimSpace(fields[1])
	if name == "" {
		name = appID
	}

	var from string
	if op != "i" {
		if inst, ok := installed[ref]; ok {
			from = inst.version
		}
	}

	return &Package{
		Name:        name,
		Repo:        RepoFlatpak,
		Backend:     "flatpak",
		FromVersion: from,
		Ref:         ref,
	}
}
