package network

import (
	"errors"
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestConnectivity(t *testing.T) {
	const check = dbusNMInterface + ".CheckConnectivity"
	denied := dbus.Error{Name: "org.freedesktop.NetworkManager.PermissionDenied", Body: []any{"not allowed"}}
	tests := []struct {
		name string
		call dbus.Call
		run  func(*NetworkManagerBackend) (string, error)
		want string
		err  string
	}{
		{"check reports and stores the state", dbus.Call{Body: []any{uint32(3)}}, (*NetworkManagerBackend).CheckConnectivity, "limited", ""},
		{"check failure is returned", dbus.Call{Err: errors.New("checking disabled")}, (*NetworkManagerBackend).CheckConnectivity, "", "checking disabled"},
		{"enable denied is returned", dbus.Call{Err: denied}, func(b *NetworkManagerBackend) (string, error) { return "", b.SetConnectivityCheckEnabled(true) }, "", "not allowed"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := newEditorFixture(t)
			obj := f.object(t, dbusNMPath)
			if tt.err == "not allowed" {
				obj.EXPECT().Call(dbusPropsInterface+".Set", dbus.FlagAllowInteractiveAuthorization, dbusNMInterface, "ConnectivityCheckEnabled", dbus.MakeVariant(true)).Return(&tt.call).Once()
			} else {
				obj.EXPECT().Call(check, dbus.Flags(0)).Return(&tt.call).Once()
			}
			got, err := tt.run(f.backend)
			if tt.err != "" {
				require.ErrorContains(t, err, tt.err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
			assert.Equal(t, tt.want, f.backend.state.Connectivity)
		})
	}
}

func TestHandleNetworkManagerChange_Connectivity(t *testing.T) {
	f := newEditorFixture(t)
	for v, want := range map[uint32]string{1: "none", 2: "portal", 4: "full", 7: "unknown"} {
		f.backend.handleNetworkManagerChange(map[string]dbus.Variant{"Connectivity": dbus.MakeVariant(v)})
		assert.Equal(t, want, f.backend.state.Connectivity)
	}

	f.backend.handleNetworkManagerChange(map[string]dbus.Variant{
		"ConnectivityCheckEnabled": dbus.MakeVariant(true), "ConnectivityCheckAvailable": dbus.MakeVariant(true),
		"ConnectivityCheckUri": dbus.MakeVariant("http://example.test/check"),
	})
	st := f.backend.state
	assert.True(t, st.ConnectivityCheckEnabled && st.ConnectivityCheckAvailable)
	assert.Equal(t, "http://example.test/check", st.ConnectivityCheckURI)
}
