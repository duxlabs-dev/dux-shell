package sysupdate

import (
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

func init() {
	RegisterSystemBackend(func() Backend { return &zypperBackend{} })
}

type zypperBackend struct{}

func (zypperBackend) ID() string                         { return "zypper" }
func (zypperBackend) DisplayName() string                { return "Zypper" }
func (zypperBackend) Repo() RepoKind                     { return RepoSystem }
func (zypperBackend) NeedsAuth() bool                    { return true }
func (zypperBackend) RunsInTerminal() bool               { return false }
func (zypperBackend) IsAvailable(_ context.Context) bool { return commandExists("zypper") }

type zypperUpdateList struct {
	XMLName xml.Name       `xml:"stream"`
	Updates []zypperUpdate `xml:"update-list>update"`
}

type zypperUpdate struct {
	Name       string `xml:"name,attr"`
	Edition    string `xml:"edition,attr"`
	EditionOld string `xml:"edition-old,attr"`
	Kind       string `xml:"kind,attr"`
}

func (zypperBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	cmd := exec.CommandContext(ctx, "zypper", "--non-interactive", "--xmlout", "list-updates")
	out, err := cmd.Output()
	if err != nil {
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			switch exitErr.ExitCode() {
			case 100, 101, 102, 103:
				err = nil
			}
		}
		if err != nil {
			return nil, err
		}
	}
	return parseZypperXML(out)
}

func parseZypperXML(out []byte) ([]Package, error) {
	var list zypperUpdateList
	if err := xml.Unmarshal(out, &list); err != nil {
		return nil, err
	}
	pkgs := make([]Package, 0, len(list.Updates))
	for _, u := range list.Updates {
		if u.Kind != "" && u.Kind != "package" {
			continue
		}
		pkgs = append(pkgs, Package{
			Name:        u.Name,
			Repo:        RepoSystem,
			Backend:     "zypper",
			FromVersion: u.EditionOld,
			ToVersion:   u.Edition,
		})
	}
	return pkgs, nil
}

func (zypperBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	if opts.DryRun {
		return Run(ctx, []string{"zypper", "--non-interactive", "--dry-run", "update"}, RunOptions{OnLine: onLine})
	}
	if !BackendHasTargets(zypperBackend{}, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}
	return Run(ctx, zypperUpgradeArgv(opts), RunOptions{OnLine: onLine, AttachStdio: opts.AttachStdio})
}

func zypperUpgradeArgv(opts UpgradeOptions) []string {
	ignored := shellSafeNames(opts.Ignored)
	if len(ignored) == 0 {
		return privilegedArgv(opts, zypperUpdateArgv(opts)...)
	}
	return privilegedArgv(opts, "sh", "-c", zypperLockScript(ignored, strings.Join(zypperUpdateArgv(opts), " ")))
}

func zypperUpdateArgv(opts UpgradeOptions) []string {
	if opts.Interactive {
		return []string{"zypper", "update"}
	}
	return []string{"zypper", "--non-interactive", "update"}
}

// zypperLockScript locks ignored packages only for the update, leaving pre-existing user locks untouched.
func zypperLockScript(ignored []string, update string) string {
	names := strings.Join(ignored, " ")
	return fmt.Sprintf(
		`new=""; for p in %s; do grep -qsE "^solvable_name:[[:space:]]*$p$" /etc/zypp/locks || new="$new $p"; done; `+
			`[ -n "$new" ] && zypper --non-interactive al $new; `+
			`%s; rc=$?; `+
			`[ -n "$new" ] && zypper --non-interactive rl $new; exit $rc`,
		names, update)
}
