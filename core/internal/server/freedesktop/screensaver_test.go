package freedesktop

import (
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSetScreenLockActive_NoChangeNoDuplicate(t *testing.T) {
	manager := &Manager{
		state: &FreedeskState{
			Screensaver: ScreensaverState{Available: true, Active: false},
		},
		stateMutex: sync.RWMutex{},
	}
	ch := manager.SubscribeScreensaver("test")
	defer manager.UnsubscribeScreensaver("test", ch)

	// Setting to same value should not notify
	manager.SetScreenLockActive(false)

	select {
	case <-ch:
		t.Fatal("should not have received notification for no-change")
	default:
	}
}

func TestSetScreenLockActive_NotifiesSubscribers(t *testing.T) {
	manager := &Manager{
		state: &FreedeskState{
			Screensaver: ScreensaverState{Available: true, Active: false},
		},
		stateMutex: sync.RWMutex{},
	}
	ch := manager.SubscribeScreensaver("test")
	defer manager.UnsubscribeScreensaver("test", ch)

	manager.SetScreenLockActive(true)

	select {
	case state := <-ch:
		assert.True(t, state.Active)
	default:
		t.Fatal("subscriber was not notified")
	}
}
