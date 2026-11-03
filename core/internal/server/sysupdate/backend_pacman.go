package sysupdate

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

func init() {
	RegisterSystemBackend(func() Backend { return &archHelperBackend{id: "paru"} })
	RegisterSystemBackend(func() Backend { return &archHelperBackend{id: "yay"} })
	RegisterSystemBackend(func() Backend { return &shellyBackend{} })
	RegisterSystemBackend(func() Backend { return &pacmanBackend{} })
}

var archUpdateLine = regexp.MustCompile(`^(\S+)\s+(\S+)\s+->\s+(\S+)`)

type pacmanBackend struct{}

func (pacmanBackend) ID() string                         { return "pacman" }
func (pacmanBackend) DisplayName() string                { return "Pacman" }
func (pacmanBackend) Repo() RepoKind                     { return RepoSystem }
func (pacmanBackend) NeedsAuth() bool                    { return true }
func (pacmanBackend) RunsInTerminal() bool               { return false }
func (pacmanBackend) IsAvailable(_ context.Context) bool { return commandExists("pacman") }

func (b pacmanBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	out, err := pacmanRepoUpdates(ctx)
	if err != nil {
		return nil, err
	}
	return parseArchUpdates(out, b.ID(), RepoSystem), nil
}

func (b pacmanBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	if opts.DryRun {
		return Run(ctx, []string{"pacman", "-Sup"}, RunOptions{OnLine: onLine})
	}
	if !BackendHasTargets(b, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}
	return Run(ctx, pacmanUpgradeArgv(opts), RunOptions{OnLine: onLine, AttachStdio: opts.AttachStdio})
}

func pacmanUpgradeArgv(opts UpgradeOptions) []string {
	return privilegedArgv(opts, withAutoYes(opts, []string{"pacman", "-Syu", "--needed"}, "--noconfirm")...)
}

// Arch repository packages must upgrade together; AUR packages may be held.
func dropPacmanRepoIgnores(ignored []string, pending []Package) []string {
	if len(ignored) == 0 {
		return ignored
	}
	repoPending := make(map[string]bool, len(pending))
	for _, p := range pending {
		if p.Repo == RepoSystem {
			repoPending[p.Name] = true
		}
	}
	out := make([]string, 0, len(ignored))
	for _, name := range ignored {
		if repoPending[name] {
			continue
		}
		out = append(out, name)
	}
	return out
}

func isPacmanFamily(b Backend) bool {
	if b == nil {
		return false
	}
	switch b.ID() {
	case "pacman", "paru", "yay", "shelly":
		return true
	default:
		return false
	}
}

type archHelperBackend struct {
	id string
}

func (b archHelperBackend) ID() string      { return b.id }
func (b archHelperBackend) Repo() RepoKind  { return RepoSystem }
func (b archHelperBackend) NeedsAuth() bool { return true }
func (b archHelperBackend) RunsInTerminal() bool {
	return os.Getenv("DMS_FORCE_PKEXEC") != "1"
}
func (b archHelperBackend) IsAvailable(_ context.Context) bool { return commandExists(b.id) }

func (b archHelperBackend) DisplayName() string {
	switch b.id {
	case "paru":
		return "Paru (AUR)"
	case "yay":
		return "Yay (AUR)"
	default:
		return b.id
	}
}

func (b archHelperBackend) CheckUpdates(ctx context.Context) ([]Package, error) {
	repoOut, err := pacmanRepoUpdates(ctx)
	if err != nil {
		return nil, err
	}
	pkgs := parseArchUpdates(repoOut, b.id, RepoSystem)

	aurOut, err := capturePermissive(ctx, b.id, "-Qua")
	if err != nil {
		return nil, err
	}
	pkgs = append(pkgs, parseArchUpdates(aurOut, b.id, RepoAUR)...)
	return pkgs, nil
}

func (b archHelperBackend) Upgrade(ctx context.Context, opts UpgradeOptions, onLine func(string)) error {
	if opts.DryRun {
		return Run(ctx, []string{b.id, "-Sup"}, RunOptions{OnLine: onLine})
	}
	if !BackendHasTargets(b, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return nil
	}
	if os.Getenv("DMS_FORCE_PKEXEC") == "1" {
		argv := append([]string{"pkexec"}, archHelperUpgradeArgv(b.id, opts)...)
		return Run(ctx, argv, RunOptions{OnLine: onLine, AttachStdio: opts.AttachStdio})
	}
	if opts.AttachStdio {
		return Run(ctx, archHelperUpgradeArgv(b.id, opts), RunOptions{OnLine: onLine, AttachStdio: true})
	}
	term := findTerminal(opts.Terminal)
	if term == "" {
		return fmt.Errorf("no terminal found (pick one in DMS settings, set $TERMINAL, or install kitty/ghostty/foot/alacritty)")
	}
	cmd := strings.Join(archHelperUpgradeArgv(b.id, opts), " ")
	title := fmt.Sprintf("DMS — System Update (%s)", b.id)
	return Run(ctx, wrapInTerminal(term, title, cmd, opts.TerminalArgs), RunOptions{OnLine: onLine})
}

func archHelperUpgradeArgv(id string, opts UpgradeOptions) []string {
	argv := withAutoYes(opts, []string{id, "-Syu", "--needed"}, "--noconfirm")
	if !opts.IncludeAUR {
		argv = append(argv, "--repo")
	}
	ignored := shellSafeNames(opts.Ignored)
	if len(ignored) > 0 {
		argv = append(argv, "--ignore", strings.Join(ignored, ","))
	}
	return argv
}

func pacmanRepoUpdates(ctx context.Context) (string, error) {
	if commandExists("checkupdates") {
		return capturePermissive(ctx, "checkupdates")
	}
	if commandExists("fakeroot") {
		out, err := pacmanCheckViaFakeroot(ctx)
		if err == nil {
			return out, nil
		}
		log.Warnf("[sysupdate] fakeroot db refresh failed, falling back to stale pacman -Qu: %v", err)
	}
	return capturePermissive(ctx, "pacman", "-Qu")
}

func pacmanCheckViaFakeroot(ctx context.Context) (string, error) {
	dir, err := pacmanPrivateDB()
	if err != nil {
		return "", err
	}

	if err := seedPacmanDB(dir); err != nil {
		return "", fmt.Errorf("seed sync db: %w", err)
	}

	refresh := exec.CommandContext(ctx, "fakeroot", "--", "pacman", "-Sy", "--dbpath", dir, "--logfile", "/dev/null", "--disable-sandbox")
	if out, err := refresh.CombinedOutput(); err != nil {
		return "", fmt.Errorf("fakeroot pacman -Sy: %w (%s)", err, strings.TrimSpace(string(out)))
	}

	return capturePermissive(ctx, "pacman", "-Qu", "--dbpath", dir)
}

func seedPacmanDB(dir string) error {
	syncDir := filepath.Join(dir, "sync")
	if err := os.MkdirAll(syncDir, 0o755); err != nil {
		return err
	}
	dbs, err := filepath.Glob("/var/lib/pacman/sync/*.db")
	if err != nil {
		return err
	}
	for _, src := range dbs {
		if err := copyFile(src, filepath.Join(syncDir, filepath.Base(src))); err != nil {
			return err
		}
	}

	localLink := filepath.Join(dir, "local")
	if fi, err := os.Lstat(localLink); err == nil {
		if fi.Mode()&os.ModeSymlink == 0 {
			if err := os.RemoveAll(localLink); err != nil {
				return err
			}
		} else {
			return nil
		}
	}
	return os.Symlink("/var/lib/pacman/local", localLink)
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	fi, err := in.Stat()
	if err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	if err := out.Sync(); err != nil {
		out.Close()
		return err
	}
	if err := out.Close(); err != nil {
		return err
	}
	// Preserve mtime so libalpm's If-Modified-Since against --dbpath actually
	// refetches when the mirror has newer content; otherwise the seeded copy's
	// fresh mtime always beats the server's Last-Modified and the private DB
	// stays stuck at whatever /var/lib/pacman/sync contained at seed time.
	return os.Chtimes(dst, fi.ModTime(), fi.ModTime())
}

func pacmanPrivateDB() (string, error) {
	tmp := os.Getenv("TMPDIR")
	if tmp == "" {
		tmp = "/tmp"
	}
	dir := filepath.Join(tmp, fmt.Sprintf("dms-checkup-db-%d", os.Getuid()))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

func capturePermissive(ctx context.Context, argv ...string) (string, error) {
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	out, err := cmd.Output()
	if err == nil {
		return string(out), nil
	}
	if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
		switch exitErr.ExitCode() {
		case 1, 2:
			return string(out), nil
		}
	}
	return "", err
}

func parseArchUpdates(text, backendID string, repo RepoKind) []Package {
	if text == "" {
		return nil
	}
	var pkgs []Package
	for line := range strings.SplitSeq(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// pacman -Qu / paru -Qua flag IgnorePkg entries with a trailing marker
		if strings.HasSuffix(line, "[ignored]") {
			continue
		}
		m := archUpdateLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		p := Package{
			Name:        m[1],
			Repo:        repo,
			Backend:     backendID,
			FromVersion: m[2],
			ToVersion:   m[3],
		}
		if repo == RepoAUR {
			p.ChangelogURL = "https://aur.archlinux.org/packages/" + p.Name
		}
		pkgs = append(pkgs, p)
	}
	return pkgs
}
