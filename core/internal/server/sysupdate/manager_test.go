package sysupdate

import (
	"context"
	"slices"
	"strings"
	"testing"
)

type customUpgradeTestBackend struct {
	pacmanBackend
	checks int
}

func (b *customUpgradeTestBackend) CheckUpdates(context.Context) ([]Package, error) {
	b.checks++
	return nil, nil
}

func TestCustomUpgradeFailure(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PATH", dir)
	writeUpdateExecutable(t, dir, "fake-terminal", `while [ "$#" -gt 0 ] && [ "$1" != sh ]; do shift; done
[ "$#" -gt 0 ] || exit 99
shift
exec /bin/sh "$@"`)

	backend := &customUpgradeTestBackend{}
	m := &Manager{
		selection:   Selection{System: backend},
		notifyDirty: make(chan struct{}, 1),
		stopChan:    make(chan struct{}),
	}
	m.runCustomUpgrade(t.Context(), "false", "test", UpgradeOptions{Terminal: "fake-terminal"})

	state := m.GetState()
	if state.Phase != PhaseError {
		t.Errorf("phase = %s, want %s", state.Phase, PhaseError)
	}
	if state.Error == nil || state.Error.Code != ErrCodeBackendFailed || !strings.Contains(state.Error.Message, "exit status 1") {
		t.Errorf("error = %#v, want backend-failed with exit status 1", state.Error)
	}
	if slices.Contains(state.RecentLog, "Upgrade complete.") {
		t.Error("failed custom upgrade logged success")
	}
	if backend.checks != 0 {
		t.Errorf("failed custom upgrade refreshed %d times", backend.checks)
	}
}

type stopTestBackend struct {
	id      string
	upgrade func(context.Context) error
	checks  int
}

func (b *stopTestBackend) ID() string                       { return b.id }
func (b *stopTestBackend) DisplayName() string              { return b.id }
func (b *stopTestBackend) Repo() RepoKind                   { return RepoSystem }
func (b *stopTestBackend) IsAvailable(context.Context) bool { return true }
func (b *stopTestBackend) NeedsAuth() bool                  { return false }
func (b *stopTestBackend) RunsInTerminal() bool             { return false }
func (b *stopTestBackend) CheckUpdates(context.Context) ([]Package, error) {
	b.checks++
	return nil, nil
}
func (b *stopTestBackend) Upgrade(ctx context.Context, _ UpgradeOptions, _ func(string)) error {
	return b.upgrade(ctx)
}

func TestUserStoppedUpgradeIsNotAFailure(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())

	t.Run("dismissed password prompt", func(t *testing.T) {
		system := &stopTestBackend{id: "dnf", upgrade: func(ctx context.Context) error {
			return Run(ctx, []string{"/bin/sh", "-c", "exit 126"}, RunOptions{})
		}}
		m := &Manager{selection: Selection{System: system}, notifyDirty: make(chan struct{}, 1), stopChan: make(chan struct{})}
		m.runUpgrade(t.Context(), UpgradeOptions{Targets: []Package{{Name: "kernel-core", Repo: RepoSystem, Backend: "dnf"}}})

		state := m.GetState()
		if state.Phase != PhaseIdle || state.Error != nil {
			t.Errorf("phase = %s, error = %#v, want idle without error", state.Phase, state.Error)
		}
		if state.Reboot.Recommended {
			t.Error("dismissed upgrade recommended a reboot")
		}
		if system.checks != 0 {
			t.Errorf("nothing ran but the list was refreshed %d times", system.checks)
		}
	})

	t.Run("cancel after the kernel landed", func(t *testing.T) {
		ctx, cancel := context.WithCancel(t.Context())
		defer cancel()
		system := &stopTestBackend{id: "dnf", upgrade: func(context.Context) error { return nil }}
		overlay := &stopTestBackend{id: "extra", upgrade: func(ctx context.Context) error {
			cancel()
			return ctx.Err()
		}}
		m := &Manager{selection: Selection{System: system, Overlay: []Backend{overlay}}, notifyDirty: make(chan struct{}, 1), stopChan: make(chan struct{})}
		m.runUpgrade(ctx, UpgradeOptions{Targets: []Package{
			{Name: "kernel-core", Repo: RepoSystem, Backend: "dnf"},
			{Name: "tool", Repo: RepoSystem, Backend: "extra"},
		}})

		state := m.GetState()
		if state.Phase != PhaseIdle || state.Error != nil {
			t.Errorf("phase = %s, error = %#v, want idle without error", state.Phase, state.Error)
		}
		if !state.Reboot.Recommended || !slices.Equal(state.Reboot.Packages, []string{"kernel-core"}) {
			t.Errorf("reboot = %#v, want kernel-core from the finished backend", state.Reboot)
		}
		if system.checks == 0 {
			t.Error("partial upgrade did not refresh the stale package list")
		}
	})
}

type repoTestBackend struct {
	stopTestBackend
	repo    RepoKind
	pkgs    []Package
	onCheck func()
}

func (b *repoTestBackend) Repo() RepoKind { return b.repo }
func (b *repoTestBackend) CheckUpdates(context.Context) ([]Package, error) {
	b.checks++
	if b.onCheck != nil {
		b.onCheck()
	}
	return b.pkgs, nil
}

func TestExcludedOverlaysAreNotChecked(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	system := &repoTestBackend{stopTestBackend: stopTestBackend{id: "dnf"}, repo: RepoSystem, pkgs: []Package{{Name: "bash", Repo: RepoSystem, Backend: "dnf"}}}
	flatpak := &repoTestBackend{stopTestBackend: stopTestBackend{id: "flatpak"}, repo: RepoFlatpak}
	brew := &repoTestBackend{stopTestBackend: stopTestBackend{id: "homebrew"}, repo: RepoHomebrew, pkgs: []Package{{Name: "git", Repo: RepoHomebrew, Backend: "homebrew"}}}
	m := &Manager{
		selection:   Selection{System: system, Overlay: []Backend{flatpak, brew}},
		notifyDirty: make(chan struct{}, 1),
		stopChan:    make(chan struct{}),
	}
	names := func() []string {
		var out []string
		for _, p := range m.GetState().Packages {
			out = append(out, p.Name)
		}
		return out
	}

	m.SetExcluded([]string{"homebrew", "system"})
	m.runRefresh(t.Context(), false)
	if system.checks != 1 || flatpak.checks != 1 || brew.checks != 0 {
		t.Fatalf("checks system=%d flatpak=%d homebrew=%d, want 1 1 0", system.checks, flatpak.checks, brew.checks)
	}
	if got := names(); !slices.Equal(got, []string{"bash"}) {
		t.Fatalf("packages while excluded = %v, want [bash]", got)
	}

	m.SetExcluded(nil)
	m.runRefresh(t.Context(), false)
	if got := names(); brew.checks != 1 || !slices.Equal(got, []string{"bash", "git"}) {
		t.Fatalf("re-included homebrew: checks=%d packages=%v", brew.checks, got)
	}

	brew.onCheck = func() { m.SetExcluded([]string{"homebrew"}) }
	m.runRefresh(t.Context(), false)
	if got := names(); !slices.Equal(got, []string{"bash"}) {
		t.Fatalf("packages after excluding mid-check = %v, want [bash]", got)
	}
}
