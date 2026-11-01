package sysupdate

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/notify"
)

func init() {
	RegisterSystemBackend(func() Backend { return &portageBackend{} })
}

// [ebuild     U  ] sys-apps/util-linux-2.40.4::gentoo [2.40.2::gentoo] USE="..."
var (
	portageUpdateLine = regexp.MustCompile(`^\s*\[(ebuild|binary)\b[^\]]*\]\s+([^\s/]+)/([^\s\[\]]+?)::([^\s\[\]]+)(?:\s+\[\s*([^\s\]]+?)(?:::[^\s\]]+)?\])?`)
	ansiRegexp        = regexp.MustCompile(`\x1B\[[0-9;?]*[ -/]*[@-~]`)
)

func stripANSI(s string) string {
	return ansiRegexp.ReplaceAllString(s, "")
}

type portageBackend struct{}

func (portageBackend) ID() string                         { return "portage" }
func (portageBackend) DisplayName() string                { return "Portage" }
func (portageBackend) Repo() RepoKind                     { return RepoSystem }
func (portageBackend) NeedsAuth() bool                    { return true }
func (portageBackend) RunsInTerminal() bool               { return false }
func (portageBackend) IsAvailable(_ context.Context) bool { return commandExists("emerge") }

func (b portageBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	out, err := capturePortageUpdates(ctx)
	if err != nil {
		return nil, err
	}
	return parsePortageUpdates(out, b.ID()), nil
}

func (b portageBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	err := b.upgrade(ctx, opts, onLine)
	if err != nil && isAuthDismissed(err) {
		return err
	}
	if err != nil && !opts.DryRun && ctx.Err() == nil {
		notifyPortageFailure()

	}
	return err
}

// Notify the user that portage failed so they can check the logs and fix the issue manually
func notifyPortageFailure() {
	if _, err := notify.Send(notify.Notification{
		Summary: "Portage update failed",
		Body:    "Open Settings > Software Updates to read the error log.",
		Timeout: 10000,
	}); err != nil {
		log.Warnf("[sysupdate] portage failure notification: %v", err)
	}
}

func (b portageBackend) upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	if opts.DryRun {
		return Run(ctx, []string{"emerge", "--pretend", "--update", "--newuse", "--deep", "@world"}, RunOptions{OnLine: onLine})
	}
	if !BackendHasTargets(b, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}

	if len(opts.Targets) > 0 && hasPortageTarget(opts.Targets) && !portageIsExcluded(opts) {
		if err := runPortageFirst(ctx, opts, onLine); err != nil {
			return err
		}
	}

	ansiWrap := func(s string) {
		if onLine != nil {
			onLine(stripANSI(s))
		}
	}
	return Run(ctx, portageUpgradeArgv(opts), RunOptions{OnLine: ansiWrap, AttachStdio: opts.AttachStdio})
}

// emerge upgrades all of @world, so ignores are the only way to hold a package back
func portageUpgradeArgv(opts UpgradeOptions) []string {
	argv := []string{"emerge", "--update", "--newuse", "--deep", "--quiet"}
	for _, atom := range shellSafeNames(opts.Ignored) {
		argv = append(argv, "--exclude", atom)
	}
	argv = append(argv, "@world")
	return privilegedArgv(opts, argv...)
}

// Portage can report names without slots, so a sloted ignore only matches slotless packages when it is slot 0.
func PackageMatchesIgnore(pkgName, ignored string) bool {
	pkgBase, pkgSlot, _ := strings.Cut(pkgName, ":")
	ignBase, ignSlot, _ := strings.Cut(ignored, ":")
	if pkgSlot != "" && ignSlot != "" {
		return strings.EqualFold(pkgBase, ignBase) && pkgSlot == ignSlot
	}
	if ignSlot != "" && pkgSlot == "" {
		return strings.EqualFold(pkgBase, ignBase) && ignSlot == "0"
	}
	return strings.EqualFold(pkgBase, ignBase)
}

// IsPackageIgnored reports whether any ignore entry holds pkgName back.
func IsPackageIgnored(pkgName string, ignored []string) bool {
	for _, ign := range ignored {
		if PackageMatchesIgnore(pkgName, ign) {
			return true
		}
	}
	return false
}

// An ignored portage means the user holds it back, so the pre-update step must skip it too
func portageIsExcluded(opts UpgradeOptions) bool {
	for _, ign := range opts.Ignored {
		if IsPackageIgnored("sys-apps/portage", []string{ign}) {
			return true
		}
		base, _, _ := strings.Cut(ign, ":")
		if isPortagePackage(base) {
			return true
		}
	}
	return false
}

func isPortagePackage(name string) bool {
	l := strings.ToLower(name)
	return l == "sys-apps/portage" || l == "portage" || strings.HasSuffix(l, "/portage")
}

func hasPortageTarget(targets []Package) bool {
	for _, p := range targets {
		if p.Backend == "portage" && isPortagePackage(p.Name) {
			return true
		}
	}
	return false
}

// Before running any other system updates, portage should always be updated first
func runPortageFirst(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	argv := []string{"emerge", "--oneshot", "sys-apps/portage"}
	return Run(ctx, privilegedArgv(opts, argv...), RunOptions{OnLine: onLine, AttachStdio: opts.AttachStdio})
}

// Portage needs to sync the repos first before we can check for any available updates
// This requires root, there is no good way around this
// even if this causes the user to suddenly get pkexec prompts if they enable background updates
func portageSync(ctx context.Context) (string, error) {
	argv := privilegedArgv(UpgradeOptions{}, "emerge", "--sync")
	var out strings.Builder
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	if err != nil && isAuthDismissed(err) {
		return out.String(), errors.New("authentication request was dismissed or canceled")
	}
	if err != nil {
		return out.String(), portageRunError(err, out.String())
	}
	return out.String(), nil
}

func portageRunError(err error, output string) error {
	if detail := strings.TrimSpace(output); detail != "" {
		return fmt.Errorf("%w: %s", err, detail)
	}
	return err
}

func capturePortageUpdates(ctx context.Context) (string, error) {
	if _, err := portageSync(ctx); err != nil {
		return "", err
	}

	cmd := exec.CommandContext(ctx, "emerge", "--pretend", "--verbose", "--update", "--newuse", "--deep", "--color=n", "@world")
	cmd.Env = append(cmd.Environ(), "TERM=dumb", "LC_ALL=C")
	var out, errOut strings.Builder
	cmd.Stdout = &out
	cmd.Stderr = &errOut
	// Any non-zero exit means @world does not resolve, and a broken world prints no update list, so it must not read as up to date.
	if err := cmd.Run(); err != nil {
		return "", portageRunError(err, out.String()+errOut.String())
	}
	return out.String(), nil
}

func splitPkgVersion(pkgVer string) (pkg, ver string) {
	for i := 0; i < len(pkgVer)-1; i++ {
		if pkgVer[i] == '-' && pkgVer[i+1] >= '0' && pkgVer[i+1] <= '9' {
			return pkgVer[:i], pkgVer[i+1:]
		}
	}
	return pkgVer, pkgVer
}

func extractPkgAndVersion(pkgVer string) (pkg, ver string) {
	pkg, ver = splitPkgVersion(pkgVer)
	if pkg == pkgVer {
		return "", ver
	}
	return pkg, ver
}

func parsePortageUpdates(text, backendID string) []Package {
	if text == "" {
		return nil
	}
	var pkgs []Package
	for line := range strings.SplitSeq(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		line = stripANSI(line)
		m := portageUpdateLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		category := m[2]
		pkgBase, newVer := splitPkgVersion(m[3])
		_, oldVer := extractPkgAndVersion(m[5])
		pkgs = append(pkgs, Package{
			Name:        category + "/" + pkgBase,
			Repo:        portageRepoLabel(m[1], m[4]),
			Backend:     backendID,
			FromVersion: oldVer,
			ToVersion:   newVer,
		})
	}
	return pkgs
}

// The GUI shows repo and build type in one slot, since Package has no field for it.
func portageRepoLabel(build, repo string) RepoKind {
	if repo == "" {
		repo = "gentoo"
	}
	return RepoKind(repo + " (" + build + ")")
}
