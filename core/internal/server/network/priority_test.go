package network

import (
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
)

func TestManager_SetConnectionPreference(t *testing.T) {
	t.Run("invalid preference", func(t *testing.T) {
		manager := &Manager{
			state: &NetworkState{
				Preference: PreferenceAuto,
			},
		}

		err := manager.SetConnectionPreference(ConnectionPreference("invalid"))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "invalid preference")
	})
}

func TestProfileAtDefaultsMatchesAutoTargets(t *testing.T) {
	assert.True(t, priorityMatches(dbus.Variant{}, int64(priorityDefault)))
	assert.True(t, routeMetricMatches(nil, metricDefault))
	assert.True(t, routeMetricMatches(map[string]dbus.Variant{"method": dbus.MakeVariant("auto")}, metricDefault))
	assert.False(t, routeMetricMatches(map[string]dbus.Variant{"route-metric": dbus.MakeVariant(int64(100))}, metricDefault))
	assert.False(t, priorityMatches(dbus.MakeVariant(int32(100)), int64(priorityDefault)))
}
