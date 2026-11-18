package globalshortcuts

import (
	"context"
	"slices"
	"strconv"
	"strings"
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/pubsub"
)

type pendingPrompt struct {
	prompt Prompt
	answer chan []Shortcut
}

type Manager struct {
	mu          sync.Mutex
	path        string
	apps        []App
	pending     []*pendingPrompt
	lastToken   uint64
	rebind      func(App)
	subscribers pubsub.Broker[State]
}

func NewManager() (*Manager, error) {
	path, err := storePath()
	if err != nil {
		return nil, err
	}
	apps, err := loadApps(path)
	if err != nil {
		log.Warnf("Global shortcuts store unreadable, starting empty: %v", err)
	}
	return &Manager{path: path, apps: apps}, nil
}

func (m *Manager) SetRebinder(rebind func(App)) {
	m.mu.Lock()
	m.rebind = rebind
	m.mu.Unlock()
}

func (m *Manager) Bind(ctx context.Context, appID string, requested []Shortcut) ([]Shortcut, error) {
	m.mu.Lock()
	offer, hasNew := mergeRequested(m.shortcutsLocked(appID), requested)
	m.mu.Unlock()

	if hasNew {
		return m.ask(ctx, PromptBind, appID, offer)
	}
	m.remember(appID, offer)
	return offer, nil
}

func (m *Manager) Configure(ctx context.Context, appID string) ([]Shortcut, error) {
	saved := m.savedShortcuts(appID)
	if len(saved) == 0 {
		return nil, nil
	}
	return m.ask(ctx, PromptConfigure, appID, saved)
}

func (m *Manager) SetTriggers(appID, shortcutID string, triggers []string) error {
	m.mu.Lock()
	shortcuts := slices.Clone(m.shortcutsLocked(appID))
	index := slices.IndexFunc(shortcuts, func(shortcut Shortcut) bool { return shortcut.ID == shortcutID })
	if index < 0 {
		m.mu.Unlock()
		return ErrUnknownShortcut
	}
	shortcuts[index].Triggers = cleanTriggers(triggers)
	m.setShortcutsLocked(appID, shortcuts)
	m.persistLocked()
	m.mu.Unlock()

	m.publish()
	m.notifyRebinder(App{ID: appID, Shortcuts: shortcuts})
	return nil
}

func (m *Manager) Remove(appID string) error {
	m.mu.Lock()
	index := m.appIndexLocked(appID)
	if index < 0 {
		m.mu.Unlock()
		return ErrUnknownApp
	}
	m.apps = slices.Delete(m.apps, index, index+1)
	m.persistLocked()
	m.mu.Unlock()

	m.publish()
	m.notifyRebinder(App{ID: appID})
	return nil
}

func (m *Manager) Submit(token string, edits []TriggerEdit) error {
	m.mu.Lock()
	pending := m.takePendingLocked(token)
	if pending == nil {
		m.mu.Unlock()
		return ErrUnknownPrompt
	}
	shortcuts := applyEdits(pending.prompt.Shortcuts, edits)
	m.setShortcutsLocked(pending.prompt.AppID, shortcuts)
	m.persistLocked()
	m.mu.Unlock()

	pending.answer <- shortcuts
	m.publish()
	return nil
}

func (m *Manager) Cancel(token string) error {
	m.mu.Lock()
	pending := m.takePendingLocked(token)
	m.mu.Unlock()
	if pending == nil {
		return ErrUnknownPrompt
	}

	close(pending.answer)
	m.publish()
	return nil
}

func (m *Manager) GetState() State {
	m.mu.Lock()
	defer m.mu.Unlock()

	state := State{
		Apps:    make([]App, len(m.apps)),
		Prompts: make([]Prompt, len(m.pending)),
	}
	copy(state.Apps, m.apps)
	for i, pending := range m.pending {
		state.Prompts[i] = pending.prompt
	}
	return state
}

func (m *Manager) Subscribe(id string) chan State {
	return m.subscribers.Subscribe(id)
}

func (m *Manager) Unsubscribe(id string, ch chan State) {
	m.subscribers.Unsubscribe(id, ch)
}

func (m *Manager) Close() {
	m.subscribers.Close()
}

func (m *Manager) ask(ctx context.Context, kind PromptKind, appID string, offer []Shortcut) ([]Shortcut, error) {
	pending := m.enqueue(kind, appID, offer)
	m.publish()

	select {
	case shortcuts, answered := <-pending.answer:
		if !answered {
			return nil, ErrDenied
		}
		return shortcuts, nil
	case <-ctx.Done():
		m.mu.Lock()
		m.takePendingLocked(pending.prompt.Token)
		m.mu.Unlock()
		m.publish()
		return nil, ctx.Err()
	}
}

func (m *Manager) enqueue(kind PromptKind, appID string, offer []Shortcut) *pendingPrompt {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.pending = slices.DeleteFunc(m.pending, func(stale *pendingPrompt) bool {
		if stale.prompt.AppID != appID {
			return false
		}
		close(stale.answer)
		return true
	})

	m.lastToken++
	pending := &pendingPrompt{
		prompt: Prompt{
			Token:     strconv.FormatUint(m.lastToken, 10),
			Kind:      kind,
			AppID:     appID,
			Shortcuts: offer,
		},
		answer: make(chan []Shortcut, 1),
	}
	m.pending = append(m.pending, pending)
	return pending
}

func (m *Manager) remember(appID string, shortcuts []Shortcut) {
	m.mu.Lock()
	if slices.EqualFunc(m.shortcutsLocked(appID), shortcuts, sameShortcut) {
		m.mu.Unlock()
		return
	}
	m.setShortcutsLocked(appID, shortcuts)
	m.persistLocked()
	m.mu.Unlock()

	m.publish()
}

func (m *Manager) savedShortcuts(appID string) []Shortcut {
	m.mu.Lock()
	defer m.mu.Unlock()
	return slices.Clone(m.shortcutsLocked(appID))
}

func (m *Manager) notifyRebinder(app App) {
	m.mu.Lock()
	rebind := m.rebind
	m.mu.Unlock()
	if rebind == nil {
		return
	}
	rebind(app)
}

func (m *Manager) publish() {
	m.subscribers.Publish(m.GetState())
}

func (m *Manager) appIndexLocked(appID string) int {
	return slices.IndexFunc(m.apps, func(app App) bool { return app.ID == appID })
}

func (m *Manager) shortcutsLocked(appID string) []Shortcut {
	index := m.appIndexLocked(appID)
	if index < 0 {
		return nil
	}
	return m.apps[index].Shortcuts
}

func (m *Manager) setShortcutsLocked(appID string, shortcuts []Shortcut) {
	index := m.appIndexLocked(appID)
	if index < 0 {
		m.apps = append(m.apps, App{ID: appID, Shortcuts: shortcuts})
		return
	}
	m.apps[index].Shortcuts = shortcuts
}

func (m *Manager) persistLocked() {
	if err := saveApps(m.path, m.apps); err != nil {
		log.Warnf("Failed to save global shortcuts: %v", err)
	}
}

func (m *Manager) takePendingLocked(token string) *pendingPrompt {
	index := slices.IndexFunc(m.pending, func(pending *pendingPrompt) bool { return pending.prompt.Token == token })
	if index < 0 {
		return nil
	}
	pending := m.pending[index]
	m.pending = slices.Delete(m.pending, index, index+1)
	return pending
}

func mergeRequested(saved, requested []Shortcut) ([]Shortcut, bool) {
	offer := make([]Shortcut, 0, len(requested))
	hasNew := false
	for _, shortcut := range requested {
		shortcut.Preferred = shortcut.Triggers
		index := slices.IndexFunc(saved, func(known Shortcut) bool { return known.ID == shortcut.ID })
		if index < 0 {
			hasNew = true
			offer = append(offer, shortcut)
			continue
		}
		shortcut.Triggers = saved[index].Triggers
		offer = append(offer, shortcut)
	}
	return offer, hasNew
}

func applyEdits(offer []Shortcut, edits []TriggerEdit) []Shortcut {
	shortcuts := make([]Shortcut, len(offer))
	for i, shortcut := range offer {
		index := slices.IndexFunc(edits, func(edit TriggerEdit) bool { return edit.ID == shortcut.ID })
		if index >= 0 {
			shortcut.Triggers = cleanTriggers(edits[index].Triggers)
		}
		shortcuts[i] = shortcut
	}
	return shortcuts
}

func cleanTriggers(triggers []string) []string {
	cleaned := make([]string, 0, len(triggers))
	for _, trigger := range triggers {
		trigger = strings.TrimSpace(trigger)
		if trigger == "" || slices.Contains(cleaned, trigger) {
			continue
		}
		cleaned = append(cleaned, trigger)
	}
	return cleaned
}

func sameShortcut(a, b Shortcut) bool {
	return a.ID == b.ID && a.Description == b.Description && slices.Equal(a.Triggers, b.Triggers) && slices.Equal(a.Preferred, b.Preferred)
}
