package notifyactions

import (
	"testing"

	"github.com/godbus/dbus/v5"
)

func TestUnrelatedOwnerChangeKeepsWatchers(t *testing.T) {
	m := &Manager{signals: make(chan *dbus.Signal), watched: map[uint32]watched{7: {path: "/tmp/x"}}}
	done := make(chan struct{})
	go func() {
		m.loop()
		close(done)
	}()

	m.signals <- &dbus.Signal{Name: ownerChanged, Body: []any{"org.example.Other", ":1.2", ":1.3"}}
	m.signals <- &dbus.Signal{Name: ownerChanged, Body: []any{notifyInterface, ":1.4", ":1.5"}}
	close(m.signals)
	<-done

	if _, ok := m.watched[7]; ok {
		t.Fatal("notification server restart did not clear watchers")
	}
}

func TestUnrelatedOwnerChangeAlone(t *testing.T) {
	m := &Manager{signals: make(chan *dbus.Signal), watched: map[uint32]watched{7: {path: "/tmp/x"}}}
	done := make(chan struct{})
	go func() {
		m.loop()
		close(done)
	}()

	m.signals <- &dbus.Signal{Name: ownerChanged, Body: []any{"org.example.Other", ":1.2", ":1.3"}}
	close(m.signals)
	<-done

	if _, ok := m.watched[7]; !ok {
		t.Fatal("an unrelated NameOwnerChanged cleared the watchers")
	}
}
