package freedesktop

import (
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSetScreenLockActive_NoChangeNoDuplicate(t *testing.T) {
	ch := make(chan ScreensaverState, 64)
	manager := &Manager{
		state: &FreedeskState{
			Screensaver: ScreensaverState{Available: true, Active: false},
		},
		stateMutex: sync.RWMutex{},
	}
	manager.screensaverSubscribers.Store("test", ch)
	defer manager.screensaverSubscribers.Delete("test")

	// Setting to same value should not notify
	manager.SetScreenLockActive(false)

	select {
	case <-ch:
		t.Fatal("should not have received notification for no-change")
	default:
	}
}

func TestSetScreenLockActive_NotifiesSubscribers(t *testing.T) {
	ch := make(chan ScreensaverState, 64)
	manager := &Manager{
		state: &FreedeskState{
			Screensaver: ScreensaverState{Available: true, Active: false},
		},
		stateMutex: sync.RWMutex{},
	}
	manager.screensaverSubscribers.Store("test", ch)
	defer manager.screensaverSubscribers.Delete("test")

	manager.SetScreenLockActive(true)

	select {
	case state := <-ch:
		assert.True(t, state.Active)
	default:
		t.Fatal("subscriber was not notified")
	}
}
