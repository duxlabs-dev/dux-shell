package clipboard

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/godbus/dbus/v5"
	bolt "go.etcd.io/bbolt"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wlcontext"
)

const largeEntryBytes = 1 << 20

type Config struct {
	MaxHistory     int   `json:"maxHistory"`
	MaxEntrySize   int64 `json:"maxEntrySize"`
	AutoClearDays  int   `json:"autoClearDays"`
	ClearAtStartup bool  `json:"clearAtStartup"`
	Disabled       bool  `json:"disabled"`
	MaxPinned      int   `json:"maxPinned"`
}

func DefaultConfig() Config {
	return Config{
		MaxHistory:     100,
		MaxEntrySize:   5 * 1024 * 1024,
		AutoClearDays:  0,
		ClearAtStartup: false,
		MaxPinned:      25,
	}
}

func getConfigPath() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(configDir, "dms", "clsettings.json"), nil
}

func LoadConfig() Config {
	cfg, err := readConfig()
	if err != nil {
		return DefaultConfig()
	}
	return cfg
}

func readConfig() (Config, error) {
	cfg := DefaultConfig()

	path, err := getConfigPath()
	if err != nil {
		return cfg, err
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return cfg, err
	}

	if err := json.Unmarshal(data, &cfg); err != nil {
		return DefaultConfig(), err
	}
	return cfg, nil
}

func SaveConfig(cfg Config) error {
	path, err := getConfigPath()
	if err != nil {
		return err
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(path, data, 0o644)
}

type SearchParams struct {
	Query    string `json:"query"`
	MimeType string `json:"mimeType"`
	IsImage  *bool  `json:"isImage"`
	Limit    int    `json:"limit"`
	Offset   int    `json:"offset"`
	Before   *int64 `json:"before"`
	After    *int64 `json:"after"`
}

type SearchResult struct {
	Entries []Entry `json:"entries"`
	Total   int     `json:"total"`
	HasMore bool    `json:"hasMore"`
}

type Entry struct {
	ID          uint64    `json:"id"`
	Data        []byte    `json:"data,omitempty"`
	MimeType    string    `json:"mimeType"`
	Preview     string    `json:"preview"`
	Size        int       `json:"size"`
	Timestamp   time.Time `json:"timestamp"`
	IsImage     bool      `json:"isImage"`
	Hash        uint64    `json:"hash,omitempty"`
	Pinned      bool      `json:"pinned"`
	AltData     []byte    `json:"altData,omitempty"`
	AltMimeType string    `json:"altMimeType,omitempty"`
}

type State struct {
	Enabled bool    `json:"enabled"`
	History []Entry `json:"history"`
	Current *Entry  `json:"current,omitempty"`
}

type Manager struct {
	config      Config
	configMutex sync.RWMutex
	configPath  string

	display wlclient.WaylandDisplay
	wlCtx   wlcontext.WaylandContext

	registry       *wlclient.Registry
	dataControlMgr any
	seat           *wlclient.Seat
	dataDevice     any
	currentOffer   any
	currentSource  any
	seatName       uint32
	mimeTypes      []string
	offerMimeTypes map[any][]string
	offerMutex     sync.RWMutex

	isOwner        bool
	ownerLock      sync.Mutex
	pasteSupported bool

	initialized bool
	deviceBound atomic.Bool

	alive    bool
	stopChan chan struct{}

	db     *bolt.DB
	dbPath string

	state      *State
	stateMutex sync.RWMutex

	subscribers map[string]chan State
	subMutex    sync.RWMutex
	dirty       chan struct{}
	notifierWg  sync.WaitGroup
	lastState   *State

	// lazily created by dbusConnForFlatpak under dbusConnMutex
	dbusConn      *dbus.Conn
	dbusConnMutex sync.Mutex
}

func (m *Manager) GetState() State {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	if m.state == nil {
		return State{}
	}
	return *m.state
}

func (m *Manager) Subscribe(id string) chan State {
	ch := make(chan State, 64)
	m.subMutex.Lock()
	m.subscribers[id] = ch
	m.subMutex.Unlock()
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	m.subMutex.Lock()
	if ch, ok := m.subscribers[id]; ok {
		close(ch)
		delete(m.subscribers, id)
	}
	m.subMutex.Unlock()
}

func (m *Manager) notifySubscribers() {
	select {
	case m.dirty <- struct{}{}:
	default:
	}
}
