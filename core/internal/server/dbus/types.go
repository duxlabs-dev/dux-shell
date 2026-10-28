package dbus

import (
	"sync"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/godbus/dbus/v5"
)

type Manager struct {
	systemConn     *dbus.Conn
	sessionConn    *dbus.Conn
	systemSignals  chan *dbus.Signal
	sessionSignals chan *dbus.Signal

	subscriptions     syncmap.Map[string, *signalSubscription]
	subscribersMu     sync.Mutex
	signalSubscribers syncmap.Map[string, chan SignalEvent]
	owners            syncmap.Map[*ipc.ConnWriter, struct{}]
}

type signalSubscription struct {
	Bus       string
	Sender    string
	Path      string
	Interface string
	Member    string
	ClientID  string
	Owner     *ipc.ConnWriter
}

type SignalEvent struct {
	SubscriptionID string `json:"subscriptionId"`
	Sender         string `json:"sender"`
	Path           string `json:"path"`
	Interface      string `json:"interface"`
	Member         string `json:"member"`
	Body           []any  `json:"body"`
}

type CallResult struct {
	Values []any `json:"values"`
}

type PropertyResult struct {
	Value any `json:"value"`
}

type IntrospectResult struct {
	XML string `json:"xml"`
}

type ListNamesResult struct {
	Names []string `json:"names"`
}

type SubscribeResult struct {
	SubscriptionID string `json:"subscriptionId"`
}
