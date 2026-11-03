package network

import (
	"net"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestParseWpaScanResults(t *testing.T) {
	text := "bssid / frequency / signal level / flags / ssid\n" +
		"02:00:01:02:03:04\t2412\t-45\t[WPA2-PSK-CCMP][ESS]\tHome\n" +
		"02:00:01:02:03:05\t5180\t-60\t[WPA2-EAP-CCMP][ESS]\tOffice\n" +
		"02:00:01:02:03:06\t2437\t-70\t[ESS]\tCafe\n" +
		"02:00:01:02:03:07\t2462\t-80\t[WPA2-PSK-CCMP][ESS]\t\n" +
		"02:00:01:02:03:08\t2412\t-50\t[WEP][ESS]\tTab\\tNet\n" +
		"garbage line without tabs\n"

	results := parseWpaScanResults(text)

	assert.Len(t, results, 5)
	assert.Equal(t, "02:00:01:02:03:04", results[0].BSSID)
	assert.Equal(t, uint32(2412), results[0].Frequency)
	assert.Equal(t, -45, results[0].Level)
	assert.Equal(t, "[WPA2-PSK-CCMP][ESS]", results[0].Flags)
	assert.Equal(t, "Home", results[0].SSID)
	assert.Empty(t, results[3].SSID)
	assert.Equal(t, "Tab\tNet", results[4].SSID)
}

func TestWpaWiFiNetworksFromScanResults(t *testing.T) {
	results := []wpaScanResult{
		{BSSID: "02:00:01:02:03:04", Frequency: 2412, Level: -45, Flags: "[WPA2-PSK-CCMP][ESS]", SSID: "Home"},
		{BSSID: "02:00:01:02:03:05", Frequency: 5180, Level: -80, Flags: "[WPA2-PSK-CCMP][ESS]", SSID: "Home"},
		{BSSID: "02:00:01:02:03:06", Frequency: 5200, Level: -60, Flags: "[WPA2-EAP-CCMP][ESS]", SSID: "Office"},
		{BSSID: "02:00:01:02:03:07", Frequency: 2437, Level: -70, Flags: "[ESS]", SSID: "Cafe"},
		{BSSID: "02:00:01:02:03:08", Frequency: 2462, Level: -50, Flags: "[WPA2-PSK-CCMP][ESS]", SSID: ""},
	}

	networks := wpaWiFiNetworksFromScanResults(results)

	byNet := make(map[string]WiFiNetwork, len(networks))
	for _, network := range networks {
		byNet[network.SSID] = network
	}

	assert.Len(t, networks, 3)

	home := byNet["Home"]
	assert.Equal(t, "02:00:01:02:03:04", home.BSSID, "strongest BSS should win")
	assert.Equal(t, uint8(55), home.Signal)
	assert.True(t, home.Secured)
	assert.False(t, home.Enterprise)
	assert.Equal(t, uint32(1), home.Channel)

	office := byNet["Office"]
	assert.True(t, office.Secured)
	assert.True(t, office.Enterprise)

	cafe := byNet["Cafe"]
	assert.False(t, cafe.Secured)
	assert.Equal(t, "infrastructure", cafe.Mode)
}

func TestSignalPercentFromDbm(t *testing.T) {
	testCases := []struct {
		dbm      int
		expected uint8
	}{
		{-30, 70},
		{-110, 0},
		{10, 100},
	}

	for _, tc := range testCases {
		assert.Equal(t, tc.expected, signalPercentFromDbm(tc.dbm), "dbm=%d", tc.dbm)
	}
}

func TestParseWpaStatus(t *testing.T) {
	text := "bssid=02:00:01:02:03:04\n" +
		"freq=2412\n" +
		"ssid=Home Network\n" +
		"id=3\n" +
		"key_mgmt=WPA2-PSK\n" +
		"wpa_state=COMPLETED\n" +
		"ip_address=192.168.1.21\n"

	st := parseWpaStatus(text)

	assert.Equal(t, "COMPLETED", st.wpaState)
	assert.Equal(t, "Home Network", st.ssid)
	assert.Equal(t, "02:00:01:02:03:04", st.bssid)
	assert.Equal(t, "192.168.1.21", st.ipAddress)
	assert.Equal(t, "WPA2-PSK", st.keyMgmt)
	assert.Equal(t, 3, st.networkID)
}

func TestParseWpaStatus_Disconnected(t *testing.T) {
	st := parseWpaStatus("wpa_state=DISCONNECTED\naddress=02:00:01:02:03:04\n")

	assert.Equal(t, "DISCONNECTED", st.wpaState)
	assert.Empty(t, st.ssid)
	assert.Equal(t, -1, st.networkID)
}

func TestParseWpaSignalPollRSSI(t *testing.T) {
	rssi, ok := parseWpaSignalPollRSSI("RSSI=-62\nLINKSPEED=433\nNOISE=9999\nFREQUENCY=5180\n")
	assert.True(t, ok)
	assert.Equal(t, -62, rssi)

	_, ok = parseWpaSignalPollRSSI("FAIL")
	assert.False(t, ok)
}

func TestParseWpaListNetworks(t *testing.T) {
	text := "network id / ssid / bssid / flags\n" +
		"0\tHome\tany\t[CURRENT]\n" +
		"1\tOffice\tany\t[DISABLED]\n" +
		"2\tCafe\tany\t\n" +
		"3\tFlaky\tany\t[TEMP-DISABLED]\n" +
		"bogus\tline\tany\t\n"

	networks := parseWpaListNetworks(text)

	assert.Len(t, networks, 4)
	assert.Equal(t, 0, networks[0].id)
	assert.Equal(t, "Home", networks[0].ssid)
	assert.True(t, networks[0].current)
	assert.False(t, networks[0].disabled)

	assert.True(t, networks[1].disabled)
	assert.False(t, networks[2].disabled)
	assert.False(t, networks[2].current)
	assert.True(t, networks[3].tempDisabled)
}

func TestParseWpaEventLine(t *testing.T) {
	testCases := []struct {
		line     string
		ok       bool
		priority int
		name     string
		args     string
	}{
		{"<2>CTRL-EVENT-CONNECTED - Connection to 02:00:01:02:03:04 completed [id=0 id_str=]", true, 2, "CTRL-EVENT-CONNECTED", "- Connection to 02:00:01:02:03:04 completed [id=0 id_str=]"},
		{"<2>CTRL-EVENT-SCAN-RESULTS ", true, 2, "CTRL-EVENT-SCAN-RESULTS", ""},
		{"OK", false, 0, "", ""},
		{"", false, 0, "", ""},
		{"<x>BROKEN", false, 0, "", ""},
	}

	for _, tc := range testCases {
		event, ok := parseWpaEventLine(tc.line)
		assert.Equal(t, tc.ok, ok, "line=%q", tc.line)
		if !tc.ok {
			continue
		}
		assert.Equal(t, tc.priority, event.priority, "line=%q", tc.line)
		assert.Equal(t, tc.name, event.name, "line=%q", tc.line)
		assert.Equal(t, tc.args, event.args, "line=%q", tc.line)
	}
}

func TestParseWpaTempDisabled(t *testing.T) {
	ssid, reason := parseWpaTempDisabled(`id=1 ssid="Home Net" auth_failures=1 duration=10 reason=WRONG_KEY`)
	assert.Equal(t, "Home Net", ssid)
	assert.Equal(t, "WRONG_KEY", reason)

	ssid, reason = parseWpaTempDisabled(`id=2 ssid="quo\"te" auth_failures=3 duration=20 reason=CONN_FAILED`)
	assert.Equal(t, `quo"te`, ssid)
	assert.Equal(t, "CONN_FAILED", reason)

	ssid, reason = parseWpaTempDisabled("garbage")
	assert.Empty(t, ssid)
	assert.Empty(t, reason)
}

func TestDecodeWpaSSIDText(t *testing.T) {
	testCases := []struct {
		encoded  string
		expected string
	}{
		{"Plain", "Plain"},
		{`With\tTab`, "With\tTab"},
		{`With\\Backslash`, `With\Backslash`},
		{`With\"Quote`, `With"Quote`},
		{`Hex\xc3\xa9`, "Hexé"},
		{`Trailing\`, `Trailing\`},
		{`Bad\xzz`, `Bad\xzz`},
	}

	for _, tc := range testCases {
		assert.Equal(t, tc.expected, decodeWpaSSIDText(tc.encoded), "encoded=%q", tc.encoded)
	}
}

func TestWpaQuotedString(t *testing.T) {
	quoted, err := wpaQuotedString("passphrase")
	assert.NoError(t, err)
	assert.Equal(t, `"passphrase"`, quoted)

	_, err = wpaQuotedString(`with"quote`)
	assert.Error(t, err)

	_, err = wpaQuotedString("with\nnewline")
	assert.Error(t, err)
}

func TestParseWpaConfigPassphrase(t *testing.T) {
	config := "ctrl_interface=/var/run/wpa_supplicant\n" +
		"update_config=1\n" +
		"\n" +
		"network={\n" +
		"\tssid=\"Home\"\n" +
		"\tpsk=\"secret pass\"\n" +
		"}\n" +
		"\n" +
		"network={\n" +
		"\tssid=486578\n" +
		"\tpsk=\"hexpass\"\n" +
		"}\n" +
		"\n" +
		"network={\n" +
		"\tssid=\"RawKey\"\n" +
		"\tpsk=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n" +
		"}\n"

	pass, err := parseWpaConfigPassphrase(config, "Home")
	assert.NoError(t, err)
	assert.Equal(t, "secret pass", pass)

	pass, err = parseWpaConfigPassphrase(config, "Hex")
	assert.NoError(t, err)
	assert.Equal(t, "hexpass", pass)

	_, err = parseWpaConfigPassphrase(config, "RawKey")
	assert.Error(t, err, "raw hex PSK is not a passphrase")

	_, err = parseWpaConfigPassphrase(config, "Unknown")
	assert.Error(t, err)
}

func startFakeWpaSocket(t *testing.T, handler func(cmd string) []string) string {
	t.Helper()

	sockPath := filepath.Join(t.TempDir(), "wlan0")
	conn, err := net.ListenUnixgram("unixgram", &net.UnixAddr{Name: sockPath, Net: "unixgram"})
	if err != nil {
		t.Fatalf("listen fake wpa socket: %v", err)
	}
	t.Cleanup(func() { conn.Close() })

	go func() {
		buf := make([]byte, 4096)
		for {
			n, addr, err := conn.ReadFromUnix(buf)
			if err != nil {
				return
			}
			for _, reply := range handler(string(buf[:n])) {
				conn.WriteToUnix([]byte(reply), addr)
			}
		}
	}()

	return sockPath
}

func TestWpaCtrlConn_Request(t *testing.T) {
	sockPath := startFakeWpaSocket(t, func(cmd string) []string {
		switch cmd {
		case "PING":
			return []string{"PONG\n"}
		case "SCAN":
			return []string{"<2>CTRL-EVENT-SCAN-STARTED ", "OK\n"}
		default:
			return []string{"FAIL\n"}
		}
	})

	conn, err := newWpaCtrlConn(sockPath)
	if err != nil {
		t.Fatalf("open wpa_ctrl conn: %v", err)
	}
	defer conn.close()

	reply, err := conn.request("PING")
	assert.NoError(t, err)
	assert.Equal(t, "PONG", reply)

	reply, err = conn.request("SCAN")
	assert.NoError(t, err)
	assert.Equal(t, "OK", reply, "unsolicited event datagrams must be skipped")

	reply, err = conn.request("BOGUS")
	assert.NoError(t, err)
	assert.Equal(t, "FAIL", reply)
}

func TestWpaSupplicantBackend_ClassifyAttempt(t *testing.T) {
	backend, _ := NewWpaSupplicantBackend()

	att := &wpaConnectAttempt{ssid: "Home", sawTempDisabled: true}
	assert.Equal(t, "bad-credentials", backend.classifyAttempt(att))

	att = &wpaConnectAttempt{ssid: "Home"}
	assert.Equal(t, "no-such-ssid", backend.classifyAttempt(att))

	backend.recentScansMu.Lock()
	backend.recentScans["Home"] = time.Now()
	backend.recentScansMu.Unlock()
	assert.Equal(t, "assoc-timeout", backend.classifyAttempt(att))
}
