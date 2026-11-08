package network

import (
	"errors"
	"testing"

	mock_dbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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

func TestApplyPreferenceToProfile(t *testing.T) {
	const wifi, eth = "802-11-wireless", "802-3-ethernet"
	tests := []struct {
		name, typ, mode string
		pref            ConnectionPreference
		metric          int64
		prio            int32
		updateErr       error
		wantChange      bool
		wantMetric      int64
		wantPrio        int32
	}{
		{"preferred wifi", wifi, "infrastructure", PreferenceWiFi, -1, 0, nil, true, 100, 0},
		{"demoted ethernet", eth, "", PreferenceWiFi, -1, 0, nil, true, 300, 0},
		{"hotspot left", wifi, "ap", PreferenceWiFi, -1, 0, nil, false, 0, 0},
		{"user metric left", eth, "", PreferenceEthernet, 50, 0, nil, false, 0, 0},
		{"auto resets metric and priority", wifi, "infrastructure", PreferenceAuto, 100, 10, nil, true, -1, 0},
		{"auto leaves defaults and generated priority", eth, "", PreferenceAuto, -1, -999, nil, false, 0, 0},
		{"auto with user metric next to DMS priority", wifi, "infrastructure", PreferenceAuto, 50, 10, nil, true, 50, 0},
		{"user priority under non-auto preference", eth, "", PreferenceWiFi, -1, 7, nil, true, 300, 7},
		{"update error names the profile", eth, "", PreferenceWiFi, -1, 0, errors.New("denied"), false, 0, 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			stored := nmSettings{
				"connection":      {"id": dbus.MakeVariant("home"), "type": dbus.MakeVariant(tt.typ), "autoconnect-priority": dbus.MakeVariant(tt.prio)},
				"802-11-wireless": {"mode": dbus.MakeVariant(tt.mode)},
				"ipv4":            {"route-metric": dbus.MakeVariant(tt.metric)},
				"ipv6":            {"route-metric": dbus.MakeVariant(tt.metric)},
			}
			obj := mock_dbus.NewMockBusObject(t)
			expectGetSettings(obj, stored)
			var got *nmSettings
			if tt.wantChange || tt.updateErr != nil {
				expectGetSettings(obj, stored)
				got = captureUpdate2(obj, nmUpdate2FlagToDisk, tt.updateErr)
			}

			changed, err := applyPreferenceToProfile(obj, tt.pref)
			assert.Equal(t, tt.wantChange, changed)
			if tt.updateErr != nil {
				assert.ErrorContains(t, err, "home: ")
				return
			}
			require.NoError(t, err)
			if tt.wantChange {
				assert.Equal(t, tt.wantMetric, (*got)["ipv4"]["route-metric"].Value())
				assert.Equal(t, tt.wantMetric, (*got)["ipv6"]["route-metric"].Value())
				assert.Equal(t, tt.wantPrio, (*got)["connection"]["autoconnect-priority"].Value())
			}
		})
	}
}
