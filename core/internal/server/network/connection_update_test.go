package network

import (
	"errors"
	"maps"
	"slices"
	"testing"

	mock_dbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type legacyIP6Addr struct {
	Addr    []byte
	Prefix  uint32
	Gateway []byte
}

func expectGetSettings(obj *mock_dbus.MockBusObject, s nmSettings) {
	obj.EXPECT().Call(nmConnGetSettings, dbus.Flags(0)).
		Return(&dbus.Call{Body: []any{s}}).Once()
}

func expectGetSecrets(obj *mock_dbus.MockBusObject, setting string, s nmSettings) {
	obj.EXPECT().Call(nmConnGetSecrets, dbus.Flags(0), setting).
		Return(&dbus.Call{Body: []any{s}}).Once()
}

func captureUpdate2(obj *mock_dbus.MockBusObject, flags uint32, err error) *nmSettings {
	var got nmSettings
	obj.EXPECT().Call(nmConnUpdate2, dbus.Flags(0), mock.Anything, flags, mock.Anything).
		Run(func(_ string, _ dbus.Flags, args ...any) {
			got = args[0].(nmSettings)
		}).
		Return(&dbus.Call{Err: err, Body: []any{map[string]dbus.Variant{}}}).Once()
	return &got
}

func TestUpdateConnectionSettings_ManualDNSAndGatewaySurviveAutoconnectFlip(t *testing.T) {
	obj := mock_dbus.NewMockBusObject(t)
	legacyAddrs := []legacyIP6Addr{{Addr: make([]byte, 16), Prefix: 64, Gateway: make([]byte, 16)}}
	addr := func(a string, p uint32) dbus.Variant {
		return dbus.MakeVariant([]map[string]dbus.Variant{{"address": dbus.MakeVariant(a), "prefix": dbus.MakeVariant(p)}})
	}
	expectGetSettings(obj, nmSettings{
		"connection": {"id": dbus.MakeVariant("Wired"), "autoconnect": dbus.MakeVariant(true)},
		"ipv4": {
			"method": dbus.MakeVariant("manual"), "addresses": dbus.MakeVariant([][]uint32{{0x0100a8c0, 24, 0x0101a8c0}}),
			"address-data": addr("192.168.0.1", 24), "gateway": dbus.MakeVariant("192.168.1.1"),
			"dns": dbus.MakeVariant([]uint32{0x01010101}), "dns-data": dbus.MakeVariant([]string{"1.1.1.1"}),
		},
		"ipv6": {"method": dbus.MakeVariant("manual"), "addresses": dbus.MakeVariant(legacyAddrs), "address-data": addr("fd00::1", 64)},
	})
	got := captureUpdate2(obj, 0, nil)

	require.NoError(t, updateConnectionSettings(obj, false, func(s nmSettings) error {
		setSettingValue(s, "connection", "autoconnect", false)
		return nil
	}))

	s := *got
	assert.Equal(t, false, s["connection"]["autoconnect"].Value())
	assert.NotContains(t, s["ipv4"], "addresses")
	assert.NotContains(t, s["ipv4"], "dns")
	assert.NotContains(t, s["ipv6"], "addresses")
	assert.Equal(t, "192.168.1.1", s["ipv4"]["gateway"].Value())
	assert.Equal(t, "as", s["ipv4"]["dns-data"].Signature().String())
	assert.Equal(t, "aa{sv}", s["ipv4"]["address-data"].Signature().String())

	legacy := nmSettings{"ipv4": {"dns": dbus.MakeVariant([]uint32{1}), "addresses": dbus.MakeVariant([][]uint32{{1, 24, 0}})}}
	dropLegacyIPKeys(legacy)
	assert.Contains(t, legacy["ipv4"], "dns", "legacy key without a modern twin is kept")
	assert.Contains(t, legacy["ipv4"], "addresses")
}

func secretsFixture() nmSettings {
	return nmSettings{
		"connection":               {"id": dbus.MakeVariant("x"), "uuid": dbus.MakeVariant("u-vpn")},
		"802-11-wireless-security": {"key-mgmt": dbus.MakeVariant("wpa-psk")},
		"vpn": {
			"service-type": dbus.MakeVariant("org.freedesktop.NetworkManager.openvpn"),
		},
		"wireguard": {
			"peers": dbus.MakeVariant([]map[string]dbus.Variant{
				{"public-key": dbus.MakeVariant("PEER_A"), "endpoint": dbus.MakeVariant("a:51820")},
				{"public-key": dbus.MakeVariant("PEER_B")},
			}),
		},
	}
}

var (
	agentHeld = dbus.Error{Name: "org.freedesktop.NetworkManager.AgentManager.NoSecrets", Body: []any{"No agents were available for this request."}}
	askAgent  = errors.New("NM asks DMS's agent for the vpn secrets")
	wgHeld    = errors.New("an agent holds the wireguard secrets")
	askBoth   = errors.New("askAgent, and an agent holds the wireguard secrets")
	// offerSeen records, per vpn read through nmAsksAgent, whether DMS's agent had an offer.
	offerSeen []bool
)

// nmAsksAgent stands in for NM reading vpn secrets that only an agent holds:
// the stored cert-pass plus what DMS's agent answers, or NoSecrets.
func nmAsksAgent() *dbus.Call {
	offerSeen = append(offerSeen, offeredAgentSecrets("u-vpn", "vpn") != nil)
	if offeredAgentSecrets("u-vpn", "vpn") == nil {
		return &dbus.Call{Err: agentHeld}
	}
	conn := map[string]nmVariantMap{"connection": {"uuid": dbus.MakeVariant("u-vpn"), "type": dbus.MakeVariant("vpn")}}
	got, derr := (&SecretAgent{}).GetSecrets(conn, "/s/1", "vpn", nil, nmSecretAgentFlagAllowInteraction)
	if derr != nil {
		return &dbus.Call{Err: *derr}
	}
	secrets := map[string]string{"cert-pass": "b"}
	maps.Copy(secrets, got["vpn"]["secrets"].Value().(map[string]string))
	return &dbus.Call{Body: []any{nmSettings{"vpn": {"secrets": dbus.MakeVariant(secrets)}}}}
}

// expectStoredSecrets answers the vpn read with held when it is set, through
// nmAsksAgent for askAgent, and the wireguard read with NoSecrets for wgHeld.
func expectStoredSecrets(obj *mock_dbus.MockBusObject, held error) {
	expectGetSecrets(obj, "802-11-wireless-security", nmSettings{
		"802-11-wireless-security": {"psk": dbus.MakeVariant("old")},
	})
	switch held {
	case askAgent, askBoth:
		obj.EXPECT().Call(nmConnGetSecrets, dbus.Flags(0), "vpn").
			RunAndReturn(func(string, dbus.Flags, ...any) *dbus.Call { return nmAsksAgent() })
	case nil, wgHeld:
		expectGetSecrets(obj, "vpn", nmSettings{
			"vpn": {"secrets": dbus.MakeVariant(map[string]string{"password": "a", "cert-pass": "b"})},
		})
	default:
		obj.EXPECT().Call(nmConnGetSecrets, dbus.Flags(0), "vpn").Return(&dbus.Call{Err: held})
	}
	if held == wgHeld || held == askBoth {
		obj.EXPECT().Call(nmConnGetSecrets, dbus.Flags(0), "wireguard").Return(&dbus.Call{Err: agentHeld}).Once()
		return
	}
	expectGetSecrets(obj, "wireguard", nmSettings{"wireguard": {
		"peers": dbus.MakeVariant([]map[string]dbus.Variant{
			{"public-key": dbus.MakeVariant("PEER_B"), "preshared-key": dbus.MakeVariant("PSK_B")},
		}),
	}})
}

func TestUpdateConnectionSettings_SecretsMergedAndPatchWins(t *testing.T) {
	obj := mock_dbus.NewMockBusObject(t)
	expectGetSettings(obj, secretsFixture())
	expectStoredSecrets(obj, agentHeld)
	s, unreadable, err := readConnectionSettings(obj, true)
	require.NoError(t, err)
	assert.Equal(t, []string{"vpn"}, slices.Collect(maps.Keys(unreadable)))
	assert.Equal(t, "old", s["802-11-wireless-security"]["psk"].Value())

	peerPatch := func(peer map[string]any) SettingsPatch { return SettingsPatch{"wireguard": {"peers": []any{peer}}} }
	vpnData := SettingsPatch{"vpn": {"data": map[string]any{"remote": "b"}}}
	for _, tc := range []struct {
		name  string
		patch SettingsPatch
		held  error
		err   string
		psk   any // nil when absent
		vpn   map[string]string
		peers map[string]string // public-key -> preshared-key; nil when the section is gone
	}{
		{"stored secrets kept", SettingsPatch{}, nil, "", "old", map[string]string{"password": "a", "cert-pass": "b"},
			map[string]string{"PEER_A": "", "PEER_B": "PSK_B"}},
		{"patch wins, unmentioned kept", SettingsPatch{
			"802-11-wireless-security": {"psk": "new"}, "vpn": {"secrets": map[string]any{"password": "c"}},
		}, nil, "", "new", map[string]string{"password": "c", "cert-pass": "b"}, map[string]string{"PEER_A": "", "PEER_B": "PSK_B"}},
		{"null vpn secret removed", SettingsPatch{"vpn": {"secrets": map[string]any{"password": nil}}},
			nil, "", "old", map[string]string{"cert-pass": "b"}, map[string]string{"PEER_A": "", "PEER_B": "PSK_B"}},
		{"null peer psk removes it", peerPatch(map[string]any{"public-key": "PEER_B", "preshared-key": nil}),
			nil, "", "old", map[string]string{"password": "a", "cert-pass": "b"}, map[string]string{"PEER_B": ""}},
		{"omitted peer psk kept", peerPatch(map[string]any{"public-key": "PEER_B", "endpoint": "b:1"}),
			nil, "", "old", map[string]string{"password": "a", "cert-pass": "b"}, map[string]string{"PEER_B": "PSK_B"}},
		{"explicit peer psk wins", peerPatch(map[string]any{"public-key": "PEER_B", "preshared-key": "NEW"}),
			nil, "", "old", map[string]string{"password": "a", "cert-pass": "b"}, map[string]string{"PEER_B": "NEW"}},
		{"null containers stay deleted", SettingsPatch{"vpn": {"secrets": nil}, "wireguard": nil},
			nil, "", "old", nil, nil},
		// NM keeps stored secrets only when an update carries none at all.
		{"agent-held vpn: no secrets sent", vpnData, agentHeld, "", nil, nil,
			map[string]string{"PEER_A": "", "PEER_B": ""}},
		{"agent-held vpn: secret change refused", SettingsPatch{"vpn": {"secrets": map[string]any{"password": "c"}}},
			agentHeld, "vpn secrets can't be changed here while the vpn secrets are held by a secret agent", nil, nil, nil},
		{"agent-held wireguard: null peer psk refused", peerPatch(map[string]any{"public-key": "PEER_B", "preshared-key": nil}),
			wgHeld, "wireguard secrets can't be changed here while the wireguard secrets are held by a secret agent", nil, nil, nil},
		// The patch equals what the offer made readable, as a merging mutate's would.
		{"two agent-held sections: entered secret refused", SettingsPatch{"vpn": {"secrets": map[string]any{"password": "c", "cert-pass": "b"}}},
			askBoth, "vpn secrets can't be changed here while the wireguard secrets are held by a secret agent", nil, nil, nil},
		// Entered secrets: DMS's agent hands them to NM, which adds its stored ones.
		{"agent-held vpn: entered secret saved with the stored one", SettingsPatch{"vpn": {"secrets": map[string]any{"password": "c"}}},
			askAgent, "", "old", map[string]string{"password": "c", "cert-pass": "b"}, map[string]string{"PEER_A": "", "PEER_B": "PSK_B"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			obj := mock_dbus.NewMockBusObject(t)
			expectGetSettings(obj, secretsFixture())
			expectStoredSecrets(obj, tc.held)
			offerSeen = nil
			mutate := func(s nmSettings) error { return applySettingsPatch(s, tc.patch) }
			if tc.err != "" {
				require.EqualError(t, updateConnectionSettingsRemoving(obj, false, secretRemovalsFromPatch(tc.patch), mutate), tc.err)
				return
			}
			got := captureUpdate2(obj, 0, nil)
			require.NoError(t, updateConnectionSettingsRemoving(obj, false, secretRemovalsFromPatch(tc.patch), mutate))
			if tc.held == askAgent {
				assert.Equal(t, []bool{false, true}, offerSeen, "offered only on the second read")
				assert.Equal(t, agentHeld, nmAsksAgent().Err, "the offer ends with the write")
			}

			s := *got
			assert.Equal(t, tc.psk, s["802-11-wireless-security"]["psk"].Value())
			var vpn map[string]string
			if v, ok := s["vpn"]["secrets"]; ok {
				vpn = v.Value().(map[string]string)
			}
			assert.Equal(t, tc.vpn, vpn)
			var peers map[string]string
			if v, ok := s["wireguard"]["peers"]; ok {
				peers = map[string]string{}
				for _, p := range v.Value().([]map[string]dbus.Variant) {
					psk, _ := p["preshared-key"].Value().(string)
					peers[p["public-key"].Value().(string)] = psk
				}
			}
			assert.Equal(t, tc.peers, peers)
		})
	}
}

func TestUpdateConnectionSettings_FailuresWriteNothing(t *testing.T) {
	// Update2 drops omitted secrets, so a failed read must abort the write.
	obj := mock_dbus.NewMockBusObject(t)
	expectGetSettings(obj, nmSettings{"802-11-wireless-security": {"key-mgmt": dbus.MakeVariant("wpa-psk")}})
	obj.EXPECT().Call(nmConnGetSecrets, dbus.Flags(0), "802-11-wireless-security").
		Return(&dbus.Call{Err: dbus.Error{Name: "org.freedesktop.DBus.Error.NoReply", Body: []any{"timeout"}}}).Once()
	require.ErrorContains(t, updateConnectionSettings(obj, false, func(nmSettings) error { return nil }),
		"failed to get secrets for 802-11-wireless-security: timeout")
	obj.AssertNotCalled(t, "Call", nmConnUpdate2, mock.Anything, mock.Anything, mock.Anything, mock.Anything)

	obj = mock_dbus.NewMockBusObject(t)
	expectGetSettings(obj, nmSettings{"connection": {"id": dbus.MakeVariant("x")}})
	require.ErrorContains(t, updateConnectionSettings(obj, true, func(nmSettings) error { return errors.New("bad value") }), "bad value")
	obj.AssertNotCalled(t, "Call", nmConnUpdate2, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestUpdateConnectionSettings_PersistFlagAndNMError(t *testing.T) {
	obj := mock_dbus.NewMockBusObject(t)
	expectGetSettings(obj, nmSettings{"connection": {"id": dbus.MakeVariant("x")}})
	nmErr := dbus.Error{Name: "org.freedesktop.NetworkManager.Settings.Connection.InvalidProperty", Body: []any{"ipv4.dns: invalid IP address"}}
	captureUpdate2(obj, 0x1, nmErr)

	err := updateConnectionSettings(obj, true, func(nmSettings) error { return nil })
	require.EqualError(t, err, "failed to update connection: ipv4.dns: invalid IP address")
}
