package network_test

import (
	"bytes"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"

	"github.com/duxlabs-dev/dux-go/ipc"
	mocks "github.com/duxlabs-dev/dux-shell/core/internal/mocks/network"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/network"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type editorBackend struct {
	*mocks.MockBackend
	*mocks.MockConnectionEditorBackend
}

func call(t *testing.T, m *network.Manager, method string, params map[string]any) (resp ipc.Response[json.RawMessage]) {
	srv, cli := net.Pipe()
	go func() {
		defer srv.Close()
		network.HandleRequest(ipc.NewConnWriter(srv), ipc.Request{ID: 7, Method: method, Params: params}, m)
	}()
	require.NoError(t, json.NewDecoder(cli).Decode(&resp))
	return resp
}
func newEditorManager(t *testing.T, mb *mocks.MockBackend) (*network.Manager, *mocks.MockConnectionEditorBackend) {
	ed := mocks.NewMockConnectionEditorBackend(t)
	return network.NewTestManager(&editorBackend{mb, ed}, &network.NetworkState{}), ed
}

type ex = mocks.MockConnectionEditorBackend_Expecter

func TestConnectionHandlers(t *testing.T) {
	isPatch := func(p network.SettingsPatch) bool { return len(p) == 3 && p["802-1x"]["identity"] == "bob" }
	cases := []struct {
		method string
		p      map[string]any
		setup  func(e *ex, err error)
		want   string
	}{
		{"network.connection.update", map[string]any{"uuid": "u1", "settings": map[string]any{"ipv4": map[string]any{"mtu": 1400}, "ipv6": nil, "802-1x": map[string]any{"identity": "stale"}}, "enterprise": map[string]any{"eap": "ttls", "phase2": "mschapv2", "identity": "bob", "ca": "file"}},
			func(e *ex, err error) {
				e.UpdateConnectionSettings("u1", mock.MatchedBy(isPatch), false).Return(err).Once()
			}, "connection updated"},
		{"network.connection.add", map[string]any{"settings": map[string]any{"connection": map[string]any{"type": "802-3-ethernet"}}}, func(e *ex, err error) { e.AddConnectionProfile(mock.Anything, true).Return("n1", err).Once() }, `"uuid":"n1"`},
		{"network.connection.list", nil, func(e *ex, err error) {
			e.ListConnectionProfiles().Return([]network.ConnectionProfile{{UUID: "u1"}}, err).Once()
		}, `"uuid":"u1"`},
		{"network.connection.get", map[string]any{"uuid": "u1", "secrets": true}, func(e *ex, err error) {
			e.GetConnectionSettings("u1", true).Return(map[string]map[string]any{"connection": {"id": "A"}}, err).Once()
		}, `"id":"A"`},
		{"network.connection.delete", map[string]any{"uuid": "u1"}, func(e *ex, err error) { e.DeleteConnectionProfile("u1").Return(err).Once() }, "deleted"},
		{"network.connection.duplicate", map[string]any{"uuid": "u1", "name": "B"}, func(e *ex, err error) { e.DuplicateConnectionProfile("u1", "B").Return("u2", err).Once() }, `"uuid":"u2"`},
		{"network.connection.activate", map[string]any{"uuid": "u1", "device": "eth0"}, func(e *ex, err error) { e.ActivateConnectionProfile("u1", "eth0").Return(err).Once() }, "activating"},
		{"network.connection.deactivate", map[string]any{"uuid": "u1"}, func(e *ex, err error) { e.DeactivateConnectionProfile("u1").Return(err).Once() }, "deactivated"},
		{"network.connection.export", map[string]any{"uuid": "u1", "file": "/tmp/x.conf"}, func(e *ex, err error) { e.ExportConnectionProfile("u1", "/tmp/x.conf").Return(err).Once() }, "exported"},
		{"network.connection.getEnterprise", map[string]any{"uuid": "u1"}, func(e *ex, err error) {
			e.GetConnectionSettings("u1", false).Return(map[string]map[string]any{"802-1x": {"eap": []string{"tls"}, "ca-cert": "blob"}}, err).Once()
		}, `"ca":"file"`},
		{"network.connection.firewallZones", nil, func(e *ex, err error) { e.FirewallZones().Return([]string{"public"}, err).Once() }, `["public"]`},
		{"network.connectivity.check", nil, func(e *ex, err error) { e.CheckConnectivity().Return("portal", err).Once() }, `"portal"`},
		{"network.connectivity.setCheckEnabled", map[string]any{"enabled": true}, func(e *ex, err error) { e.SetConnectivityCheckEnabled(true).Return(err).Once() }, "success"},
	}
	plain := network.NewTestManager(mocks.NewMockBackend(t), &network.NetworkState{})
	for _, c := range cases {
		t.Run(c.method, func(t *testing.T) {
			m, ed := newEditorManager(t, mocks.NewMockBackend(t))
			c.setup(ed.EXPECT(), nil)
			resp := call(t, m, c.method, c.p)
			require.Empty(t, resp.Error)
			assert.Contains(t, string(*resp.Result), c.want)
			c.setup(ed.EXPECT(), assert.AnError)
			assert.Equal(t, assert.AnError.Error(), call(t, m, c.method, c.p).Error)
			if len(c.p) > 0 {
				assert.NotEmpty(t, call(t, m, c.method, map[string]any{}).Error)
			}
			assert.Contains(t, call(t, plain, c.method, c.p).Error, "not supported")
		})
	}
}
func TestConnectionEnterpriseRejected(t *testing.T) {
	m, ed := newEditorManager(t, mocks.NewMockBackend(t))
	ed.EXPECT().GetConnectionSettings("u2", false).Return(map[string]map[string]any{"connection": {"id": "x"}}, nil).Once()
	assert.Equal(t, "connection has no 802.1X settings", call(t, m, "network.connection.getEnterprise", map[string]any{"uuid": "u2"}).Error)
	for _, ent := range []map[string]any{{"eap": "ttls", "bogus": 1}, {"eap": "nope", "identity": "bob"}} {
		assert.NotEmpty(t, call(t, m, "network.connection.update", map[string]any{"uuid": "u1", "settings": map[string]any{}, "enterprise": ent}).Error)
	}
}
func TestWireGuardKeysHandler(t *testing.T) {
	m := network.NewTestManager(mocks.NewMockBackend(t), &network.NetworkState{})
	var pair, derived map[string]string
	require.NoError(t, json.Unmarshal(*call(t, m, "network.wireguard.keys", nil).Result, &pair))
	require.NoError(t, json.Unmarshal(*call(t, m, "network.wireguard.keys", map[string]any{"privateKey": pair["privateKey"]}).Result, &derived))
	assert.Equal(t, pair, derived)
	assert.Equal(t, "invalid WireGuard key", call(t, m, "network.wireguard.keys", map[string]any{"privateKey": "abc"}).Error)
}
func TestWifiConnectEnterpriseAndEAPConfig(t *testing.T) {
	mb := mocks.NewMockBackend(t)
	m, _ := newEditorManager(t, mb)
	var got network.ConnectionRequest
	mb.EXPECT().ConnectWiFi(mock.Anything).Run(func(r network.ConnectionRequest) { got = r }).Return(nil).Once()
	require.Empty(t, call(t, m, "network.wifi.connect", map[string]any{"ssid": "eduroam", "security": "wpa-eap", "saveOnly": true, "hidden": true,
		"enterprise": map[string]any{"eap": "ttls", "serverDomain": "radius.example.org"}}).Error)
	assert.True(t, got.SaveOnly && got.Hidden && got.Enterprise.ServerDomain == "radius.example.org")
	assert.Contains(t, call(t, m, "network.wifi.connect", map[string]any{"ssid": "x", "enterprise": map[string]any{"bogus": 1}}).Error, "bogus")
	assert.Contains(t, string(*call(t, m, "network.eapconfig.parse", map[string]any{"file": "testdata/uhh.eap-config"}).Result), `"ssids":["eduroam"]`)
	big := filepath.Join(t.TempDir(), "big.eap-config")
	require.NoError(t, os.WriteFile(big, bytes.Repeat([]byte("a"), 4<<20+1), 0o600))
	assert.Contains(t, call(t, m, "network.eapconfig.parse", map[string]any{"file": big}).Error, "too large")
	plain := network.NewTestManager(mocks.NewMockBackend(t), &network.NetworkState{})
	assert.Contains(t, call(t, plain, "network.wifi.connect", map[string]any{"ssid": "x", "saveOnly": true}).Error, "not supported")
	assert.Contains(t, call(t, plain, "network.eapconfig.parse", map[string]any{"file": "testdata/uhh.eap-config"}).Error, "not supported")
}
