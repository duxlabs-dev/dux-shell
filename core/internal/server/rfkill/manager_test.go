//go:build linux

package rfkill

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestComputeState(t *testing.T) {
	devices := make(map[uint32]rfkillDevice)
	assert.Equal(t, State{Available: false, AirplaneMode: false}, computeState(devices))

	applyEvent(devices, 0, rfkillTypeWLAN, rfkillOpAdd, 0, 0)
	applyEvent(devices, 1, rfkillTypeBluetooth, rfkillOpAdd, 1, 0)
	// Only bluetooth is blocked -> not airplane mode
	assert.Equal(t, State{Available: true, AirplaneMode: false}, computeState(devices))

	// Both blocked -> airplane mode active
	applyEvent(devices, 0, rfkillTypeWLAN, rfkillOpChange, 1, 0)
	assert.Equal(t, State{Available: true, AirplaneMode: true}, computeState(devices))

	// Unblock all via CHANGE_ALL -> airplane mode off
	applyEvent(devices, 0, rfkillTypeAll, rfkillOpChangeAll, 0, 0)
	assert.Equal(t, State{Available: true, AirplaneMode: false}, computeState(devices))

	// Hard block on remaining device after deleting the other
	applyEvent(devices, 1, rfkillTypeBluetooth, rfkillOpDel, 0, 0)
	applyEvent(devices, 0, rfkillTypeWLAN, rfkillOpChange, 0, 1)
	assert.Equal(t, State{Available: true, AirplaneMode: true}, computeState(devices))
}

func TestBuildChangeAllEvent(t *testing.T) {
	assert.Equal(t, [rfkillEventSize]byte{0, 0, 0, 0, rfkillTypeAll, rfkillOpChangeAll, 1, 0}, buildChangeAllEvent(true))
	assert.Equal(t, [rfkillEventSize]byte{0, 0, 0, 0, rfkillTypeAll, rfkillOpChangeAll, 0, 0}, buildChangeAllEvent(false))
}
