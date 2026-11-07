package sysupdate

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/lowprio"
)

const (
	defaultIntervalSeconds = 24 * 60 * 60
	minIntervalSeconds     = 5 * 60
	startupGraceSeconds    = 2 * 60
	recentLogCapacity      = 200
	checkTimeout           = 5 * time.Minute
	retryIntervalSeconds   = 5 * 60
	upgradeTimeout         = 30 * time.Minute
)

// A var so tests can skip the linger.
var postUpgradeCompleteDelay = 3 * time.Second

type Manager struct {
	mu          sync.RWMutex
	state       State
	subscribers syncmap.Map[string, chan State]

	selection Selection

	notifyDirty chan struct{}
	stopChan    chan struct{}
	notifierWG  sync.WaitGroup
	schedulerWG sync.WaitGroup

	holdMu    sync.Mutex
	holders   map[any]func() bool
	probeOnce sync.Once
	wakeSched chan struct{}

	refreshSerial sync.Mutex
	releasesMu    sync.Mutex

	opMu     sync.Mutex
	opCtx    context.Context
	opCancel context.CancelFunc
}

func NewManager(runningVersion string) (*Manager, error) {
	m := &Manager{
		notifyDirty: make(chan struct{}, 1),
		stopChan:    make(chan struct{}),
		wakeSched:   make(chan struct{}, 1),
		holders:     make(map[any]func() bool),
	}
	persisted := loadPersisted()
	if persisted.Packages == nil {
		persisted.Packages = []Package{}
	}
	m.state = State{
		Phase:           PhaseIdle,
		IntervalSeconds: defaultIntervalSeconds,
		Backends:        []BackendInfo{},
		Packages:        persisted.Packages,
		Count:           len(persisted.Packages),
		LastCheckUnix:   persisted.LastCheckUnix,
		LastSuccessUnix: persisted.LastSuccessUnix,
		Shell:           unprobedShell(runningVersion),
	}
	if persisted.RebootBootID != "" && persisted.RebootBootID == bootID() {
		m.state.Reboot = RebootInfo{Recommended: true, Packages: persisted.RebootPackages}
	}

	id, pretty := readOSRelease()
	m.state.Distro = id
	m.state.DistroPretty = pretty

	m.selection = Select(context.Background())
	m.state.Backends = m.selection.Info()
	if len(m.state.Backends) == 0 {
		m.state.Error = &ErrorInfo{
			Code:    ErrCodeNoBackend,
			Message: "no supported package manager found",
			Hint:    "install a supported package manager (pacman, dnf, apt, zypper, xbps, pkg) or flatpak",
		}
	}

	m.notifierWG.Add(1)
	go m.notifier()

	m.schedulerWG.Add(1)
	go m.scheduler()

	return m, nil
}

func (m *Manager) probeShell() {
	m.mu.RLock()
	running := m.state.Shell.Running
	m.mu.RUnlock()

	info := ProbeShell(context.Background(), running)

	feed, _ := LoadReleases()
	m.mu.Lock()
	info.UpdatePackage = findShellPackage(m.state.Packages, info.PackageName)
	info.CommitsBehind = commitsBehind(info, feed.Master)
	m.state.Shell = info
	m.mu.Unlock()
	m.markDirty()
}

func (m *Manager) Releases(force bool) ReleasesFeed {
	var feed ReleasesFeed
	lowprio.Run(func() {
		var err error
		feed, err = m.refreshReleases(context.Background(), force)
		if err != nil {
			log.Debugf("[sysupdate] releases feed: %v", err)
		}
	})
	return feed
}

// Scheduled from the persisted last check so shell restarts (which re-send the interval) don't push a daily cadence out.
func (m *Manager) nextCheckLocked() int64 {
	now := time.Now().Unix()
	interval := int64(m.state.IntervalSeconds)
	// A failed last check keeps its short retry across restarts.
	if m.state.LastSuccessUnix < m.state.LastCheckUnix {
		interval = min(interval, retryIntervalSeconds)
	}
	return max(m.state.LastCheckUnix+interval, now+startupGraceSeconds)
}

func (m *Manager) GetState() State {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return cloneState(m.state)
}

func (m *Manager) Subscribe(id string) chan State {
	ch := make(chan State, 16)
	m.subscribers.Store(id, ch)
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}
}

func (m *Manager) Close() {
	select {
	case <-m.stopChan:
		return
	default:
		close(m.stopChan)
	}
	m.opMu.Lock()
	if m.opCancel != nil {
		m.opCancel()
	}
	m.opMu.Unlock()
	select {
	case m.wakeSched <- struct{}{}:
	default:
	}
	m.schedulerWG.Wait()
	m.notifierWG.Wait()
	m.subscribers.Range(func(key string, ch chan State) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
}

// Zero turns scheduled checks off; manual and startup checks still run.
func (m *Manager) SetInterval(seconds int) {
	if seconds > 0 && seconds < minIntervalSeconds {
		seconds = minIntervalSeconds
	}
	m.mu.Lock()
	m.state.IntervalSeconds = max(seconds, 0)
	m.state.NextCheckUnix = 0
	if seconds > 0 {
		m.state.NextCheckUnix = m.nextCheckLocked()
	}
	m.mu.Unlock()
	m.wake()
	m.markDirty()
}

func (m *Manager) Refresh(opts RefreshOptions) {
	m.mu.RLock()
	phase := m.state.Phase
	m.mu.RUnlock()

	switch {
	case phase == PhaseUpgrading:
		return
	case phase == PhaseRefreshing && !opts.Force:
		m.refreshSerial.Lock()
		m.refreshSerial.Unlock()
		return
	}
	m.runRefresh(context.Background(), !opts.Background)
}

func (m *Manager) Upgrade(opts UpgradeOptions) error {
	if len(m.selection.All()) == 0 {
		return errors.New("no backend available")
	}

	m.opMu.Lock()
	if m.opCancel != nil {
		m.opMu.Unlock()
		return errors.New("operation already running")
	}
	ctx, cancel := context.WithTimeout(context.Background(), upgradeTimeout)
	m.opCtx = ctx
	m.opCancel = cancel
	m.opMu.Unlock()

	lowprio.Go(func() { m.runUpgrade(ctx, opts) })
	return nil
}

func (m *Manager) Cancel() {
	m.opMu.Lock()
	cancel := m.opCancel
	m.opMu.Unlock()
	if cancel == nil {
		return
	}
	cancel()
}

// A hold ends with its context, so a client that disconnects without releasing cannot leave the scheduler running.
func (m *Manager) Acquire(ctx context.Context, holder any) {
	m.holdMu.Lock()
	if _, held := m.holders[holder]; !held {
		m.holders[holder] = context.AfterFunc(ctx, func() { m.Release(holder) })
	}
	m.holdMu.Unlock()

	m.probeOnce.Do(func() { lowprio.Go(m.probeShell) })

	m.mu.Lock()
	if m.state.NextCheckUnix == 0 {
		m.state.NextCheckUnix = m.nextCheckLocked()
	}
	m.mu.Unlock()
	m.wake()
}

func (m *Manager) Release(holder any) {
	m.holdMu.Lock()
	stop, held := m.holders[holder]
	delete(m.holders, holder)
	m.holdMu.Unlock()
	if held {
		stop()
	}
}

func (m *Manager) held() bool {
	m.holdMu.Lock()
	defer m.holdMu.Unlock()
	return len(m.holders) > 0
}

func (m *Manager) wake() {
	select {
	case m.wakeSched <- struct{}{}:
	default:
	}
}

func (m *Manager) scheduler() {
	defer m.schedulerWG.Done()
	for {
		m.mu.RLock()
		interval := m.state.IntervalSeconds
		next := m.state.NextCheckUnix
		m.mu.RUnlock()
		if !m.held() || interval == 0 {
			select {
			case <-m.stopChan:
				return
			case <-m.wakeSched:
			}
			continue
		}

		if interval < minIntervalSeconds {
			interval = minIntervalSeconds
		}
		now := time.Now().Unix()
		if next == 0 {
			next = now + int64(interval)
		}
		wait := max(time.Duration(next-now)*time.Second, 0)
		t := time.NewTimer(wait)
		select {
		case <-m.stopChan:
			t.Stop()
			return
		case <-m.wakeSched:
			t.Stop()
		case <-t.C:
			m.runRefresh(context.Background(), false)
		}
	}
}

func (m *Manager) runRefresh(parent context.Context, manual bool) {
	m.refreshSerial.Lock()
	defer m.refreshSerial.Unlock()

	ctx, cancel := context.WithTimeout(parent, checkTimeout)
	defer cancel()

	// Move the deadline or the scheduler spins.
	if len(m.selection.All()) == 0 {
		m.mu.Lock()
		m.state.NextCheckUnix = time.Now().Unix() + int64(m.state.IntervalSeconds)
		m.mu.Unlock()
		m.wake()
		m.markDirty()
		return
	}

	m.mu.Lock()
	if m.state.Phase == PhaseUpgrading {
		// Same spin hazard mid-upgrade.
		m.state.NextCheckUnix = time.Now().Unix() + retryIntervalSeconds
		m.mu.Unlock()
		m.wake()
		return
	}
	m.state.Phase = PhaseRefreshing
	m.state.Error = nil
	m.state.RecentLog = nil
	m.mu.Unlock()
	m.markDirty()

	type backendResult struct {
		pkgs []Package
		err  error
	}
	backends := m.selection.All()
	results := make([]backendResult, len(backends))
	var wg sync.WaitGroup
	for i, b := range backends {
		wg.Add(1)
		lowprio.Go(func() {
			defer wg.Done()
			pkgs, err := b.CheckUpdates(ctx)
			results[i] = backendResult{pkgs: pkgs, err: err}
		})
	}
	wg.Wait()

	now := time.Now().Unix()
	replaced := binaryReplaced(dmsBinaryPath())
	m.mu.Lock()
	m.state.LastCheckUnix = now
	prev := m.state.Packages
	next := make([]Package, 0, len(prev))
	var firstErr error
	for i, r := range results {
		if r.err != nil {
			if firstErr == nil {
				firstErr = fmt.Errorf("%s: %w", backends[i].ID(), r.err)
			}
			// Retain a failed backend's last known packages so a transient failure doesn't wipe the list.
			for _, p := range prev {
				if p.Backend == backends[i].ID() {
					next = append(next, p)
				}
			}
			continue
		}
		next = append(next, r.pkgs...)
	}
	m.state.Packages = next
	m.state.Count = len(next)
	m.state.NextCheckUnix = now + int64(m.state.IntervalSeconds)
	m.state.Shell.UpdatePackage = findShellPackage(next, m.state.Shell.PackageName)
	// An upgrade outside DMS changes the installed version only the probe knows.
	reprobe := replaced && !m.state.Shell.RestartPending
	m.state.Shell.RestartPending = replaced
	switch {
	case firstErr == nil:
		m.state.Phase = PhaseIdle
		m.state.LastSuccessUnix = now
	case manual:
		m.state.Phase = PhaseError
		m.state.Error = &ErrorInfo{Code: ErrCodeBackendFailed, Message: firstErr.Error()}
	default:
		// Background checks fail silently and retry sooner; only manual refreshes surface errors.
		m.state.Phase = PhaseIdle
		retry := min(int64(m.state.IntervalSeconds), retryIntervalSeconds)
		m.state.NextCheckUnix = now + retry
		log.Warnf("[sysupdate] background check failed, retrying in %ds: %v", retry, firstErr)
	}
	persist := m.persistedLocked()
	m.mu.Unlock()
	savePersisted(persist)
	if reprobe {
		lowprio.Go(m.probeShell)
	}
	m.wake()
	m.markDirty()
}

func (m *Manager) runUpgrade(ctx context.Context, opts UpgradeOptions) {
	defer func() {
		m.opMu.Lock()
		if m.opCancel != nil {
			m.opCancel = nil
			m.opCtx = nil
		}
		m.opMu.Unlock()
	}()

	if opts.CustomCommand != "" {
		m.runCustomUpgrade(ctx, opts.CustomCommand, "DMS — System Update (custom)", opts)
		return
	}

	if len(opts.Targets) == 0 {
		m.mu.RLock()
		opts.Targets = append([]Package(nil), m.state.Packages...)
		m.mu.RUnlock()
	}
	if isPacmanFamily(m.selection.System) {
		opts.Ignored = dropPacmanRepoIgnores(opts.Ignored, opts.Targets)
	}
	opts.Targets = dropIgnoredTargets(opts.Targets, opts.Ignored)

	if opts.Interactive {
		exe, err := os.Executable()
		if err != nil {
			m.setError(ErrCodeBackendFailed, err.Error())
			return
		}
		m.runCustomUpgrade(ctx, interactiveUpgradeCommand(exe, opts), "DMS — System Update", opts)
		return
	}

	backends := upgradeBackends(m.selection, opts)
	if len(backends) == 0 {
		if len(opts.Targets) > 0 {
			m.setError(ErrCodeNoBackend, "all pending updates are excluded by current settings (AUR/Flatpak disabled)")
		} else {
			m.setError(ErrCodeNoBackend, "no backend selected for upgrade")
		}
		return
	}

	opID := fmt.Sprintf("op-%d", time.Now().UnixNano())
	m.mu.Lock()
	m.state.Phase = PhaseUpgrading
	m.state.OperationID = opID
	m.state.OperationStarted = time.Now().Unix()
	m.state.RecentLog = m.state.RecentLog[:0]
	m.state.Error = nil
	m.mu.Unlock()
	m.markDirty()

	onLine := func(line string) { m.appendLog(line) }
	var installed []Package
	for _, b := range backends {
		m.appendLog(fmt.Sprintf("== %s ==", b.DisplayName()))
		if err := b.Upgrade(ctx, opts, onLine); err != nil {
			if errors.Is(ctx.Err(), context.Canceled) || isAuthDismissed(err) {
				m.stopUpgrade(installed, ctx.Err() != nil || len(installed) > 0)
				return
			}
			code := ErrCodeBackendFailed
			if errors.Is(ctx.Err(), context.DeadlineExceeded) {
				code = ErrCodeTimeout
			}
			m.mu.Lock()
			m.state.Phase = PhaseError
			m.state.Error = &ErrorInfo{Code: code, Message: fmt.Sprintf("%s: %v", b.ID(), err)}
			m.mu.Unlock()
			m.markDirty()
			return
		}
		for _, p := range opts.Targets {
			if p.Backend == b.ID() {
				installed = append(installed, p)
			}
		}
	}

	m.finishSuccessfulUpgrade(true, opts.Targets)
}

func (m *Manager) runCustomUpgrade(ctx context.Context, command, title string, opts UpgradeOptions) {
	term := findTerminal(opts.Terminal)
	if term == "" {
		m.setError(ErrCodeBackendFailed, "no terminal found (pick one in DMS settings, set $TERMINAL, or install kitty/ghostty/foot/alacritty)")
		return
	}

	opID := fmt.Sprintf("op-%d", time.Now().UnixNano())
	m.mu.Lock()
	m.state.Phase = PhaseUpgrading
	m.state.OperationID = opID
	m.state.OperationStarted = time.Now().Unix()
	m.state.RecentLog = m.state.RecentLog[:0]
	m.state.Error = nil
	m.mu.Unlock()
	m.markDirty()

	onLine := func(line string) { m.appendLog(line) }
	argv := wrapInTerminal(term, title, command, opts.TerminalArgs)
	if err := Run(ctx, argv, RunOptions{OnLine: onLine}); err != nil {
		switch {
		case errors.Is(ctx.Err(), context.DeadlineExceeded):
			m.failCustomUpgrade(ErrCodeTimeout, err)
			return
		case errors.Is(ctx.Err(), context.Canceled):
			m.stopUpgrade(nil, true)
			return
		}
		m.failCustomUpgrade(ErrCodeBackendFailed, err)
		return
	}

	m.mu.RLock()
	installed := append([]Package(nil), m.state.Packages...)
	m.mu.RUnlock()
	m.finishSuccessfulUpgrade(false, installed)
	m.runRefresh(context.Background(), false)
}

func interactiveUpgradeCommand(exe string, opts UpgradeOptions) string {
	parts := []string{"'" + strings.ReplaceAll(exe, "'", `'\''`) + "'", "system", "update", "--interactive"}
	if !opts.IncludeFlatpak {
		parts = append(parts, "--no-flatpak")
	}
	if !opts.IncludeAUR {
		parts = append(parts, "--no-aur")
	}
	if ignored := shellSafeNames(opts.Ignored); len(ignored) > 0 {
		parts = append(parts, "--ignore", strings.Join(ignored, ","))
	}
	return strings.Join(parts, " ")
}

func (m *Manager) failCustomUpgrade(code ErrorCode, err error) {
	m.mu.Lock()
	m.state.Phase = PhaseError
	m.state.Error = &ErrorInfo{Code: code, Message: err.Error()}
	m.mu.Unlock()
	m.markDirty()
}

// A cancel or a dismissed password prompt is the user's choice, not a failure.
func (m *Manager) stopUpgrade(installed []Package, refresh bool) {
	m.appendLog("Upgrade stopped.")
	m.mu.Lock()
	m.state.Phase = PhaseIdle
	m.state.OperationID = ""
	m.state.OperationStarted = 0
	if names := rebootPackages(installed); len(names) > 0 {
		m.state.Reboot = RebootInfo{Recommended: true, Packages: names}
	}
	persist := m.persistedLocked()
	m.mu.Unlock()
	savePersisted(persist)
	m.markDirty()
	// Packages may have landed before the stop, so the cached list is stale.
	if refresh {
		m.runRefresh(context.Background(), false)
	}
}

func (m *Manager) finishSuccessfulUpgrade(clearPackages bool, installed []Package) {
	m.appendLog("Upgrade complete.")

	timer := time.NewTimer(postUpgradeCompleteDelay)
	defer timer.Stop()

	select {
	case <-m.stopChan:
		return
	case <-timer.C:
	}

	m.mu.Lock()
	m.state.Phase = PhaseIdle
	m.state.OperationID = ""
	m.state.OperationStarted = 0
	if clearPackages {
		m.state.Packages = m.state.Packages[:0]
		m.state.Count = 0
		m.state.Shell.UpdatePackage = nil
	}
	if names := rebootPackages(installed); len(names) > 0 {
		m.state.Reboot = RebootInfo{Recommended: true, Packages: names}
	}
	persist := m.persistedLocked()
	m.mu.Unlock()
	savePersisted(persist)
	m.markDirty()
	lowprio.Go(m.probeShell)
}

func (m *Manager) persistedLocked() persistedState {
	p := persistedState{LastCheckUnix: m.state.LastCheckUnix, LastSuccessUnix: m.state.LastSuccessUnix, Packages: m.state.Packages}
	if m.state.Reboot.Recommended {
		p.RebootBootID = bootID()
		p.RebootPackages = m.state.Reboot.Packages
	}
	return p
}

func dropIgnoredTargets(targets []Package, ignored []string) []Package {
	if len(ignored) == 0 {
		return targets
	}
	skip := make(map[string]bool, len(ignored))
	for _, name := range ignored {
		skip[name] = true
	}
	out := targets[:0]
	for _, p := range targets {
		if skip[p.Name] {
			continue
		}
		out = append(out, p)
	}
	return out
}

func upgradeBackends(sel Selection, opts UpgradeOptions) []Backend {
	var out []Backend
	if sel.System != nil {
		out = appendUpgradeBackend(out, sel.System, opts)
	}
	for _, b := range sel.Overlay {
		switch {
		case b.Repo() == RepoFlatpak && !opts.IncludeFlatpak:
			continue
		}
		out = appendUpgradeBackend(out, b, opts)
	}
	return out
}

func appendUpgradeBackend(out []Backend, b Backend, opts UpgradeOptions) []Backend {
	if !BackendHasTargets(b, opts.Targets, opts.IncludeAUR, opts.IncludeFlatpak) {
		return out
	}
	return append(out, b)
}

func (m *Manager) appendLog(line string) {
	m.mu.Lock()
	if cap(m.state.RecentLog) == 0 {
		m.state.RecentLog = make([]string, 0, recentLogCapacity)
	}
	if len(m.state.RecentLog) >= recentLogCapacity {
		copy(m.state.RecentLog, m.state.RecentLog[1:])
		m.state.RecentLog = m.state.RecentLog[:recentLogCapacity-1]
	}
	m.state.RecentLog = append(m.state.RecentLog, line)
	m.mu.Unlock()
	m.markDirty()
}

func (m *Manager) setError(code ErrorCode, msg string) {
	m.mu.Lock()
	m.state.Phase = PhaseError
	m.state.Error = &ErrorInfo{Code: code, Message: msg}
	m.mu.Unlock()
	m.markDirty()
}

func (m *Manager) markDirty() {
	select {
	case m.notifyDirty <- struct{}{}:
	default:
	}
}

func (m *Manager) notifier() {
	defer m.notifierWG.Done()
	for {
		select {
		case <-m.stopChan:
			return
		case <-m.notifyDirty:
			snap := m.GetState()
			m.subscribers.Range(func(key string, ch chan State) bool {
				select {
				case ch <- snap:
				default:
				}
				return true
			})
		}
	}
}

func cloneState(s State) State {
	out := s
	out.Backends = append([]BackendInfo(nil), s.Backends...)
	out.Packages = append([]Package(nil), s.Packages...)
	out.RecentLog = append([]string(nil), s.RecentLog...)
	out.Reboot.Packages = append([]string(nil), s.Reboot.Packages...)
	if s.Error != nil {
		errCopy := *s.Error
		out.Error = &errCopy
	}
	if s.Shell.UpdatePackage != nil {
		pkg := *s.Shell.UpdatePackage
		out.Shell.UpdatePackage = &pkg
	}
	if s.Shell.CommitsBehind != nil {
		n := *s.Shell.CommitsBehind
		out.Shell.CommitsBehind = &n
	}
	return out
}

func readOSRelease() (id, pretty string) {
	f, err := os.Open("/etc/os-release")
	if err != nil {
		return "", ""
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		k, v, ok := strings.Cut(scanner.Text(), "=")
		if !ok {
			continue
		}
		v = strings.Trim(v, "\"")
		switch k {
		case "ID":
			id = v
		case "PRETTY_NAME":
			pretty = v
		}
	}
	if err := scanner.Err(); err != nil {
		log.Debugf("[sysupdate] read os-release: %v", err)
	}
	return id, pretty
}
