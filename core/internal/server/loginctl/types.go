package loginctl

import (
	"os"
	"sync"
	"sync/atomic"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/godbus/dbus/v5"
)

type SessionState struct {
	SessionID         string `json:"sessionId"`
	SessionPath       string `json:"sessionPath"`
	Locked            bool   `json:"locked"`
	Active            bool   `json:"active"`
	IdleHint          bool   `json:"idleHint"`
	IdleSinceHint     uint64 `json:"idleSinceHint"`
	LockedHint        bool   `json:"lockedHint"`
	SessionType       string `json:"sessionType"`
	SessionClass      string `json:"sessionClass"`
	User              uint32 `json:"user"`
	UserName          string `json:"userName"`
	RemoteHost        string `json:"remoteHost"`
	Service           string `json:"service"`
	TTY               string `json:"tty"`
	Display           string `json:"display"`
	Remote            bool   `json:"remote"`
	Seat              string `json:"seat"`
	VTNr              uint32 `json:"vtnr"`
	PreparingForSleep bool   `json:"preparingForSleep"`
}

type EventType string

const (
	EventStateChanged EventType = "state_changed"
)

type SessionEvent struct {
	Type EventType    `json:"type"`
	Data SessionState `json:"data"`
}

type Manager struct {
	state                 *SessionState
	stateMutex            sync.RWMutex
	subscribers           syncmap.Map[string, chan SessionState]
	stopChan              chan struct{}
	conn                  *dbus.Conn
	sessionPath           dbus.ObjectPath
	managerObj            dbus.BusObject
	sessionObj            dbus.BusObject
	dirty                 chan struct{}
	notifierWg            sync.WaitGroup
	lastNotifiedState     *SessionState
	signals               chan *dbus.Signal
	sigWG                 sync.WaitGroup
	inhibitMu             sync.Mutex
	inhibitFile           *os.File
	keepAwakeMu           sync.Mutex
	keepAwakeFile         *os.File
	lockBeforeSuspend     atomic.Bool
	inSleepCycle          atomic.Bool
	sleepCycleID          atomic.Uint64
	prelockedReady        atomic.Bool
	lockerReadyChMu       sync.Mutex
	lockerReadyCh         chan struct{}
	lockTimerMu           sync.Mutex
	lockTimer             *time.Timer
	sleepInhibitorEnabled atomic.Bool
	fallbackDelay         time.Duration
	keepLockOnUnlock      bool
}
