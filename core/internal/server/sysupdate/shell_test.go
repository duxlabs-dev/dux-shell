package sysupdate

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/netfetch"
)

func TestGitBuildCount(t *testing.T) {
	for _, tt := range []struct {
		version string
		want    int
	}{
		{"1.7.0+git4915.56234761", 4915},
		{"0.0.git.4920.d430cae9", 4920},
		{"1.7.0", 0},
	} {
		if got := GitBuildCount(tt.version); got != tt.want {
			t.Errorf("GitBuildCount(%q) = %d, want %d", tt.version, got, tt.want)
		}
	}
}

func TestPackageOwnerParsing(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PATH", dir)
	for _, tt := range []struct {
		tool, body  string
		wantMethod  InstallMethod
		wantName    string
		wantVersion string
	}{
		{"pacman", `echo "/usr/bin/dms is owned by dms-shell-git 1.7.0+git4915-1"`, InstallPacman, "dms-shell-git", "1.7.0+git4915-1"},
		{"rpm", `printf 'dms-git\t1.7.0-1.fc44'`, InstallRPM, "dms-git", "1.7.0-1.fc44"},
		{"xbps-query", `echo "dms-1.7.0_1: /usr/bin/dms (regular file)"`, InstallXbps, "dms", "1.7.0_1"},
	} {
		t.Run(tt.tool, func(t *testing.T) {
			writeUpdateExecutable(t, dir, tt.tool, tt.body)
			defer os.Remove(filepath.Join(dir, tt.tool))
			method, name, version := packageOwner(context.Background(), "/usr/bin/dms")
			if method != tt.wantMethod || name != tt.wantName || version != tt.wantVersion {
				t.Errorf("packageOwner = (%s, %s, %s), want (%s, %s, %s)", method, name, version, tt.wantMethod, tt.wantName, tt.wantVersion)
			}
		})
	}
}

func TestPackageOwnerDpkg(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PATH", dir)
	writeUpdateExecutable(t, dir, "dpkg-query", `case "$1" in
-S) echo "dms: /usr/bin/dms" ;;
-W) echo "1.7.0-1" ;;
esac`)
	method, name, version := packageOwner(context.Background(), "/usr/bin/dms")
	if method != InstallDpkg || name != "dms" || version != "1.7.0-1" {
		t.Errorf("packageOwner = (%s, %s, %s)", method, name, version)
	}
}

func TestDetectChannel(t *testing.T) {
	for _, tt := range []struct {
		name    string
		info    ShellInfo
		running string
		want    Channel
	}{
		{"git package", ShellInfo{InstallMethod: InstallPacman, PackageName: "dms-shell-git"}, "1.7.0", ChannelGit},
		{"git version", ShellInfo{InstallMethod: InstallRPM, PackageName: "dms"}, "0.0.git.4920.abc", ChannelGit},
		{"stable package", ShellInfo{InstallMethod: InstallPacman, PackageName: "dms-shell-bin"}, "1.7.0", ChannelStable},
		{"dev build", ShellInfo{InstallMethod: InstallPacman, PackageName: "dms-shell"}, "dev", ChannelUnknown},
		{"unknown method", ShellInfo{InstallMethod: InstallUnknown}, "1.7.0", ChannelUnknown},
	} {
		if got := detectChannel(tt.info, tt.running); got != tt.want {
			t.Errorf("%s: detectChannel = %s, want %s", tt.name, got, tt.want)
		}
	}
}

func TestFindShellPackagePrefersOwner(t *testing.T) {
	pkgs := []Package{{Name: "dux-shell"}, {Name: "dux-shell-git"}, {Name: "firefox"}}
	if got := findShellPackage(pkgs, "dux-shell-git"); got == nil || got.Name != "dux-shell-git" {
		t.Errorf("owner match = %v", got)
	}
	if got := findShellPackage(pkgs, ""); got == nil || got.Name != "dux-shell" {
		t.Errorf("fallback = %v", got)
	}
	if got := findShellPackage([]Package{{Name: "firefox"}}, "dms"); got != nil {
		t.Errorf("no dms package = %v", got)
	}
}

func TestCommitsBehind(t *testing.T) {
	master := &MasterInfo{CommitCount: 4920}
	if got := commitsBehind(ShellInfo{Channel: ChannelStable, Running: "1.7.0+git4915.abc"}, master); got != nil {
		t.Errorf("stable channel = %d, want nil", *got)
	}
	if got := commitsBehind(ShellInfo{Channel: ChannelGit, Running: "1.7.0+git4915.abc"}, master); got == nil || *got != 5 {
		t.Errorf("git channel = %v, want 5", got)
	}
	if got := commitsBehind(ShellInfo{Channel: ChannelGit, Running: "1.7.0+git4930.abc"}, master); got == nil || *got != 0 {
		t.Errorf("ahead of feed = %v, want 0", got)
	}
}

func newTestManager(t *testing.T) *Manager {
	t.Helper()
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	return &Manager{
		notifyDirty: make(chan struct{}, 1),
		stopChan:    make(chan struct{}),
		state:       State{Shell: ShellInfo{Channel: ChannelGit, Running: "1.7.0+git4915.abc"}},
	}
}

func stubFeed(t *testing.T, res netfetch.Conditional, err error) *int {
	t.Helper()
	calls := 0
	orig := releasesFetch
	releasesFetch = func(_ context.Context, etag string) (netfetch.Conditional, error) {
		calls++
		if res.NotModified && etag == "" {
			t.Error("304 stub called without an ETag")
		}
		return res, err
	}
	t.Cleanup(func() { releasesFetch = orig })
	return &calls
}

func TestRefreshReleasesFetchesAndCaches(t *testing.T) {
	m := newTestManager(t)
	body, _ := json.Marshal(ReleasesFeed{
		Latest:   &Release{Tag: "v1.7.1", Version: "1.7.1"},
		Releases: []Release{{Tag: "v1.7.1", Version: "1.7.1"}},
		Master:   &MasterInfo{CommitCount: 4920},
	})
	calls := stubFeed(t, netfetch.Conditional{Body: body, ETag: `"abc"`}, nil)

	feed, err := m.refreshReleases(context.Background(), false)
	if err != nil || feed.Latest == nil || feed.Latest.Version != "1.7.1" || feed.ETag != `"abc"` {
		t.Fatalf("first fetch = %+v, %v", feed, err)
	}
	state := m.GetState()
	if state.Shell.CommitsBehind == nil || *state.Shell.CommitsBehind != 5 {
		t.Errorf("shell after fetch = %+v", state.Shell)
	}

	// Fresh cache: no network.
	if _, err := m.refreshReleases(context.Background(), false); err != nil || *calls != 1 {
		t.Errorf("fresh cache fetched again: calls=%d err=%v", *calls, err)
	}
	// Force: network with the cached ETag.
	if _, err := m.refreshReleases(context.Background(), true); err != nil || *calls != 2 {
		t.Errorf("force did not fetch: calls=%d err=%v", *calls, err)
	}
}

func TestRefreshReleasesNotModifiedKeepsBody(t *testing.T) {
	m := newTestManager(t)
	old := time.Now().Add(-2 * time.Hour).Unix()
	if err := saveReleases(ReleasesFeed{FetchedAt: old, ETag: `"abc"`, Latest: &Release{Version: "1.7.0"}, Releases: []Release{}}); err != nil {
		t.Fatal(err)
	}
	stubFeed(t, netfetch.Conditional{ETag: `"abc"`, NotModified: true}, nil)

	feed, err := m.refreshReleases(context.Background(), false)
	if err != nil || feed.Latest == nil || feed.Latest.Version != "1.7.0" {
		t.Fatalf("304 dropped cached body: %+v, %v", feed, err)
	}
	if feed.FetchedAt == old {
		t.Error("304 did not bump fetchedAt")
	}
}

func TestRefreshReleasesErrorServesCache(t *testing.T) {
	m := newTestManager(t)
	old := time.Now().Add(-2 * time.Hour).Unix()
	if err := saveReleases(ReleasesFeed{FetchedAt: old, Latest: &Release{Version: "1.7.0"}, Releases: []Release{}}); err != nil {
		t.Fatal(err)
	}
	stubFeed(t, netfetch.Conditional{}, errors.New("offline"))

	feed, err := m.refreshReleases(context.Background(), true)
	if err == nil || feed.Latest == nil || feed.Latest.Version != "1.7.0" || feed.FetchedAt != old {
		t.Errorf("offline = %+v, %v", feed, err)
	}
}

func TestSetIntervalSchedulesFromLastCheck(t *testing.T) {
	m := &Manager{
		notifyDirty: make(chan struct{}, 1),
		stopChan:    make(chan struct{}),
		wakeSched:   make(chan struct{}, 1),
	}
	now := time.Now().Unix()
	m.state.LastCheckUnix = now - 3600
	m.state.LastSuccessUnix = m.state.LastCheckUnix
	m.SetInterval(86400)
	if next := m.GetState().NextCheckUnix; next < now+86400-3600-5 || next > now+86400-3600+5 {
		t.Errorf("next = now+%d, want now+%d", next-now, 86400-3600)
	}

	// A failed last check keeps its short retry instead of waiting a full interval.
	m.state.LastCheckUnix = now - 60
	m.state.LastSuccessUnix = now - 3600
	m.SetInterval(86400)
	if next := m.GetState().NextCheckUnix; next < now+retryIntervalSeconds-60-5 || next > now+retryIntervalSeconds-60+5 {
		t.Errorf("failed next = now+%d, want now+%d", next-now, retryIntervalSeconds-60)
	}

	// Overdue checks wait out the startup grace instead of firing into login.
	m.state.LastCheckUnix = now - 2*86400
	m.SetInterval(86400)
	if next := m.GetState().NextCheckUnix; next < now+startupGraceSeconds-5 || next > now+startupGraceSeconds+5 {
		t.Errorf("overdue next = now+%d, want now+%d", next-now, startupGraceSeconds)
	}

	m.SetInterval(0)
	if state := m.GetState(); state.IntervalSeconds != 0 || state.NextCheckUnix != 0 {
		t.Errorf("never: interval = %d, next = %d, want both 0", state.IntervalSeconds, state.NextCheckUnix)
	}
}

func TestRefreshWithoutBackendsAdvancesDeadline(t *testing.T) {
	m := newTestManager(t)
	m.state.IntervalSeconds = 3600

	now := time.Now().Unix()
	m.runRefresh(context.Background(), false)

	state := m.GetState()
	if state.NextCheckUnix < now+3600-5 || state.NextCheckUnix > now+3600+5 {
		t.Errorf("next = now+%d, want now+3600 (an unmoved deadline spins the scheduler)", state.NextCheckUnix-now)
	}
}

func TestRefreshDuringUpgradeAdvancesDeadline(t *testing.T) {
	m := newTestManager(t)
	m.selection = Selection{Overlay: []Backend{&fakeBackend{}}}
	m.state.IntervalSeconds = 3600
	m.state.Phase = PhaseUpgrading

	now := time.Now().Unix()
	m.runRefresh(context.Background(), false)
	if next := m.GetState().NextCheckUnix; next < now+retryIntervalSeconds-5 {
		t.Errorf("next = now+%d, want >= now+%d", next-now, retryIntervalSeconds)
	}
}

func TestSuccessfulUpgradePersistsClearedPackages(t *testing.T) {
	m := newTestManager(t)
	orig := postUpgradeCompleteDelay
	postUpgradeCompleteDelay = 0
	t.Cleanup(func() { postUpgradeCompleteDelay = orig })

	savePersisted(persistedState{LastCheckUnix: 10, Packages: []Package{{Name: "firefox"}}})
	m.state.Packages = []Package{{Name: "firefox"}}
	m.state.Count = 1

	m.finishSuccessfulUpgrade(true, nil)
	if got := loadPersisted(); len(got.Packages) != 0 {
		t.Errorf("persisted packages after upgrade = %v, want none (they resurrect on restart)", got.Packages)
	}
}

type fakeBackend struct{}

func (fakeBackend) ID() string                                                  { return "fake" }
func (fakeBackend) DisplayName() string                                         { return "fake" }
func (fakeBackend) Repo() RepoKind                                              { return RepoFlatpak }
func (fakeBackend) IsAvailable(context.Context) bool                            { return true }
func (fakeBackend) NeedsAuth() bool                                             { return false }
func (fakeBackend) RunsInTerminal() bool                                        { return false }
func (fakeBackend) CheckUpdates(context.Context) ([]Package, error)             { return nil, nil }
func (fakeBackend) Upgrade(context.Context, UpgradeOptions, func(string)) error { return nil }

func TestRebootPackages(t *testing.T) {
	pkgs := []Package{
		{Name: "linux-zen", Repo: RepoSystem}, {Name: "kernel-core", Repo: RepoSystem}, {Name: "linux-image-6.12.0-amd64", Repo: RepoSystem},
		{Name: "systemd", Repo: RepoSystem}, {Name: "glibc", Repo: RepoSystem}, {Name: "firefox", Repo: RepoSystem},
		{Name: "linux-headers", Repo: RepoAUR}, {Name: "kernel-tools", Repo: RepoSystem},
	}
	got := rebootPackages(pkgs)
	want := []string{"linux-zen", "kernel-core", "linux-image-6.12.0-amd64", "systemd", "glibc", "kernel-tools"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("rebootPackages = %v, want %v", got, want)
	}
}

func TestRebootHintPersistsAcrossRestartNotReboot(t *testing.T) {
	m := newTestManager(t)
	orig := postUpgradeCompleteDelay
	postUpgradeCompleteDelay = 0
	t.Cleanup(func() { postUpgradeCompleteDelay = orig })

	m.finishSuccessfulUpgrade(true, []Package{{Name: "systemd", Repo: RepoSystem}})
	if !m.GetState().Reboot.Recommended {
		t.Fatal("systemd upgrade did not recommend a reboot")
	}
	p := loadPersisted()
	if p.RebootBootID != bootID() || len(p.RebootPackages) != 1 {
		t.Fatalf("persisted = %+v", p)
	}
	// A different boot id means the machine rebooted: the hint must not come back.
	p.RebootBootID = "stale"
	savePersisted(p)
	m2, err := NewManager("1.7.0")
	if err != nil {
		t.Fatal(err)
	}
	defer m2.Close()
	if m2.GetState().Reboot.Recommended {
		t.Error("reboot hint survived a reboot")
	}
}

func TestHoldEndsWithItsConnection(t *testing.T) {
	m := newTestManager(t)
	m.holders = make(map[any]func() bool)
	m.probeOnce.Do(func() {})

	ctx, disconnect := context.WithCancel(context.Background())
	m.Acquire(ctx, "client")
	m.Acquire(ctx, "client")
	disconnect()

	deadline := time.Now().Add(5 * time.Second)
	for m.held() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if m.held() {
		t.Error("a disconnected client still holds the scheduler")
	}
}
