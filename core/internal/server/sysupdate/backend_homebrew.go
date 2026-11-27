package sysupdate

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

func init() {
	RegisterOverlayBackend(func() Backend { return homebrewBackend{bin: brewPath()} })
}

// The check already ran brew update, so later calls must not repeat it.
var brewEnv = []string{"HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_NO_ENV_HINTS=1"}

type homebrewBackend struct {
	bin string
}

func (homebrewBackend) ID() string                           { return "homebrew" }
func (homebrewBackend) DisplayName() string                  { return "Homebrew" }
func (homebrewBackend) Repo() RepoKind                       { return RepoHomebrew }
func (homebrewBackend) NeedsAuth() bool                      { return false }
func (homebrewBackend) RunsInTerminal() bool                 { return false }
func (b homebrewBackend) IsAvailable(_ context.Context) bool { return b.bin != "" }

// brewPath returns the brew binary, falling back to the default Linux prefix
// because compositors often start the shell without brew's shellenv on PATH.
func brewPath() string {
	for _, p := range []string{"brew", "/home/linuxbrew/.linuxbrew/bin/brew"} {
		if path, err := exec.LookPath(p); err == nil {
			return path
		}
	}
	return ""
}

func (b homebrewBackend) command(ctx context.Context, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, b.bin, args...)
	cmd.Env = append(cmd.Environ(), brewEnv...)
	return cmd
}

func (b homebrewBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	if out, err := b.command(ctx, "update", "--quiet").CombinedOutput(); err != nil {
		return nil, fmt.Errorf("brew update: %w: %s", err, strings.TrimSpace(string(out)))
	}
	out, err := b.command(ctx, "outdated", "--json=v2").Output()
	if err != nil {
		if _, ok := errors.AsType[*exec.ExitError](err); !ok || len(out) == 0 {
			return nil, err
		}
	}
	return parseBrewOutdated(out)
}

// Some brew versions print a cask's installed version as a bare string.
type brewVersions []string

func (v *brewVersions) UnmarshalJSON(data []byte) error {
	var one string
	if json.Unmarshal(data, &one) == nil {
		*v = brewVersions{one}
		return nil
	}
	return json.Unmarshal(data, (*[]string)(v))
}

type brewOutdatedEntry struct {
	Name              string       `json:"name"`
	InstalledVersions brewVersions `json:"installed_versions"`
	CurrentVersion    string       `json:"current_version"`
	Pinned            bool         `json:"pinned"`
}

// parseBrewOutdated turns `brew outdated --json=v2` output into packages. Pinned
// formulae are left out because brew upgrade skips them.
func parseBrewOutdated(data []byte) ([]Package, error) {
	var doc struct {
		Formulae []brewOutdatedEntry `json:"formulae"`
		Casks    []brewOutdatedEntry `json:"casks"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("parse brew outdated: %w", err)
	}
	var pkgs []Package
	for _, e := range append(doc.Formulae, doc.Casks...) {
		if e.Name == "" || e.Pinned {
			continue
		}
		var from string
		if n := len(e.InstalledVersions); n > 0 {
			from = e.InstalledVersions[n-1]
		}
		pkgs = append(pkgs, Package{
			Name:        e.Name,
			Repo:        RepoHomebrew,
			Backend:     "homebrew",
			FromVersion: from,
			ToVersion:   e.CurrentVersion,
		})
	}
	return pkgs, nil
}

func (b homebrewBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	if !opts.IncludeHomebrew || !BackendHasTargets(b, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}
	argv := brewUpgradeArgv(b.bin, opts)
	if argv == nil {
		return nil
	}
	return Run(ctx, argv, RunOptions{Env: brewEnv, OnLine: onLine})
}

// brewUpgradeArgv builds a plain brew upgrade when nothing is ignored. brew has
// no exclude flag, so otherwise it names the already-filtered targets, and
// returns nil when none are left.
func brewUpgradeArgv(bin string, opts UpgradeOptions) []string {
	argv := []string{bin, "upgrade"}
	if opts.DryRun {
		argv = append(argv, "--dry-run")
	}
	if len(opts.Ignored) == 0 {
		return argv
	}
	base := len(argv)
	for _, p := range opts.Targets {
		if p.Backend == "homebrew" && safePkgName.MatchString(p.Name) {
			argv = append(argv, p.Name)
		}
	}
	if len(argv) == base {
		return nil
	}
	return argv
}
