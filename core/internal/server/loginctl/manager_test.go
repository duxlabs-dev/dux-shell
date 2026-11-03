package loginctl

import (
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestManager_Unsubscribe(t *testing.T) {
	manager := &Manager{
		state: &SessionState{},
	}

	ch := manager.Subscribe("test-client")

	manager.Unsubscribe("test-client")

	_, ok := <-ch
	assert.False(t, ok)

	_, exists := manager.subscribers.Load("test-client")
	assert.False(t, exists)
}

func TestManager_Unsubscribe_NonExistent(t *testing.T) {
	manager := &Manager{
		state: &SessionState{},
	}

	// Unsubscribe a non-existent client should not panic
	assert.NotPanics(t, func() {
		manager.Unsubscribe("non-existent")
	})
}

func TestManager_Close(t *testing.T) {
	manager := &Manager{
		state:      &SessionState{},
		stateMutex: sync.RWMutex{},
		stopChan:   make(chan struct{}),
	}

	ch1 := make(chan SessionState, 1)
	ch2 := make(chan SessionState, 1)
	manager.subscribers.Store("client1", ch1)
	manager.subscribers.Store("client2", ch2)

	manager.Close()

	select {
	case <-manager.stopChan:
	case <-time.After(100 * time.Millisecond):
		t.Fatal("stopChan not closed")
	}

	_, ok1 := <-ch1
	_, ok2 := <-ch2
	assert.False(t, ok1, "ch1 should be closed")
	assert.False(t, ok2, "ch2 should be closed")

	count := 0
	manager.subscribers.Range(func(key string, ch chan SessionState) bool {
		count++
		return true
	})
	assert.Equal(t, 0, count)
}

func TestStateChangedMeaningfully(t *testing.T) {
	tests := []struct {
		name     string
		old      *SessionState
		new      *SessionState
		expected bool
	}{
		{
			name:     "no change",
			old:      &SessionState{Locked: false, Active: true, IdleHint: false},
			new:      &SessionState{Locked: false, Active: true, IdleHint: false},
			expected: false,
		},
		{
			name:     "locked changed",
			old:      &SessionState{Locked: false, Active: true, IdleHint: false},
			new:      &SessionState{Locked: true, Active: true, IdleHint: false},
			expected: true,
		},
		{
			name:     "active changed",
			old:      &SessionState{Locked: false, Active: true, IdleHint: false},
			new:      &SessionState{Locked: false, Active: false, IdleHint: false},
			expected: true,
		},
		{
			name:     "idle hint changed",
			old:      &SessionState{Locked: false, Active: true, IdleHint: false},
			new:      &SessionState{Locked: false, Active: true, IdleHint: true},
			expected: true,
		},
		{
			name:     "locked hint changed",
			old:      &SessionState{Locked: false, Active: true, LockedHint: false},
			new:      &SessionState{Locked: false, Active: true, LockedHint: true},
			expected: true,
		},
		{
			name:     "preparing for sleep changed",
			old:      &SessionState{Locked: false, Active: true, PreparingForSleep: false},
			new:      &SessionState{Locked: false, Active: true, PreparingForSleep: true},
			expected: true,
		},
		{
			name:     "non-meaningful change (username)",
			old:      &SessionState{Locked: false, Active: true, UserName: "user1"},
			new:      &SessionState{Locked: false, Active: true, UserName: "user2"},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := stateChangedMeaningfully(tt.old, tt.new)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestManager_ApplyLockPolicy(t *testing.T) {
	on, off := true, false
	tests := []struct {
		name                  string
		policy                LockPolicy
		lockBeforeSuspend     bool
		sleepInhibitorEnabled bool
	}{
		{name: "unmanaged", sleepInhibitorEnabled: true},
		{name: "lock before suspend managed on", policy: LockPolicy{LockBeforeSuspend: &on}, lockBeforeSuspend: true, sleepInhibitorEnabled: true},
		{name: "both managed on", policy: LockPolicy{LockBeforeSuspend: &on, LoginctlLockIntegration: &on}, lockBeforeSuspend: true, sleepInhibitorEnabled: true},
		{name: "lock before suspend managed off", policy: LockPolicy{LockBeforeSuspend: &off}},
		{name: "integration managed off", policy: LockPolicy{LockBeforeSuspend: &on, LoginctlLockIntegration: &off}, lockBeforeSuspend: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager := &Manager{lockPolicy: tt.policy}
			manager.applyLockPolicy()
			assert.Equal(t, tt.lockBeforeSuspend, manager.lockBeforeSuspend.Load())
			assert.Equal(t, tt.sleepInhibitorEnabled, manager.sleepInhibitorEnabled.Load())
		})
	}
}
