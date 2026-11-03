package sysupdate

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"slices"
	"strings"
	"time"
)

type shellyBackend struct{}

func (shellyBackend) ID() string          { return "shelly" }
func (shellyBackend) DisplayName() string { return "Shelly (AUR)" }
func (shellyBackend) Repo() RepoKind      { return RepoSystem }
func (shellyBackend) NeedsAuth() bool     { return true }
func (shellyBackend) RunsInTerminal() bool {
	return os.Getenv("DMS_FORCE_PKEXEC") != "1"
}

func (shellyBackend) IsAvailable(ctx context.Context) bool {
	if !commandExists("shelly") {
		return false
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	out, err := Capture(ctx, []string{"shelly", "--version", "--json"})
	if err != nil {
		return false
	}
	var version struct {
		Name          string `json:"name"`
		SchemaVersion int    `json:"schemaVersion"`
	}
	// Shelly 3.1.3 introduced this CLI identity response.
	return json.Unmarshal([]byte(out), &version) == nil && version.Name == "shelly" && version.SchemaVersion == 1
}

func (b shellyBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	pkgs, err := b.checkUpdates(ctx, RepoSystem)
	if err != nil {
		return nil, err
	}
	aur, err := b.checkUpdates(ctx, RepoAUR)
	if err != nil {
		return nil, err
	}
	return append(pkgs, aur...), nil
}

func (b shellyBackend) checkUpdates(ctx context.Context, repo RepoKind) ([]Package, error) {
	kind := "standard"
	if repo == RepoAUR {
		kind = "aur"
	}
	out, err := Capture(ctx, []string{"shelly", "list-updates", kind, "--json"})
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if err != nil {
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			return nil, fmt.Errorf("shelly %s update check: %w: %s", kind, err, strings.TrimSpace(string(exitErr.Stderr)))
		}
		return nil, fmt.Errorf("shelly %s update check: %w", kind, err)
	}
	return parseShellyUpdates(out, repo)
}

func parseShellyUpdates(out string, repo RepoKind) ([]Package, error) {
	var updates []struct {
		Name           string
		CurrentVersion string
		Version        string
		NewVersion     string
		DownloadSize   int64
		PackageBase    string
	}
	if err := json.Unmarshal([]byte(out), &updates); err != nil {
		return nil, fmt.Errorf("shelly %s updates: invalid JSON: %w", repo, err)
	}
	if updates == nil {
		return nil, fmt.Errorf("shelly %s updates: expected a JSON array", repo)
	}
	var pkgs []Package
	for _, update := range updates {
		fromVersion := update.CurrentVersion
		if repo == RepoAUR {
			fromVersion = update.Version
		}
		if update.Name == "" || fromVersion == "" || update.NewVersion == "" {
			return nil, fmt.Errorf("shelly %s updates: missing package name or version", repo)
		}
		pkg := Package{
			Name:        update.Name,
			Backend:     "shelly",
			Repo:        repo,
			FromVersion: fromVersion,
			ToVersion:   update.NewVersion,
			SizeBytes:   max(0, update.DownloadSize),
		}
		if repo == RepoAUR {
			base := update.PackageBase
			if base == "" {
				base = update.Name
			}
			pkg.ChangelogURL = "https://aur.archlinux.org/packages/" + url.PathEscape(base)
		}
		pkgs = append(pkgs, pkg)
	}
	return pkgs, nil
}

func (b shellyBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	if !BackendHasTargets(b, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}
	var aur []Package
	if opts.IncludeAUR && (opts.DryRun || len(opts.Ignored) > 0) {
		// The manager has already removed held packages from opts.Targets.
		var err error
		aur, err = b.checkUpdates(ctx, RepoAUR)
		if err != nil {
			return err
		}
		for _, pkg := range aur {
			if slices.Contains(opts.Ignored, pkg.Name) {
				return fmt.Errorf("shelly cannot exclude held AUR package %q; disable AUR updates or remove its DMS hold before updating", pkg.Name)
			}
		}
	}
	if opts.DryRun {
		pkgs, err := b.checkUpdates(ctx, RepoSystem)
		if err != nil {
			return err
		}
		pkgs = append(pkgs, aur...)
		for _, pkg := range pkgs {
			if onLine != nil {
				onLine(fmt.Sprintf("%s %s -> %s", pkg.Name, pkg.FromVersion, pkg.ToVersion))
			}
		}
		return nil
	}
	argv := shellyUpgradeArgv(opts)
	if opts.AttachStdio {
		return Run(ctx, argv, RunOptions{OnLine: onLine, AttachStdio: true})
	}
	if !b.RunsInTerminal() {
		return Run(ctx, argv, RunOptions{OnLine: onLine, Env: []string{"SHELLY_ELEVATOR=pkexec"}})
	}
	term := findTerminal(opts.Terminal)
	if term == "" {
		return fmt.Errorf("no terminal found (pick one in DMS settings, set $TERMINAL, or install kitty/ghostty/foot/alacritty)")
	}
	return Run(ctx, wrapInTerminal(term, "DMS — System Update (shelly)", strings.Join(argv, " "), opts.TerminalArgs), RunOptions{OnLine: onLine})
}

func shellyUpgradeArgv(opts UpgradeOptions) []string {
	if !opts.IncludeAUR {
		return withAutoYes(opts, []string{"shelly", "upgrade", "standard"}, "--no-confirm")
	}
	return withAutoYes(opts, []string{"shelly", "upgrade", "all", "--no-flatpak", "--no-appimage"}, "--no-confirm")
}
