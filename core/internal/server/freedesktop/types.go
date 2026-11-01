package freedesktop

import (
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/godbus/dbus/v5"
)

type colorSchemeEcho struct {
	value   uint32
	expires time.Time
}

type AccountsState struct {
	Available     bool   `json:"available"`
	UserPath      string `json:"userPath"`
	IconFile      string `json:"iconFile"`
	RealName      string `json:"realName"`
	UserName      string `json:"userName"`
	AccountType   int32  `json:"accountType"`
	HomeDirectory string `json:"homeDirectory"`
	Shell         string `json:"shell"`
	Email         string `json:"email"`
	Language      string `json:"language"`
	Location      string `json:"location"`
	Locked        bool   `json:"locked"`
	PasswordMode  int32  `json:"passwordMode"`
	UID           uint64 `json:"uid"`
}

type SettingsState struct {
	Available   bool   `json:"available"`
	ColorScheme uint32 `json:"colorScheme"`
}

type ScreensaverInhibitor struct {
	Cookie    uint32 `json:"cookie"`
	AppName   string `json:"appName"`
	Reason    string `json:"reason"`
	Peer      string `json:"peer"`
	StartTime int64  `json:"startTime"`
}

type ScreensaverState struct {
	Available  bool                   `json:"available"`
	Active     bool                   `json:"active"`
	Inhibited  bool                   `json:"inhibited"`
	Inhibitors []ScreensaverInhibitor `json:"inhibitors"`
}

type FreedeskState struct {
	Accounts    AccountsState    `json:"accounts"`
	Settings    SettingsState    `json:"settings"`
	Screensaver ScreensaverState `json:"screensaver"`
}

type Manager struct {
	state                         *FreedeskState
	stateMutex                    sync.RWMutex
	systemConn                    *dbus.Conn
	sessionConn                   *dbus.Conn
	accountsObj                   dbus.BusObject
	settingsObj                   dbus.BusObject
	currentUID                    uint64
	subscribers                   syncmap.Map[string, chan FreedeskState]
	screensaverSubscribers        syncmap.Map[string, chan ScreensaverState]
	screensaverCookieCounter      uint32
	screensaverFreedesktopClaimed bool
	screensaverGnomeClaimed       bool
	selfEchoMu                    sync.Mutex
	selfEchoes                    []colorSchemeEcho
	// registered on sessionConn by watchSettingsChanges; guarded by stateMutex
	settingsSignals chan *dbus.Signal
}
