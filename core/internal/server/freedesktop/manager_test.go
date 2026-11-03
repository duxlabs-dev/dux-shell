package freedesktop

import (
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestManager_Close(t *testing.T) {
	manager := &Manager{
		state:       &FreedeskState{},
		stateMutex:  sync.RWMutex{},
		systemConn:  nil,
		sessionConn: nil,
	}

	assert.NotPanics(t, func() {
		manager.Close()
	})
}

func TestManager_SelfEcho_ConsumesRegisteredWrites(t *testing.T) {
	manager := &Manager{state: &FreedeskState{}}

	manager.ExpectColorSchemeEcho("prefer-dark")
	manager.ExpectColorSchemeEcho("default")

	assert.True(t, manager.consumeSelfEcho(1))
	assert.True(t, manager.consumeSelfEcho(0))
	assert.False(t, manager.consumeSelfEcho(1))
	assert.False(t, manager.consumeSelfEcho(0))
}

func TestManager_SelfEcho_ExternalChangePassesThrough(t *testing.T) {
	manager := &Manager{state: &FreedeskState{}}

	manager.ExpectColorSchemeEcho("prefer-dark")

	assert.False(t, manager.consumeSelfEcho(2))
	assert.True(t, manager.consumeSelfEcho(1))
}

func TestManager_SelfEcho_ConsumesOnePerRegistration(t *testing.T) {
	manager := &Manager{state: &FreedeskState{}}

	manager.ExpectColorSchemeEcho("prefer-dark")
	manager.ExpectColorSchemeEcho("prefer-dark")

	assert.True(t, manager.consumeSelfEcho(1))
	assert.True(t, manager.consumeSelfEcho(1))
	assert.False(t, manager.consumeSelfEcho(1))
}

func TestManager_SelfEcho_SchemeMapping(t *testing.T) {
	manager := &Manager{state: &FreedeskState{}}

	manager.ExpectColorSchemeEcho("prefer-light")
	assert.True(t, manager.consumeSelfEcho(2))

	manager.ExpectColorSchemeEcho("default")
	assert.True(t, manager.consumeSelfEcho(0))
}
