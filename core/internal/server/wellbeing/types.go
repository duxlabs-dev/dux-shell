package wellbeing

import (
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	bolt "go.etcd.io/bbolt"
)

const (
	flushInterval = time.Minute
	// a gap longer than this between credits means the process was frozen (suspend); nothing is counted for it
	maxCreditGap  = 2 * flushInterval
	retentionDays = 92
	dateLayout    = "2006-01-02"
)

type DayUsage struct {
	Date   string           `json:"date"`
	Active int64            `json:"active"`
	Apps   map[string]int64 `json:"apps"`
}

type Limits struct {
	Daily int64            `json:"daily"`
	Apps  map[string]int64 `json:"apps"`
}

type LimitEvent struct {
	Kind  string `json:"kind"`
	AppID string `json:"appId,omitempty"`
	Used  int64  `json:"used"`
	Limit int64  `json:"limit"`
}

type State struct {
	Today  DayUsage    `json:"today"`
	Limit  *LimitEvent `json:"limit,omitempty"`
	Resync bool        `json:"resync,omitempty"`
}

type segment struct {
	AppID  string `json:"appId"`
	Active bool   `json:"active"`
	Since  int64  `json:"since"`
}

type alertRecord struct {
	Date string   `json:"date"`
	Keys []string `json:"keys"`
}

type Manager struct {
	mu        sync.Mutex
	db        *bolt.DB
	now       func() time.Time
	cur       segment
	seq       int64
	limits    Limits
	limitsSet bool
	alerted   alertRecord

	subscribers syncmap.Map[string, chan State]
	wake        chan struct{}
	stopChan    chan struct{}
	wg          sync.WaitGroup
}
