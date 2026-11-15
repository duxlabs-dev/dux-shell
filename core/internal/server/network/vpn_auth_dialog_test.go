package network

import (
	"bufio"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadLegacyDialogSecrets(t *testing.T) {
	tests := []struct {
		name, in string
		want     map[string]string
		wantErr  bool
	}{
		{"pairs", "cookie\nabc\ngateway\nvpn.example.com\n\n\n", map[string]string{"cookie": "abc", "gateway": "vpn.example.com"}, false},
		{"empty value", "gwcert\n\ncookie\nabc\n\n", map[string]string{"gwcert": "", "cookie": "abc"}, false},
		{"no secrets", "\n\n", map[string]string{}, false},
		{"no terminator", "cookie\nabc\n", nil, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := readLegacyDialogSecrets(bufio.NewReader(strings.NewReader(tt.in)))
			assert.Equal(t, tt.wantErr, err != nil)
			assert.Equal(t, tt.want, got)
		})
	}
}

const vpncKeyfile = `[VPN Plugin UI]
Version=2
Title=Authenticate VPN

[Xauth password]
Value=p\sw\nx
Label=User password
Label[de]=Benutzerpasswort
IsSecret=true
ShouldAsk=true

# group secret is stored
[IPSec secret]
Value=stored
IsSecret=1
ShouldAsk=false
`

func TestParseVPNUIKeyfile(t *testing.T) {
	fields, err := parseVPNUIKeyfile([]byte(vpncKeyfile))
	require.NoError(t, err)
	assert.Equal(t, []vpnUISecret{
		{Name: "Xauth password", Label: "User password", Value: "p w\nx", IsSecret: true, ShouldAsk: true},
		{Name: "IPSec secret", Value: "stored", IsSecret: true},
	}, fields)

	_, err = parseVPNUIKeyfile([]byte("[Xauth password]\nnot a pair\n"))
	assert.Error(t, err)
}

func TestRunVPNAuthDialog(t *testing.T) {
	dir := t.TempDir()
	readStdin := `while IFS= read -r l; do printf '%s\n' "$l" >> ` + dir + `/stdin; [ "$l" = DONE ] && break; done; read -r blank` + "\n"
	tests := []struct {
		name, script string
		externalUI   bool
		wantSecrets  map[string]string
		wantFields   []vpnUISecret
		wantErr      error
		wantErrText  string
	}{
		{name: "legacy", wantSecrets: map[string]string{"cookie": "abc", "gwcert": ""},
			script: `printf '%s\n' "$@" > ` + dir + "/argv\n" + readStdin +
				`printf 'cookie\nabc\ngwcert\n\n\n'; read -r q; printf '%s' "$q" > ` + dir + "/quit\n"},
		{name: "legacy cancel", script: "exit 1\n", wantErr: errVPNAuthDialogCancelled},
		{name: "legacy crash", script: "kill -9 $$\n", wantErrText: "killed"},
		{name: "external UI", externalUI: true, script: readStdin + `printf '[VPN Plugin UI]\nVersion=2\n[pin]\nShouldAsk=true\n'` + "\n",
			wantFields: []vpnUISecret{{Name: "pin", ShouldAsk: true}}},
		{name: "legacy flood", script: "exec head -c 70000 /dev/zero\n", wantErrText: "exceeds"},
		{name: "cancel", script: "exec 2>&-; sleep 30; :\n", wantErr: context.Canceled},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dialog := filepath.Join(dir, "dialog")
			require.NoError(t, os.WriteFile(dialog, []byte("#!/bin/sh\n"+tt.script), 0o755))
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			if errors.Is(tt.wantErr, context.Canceled) {
				time.AfterFunc(200*time.Millisecond, cancel)
			}
			start := time.Now()
			secrets, fields, err := runVPNAuthDialog(ctx, vpnAuthDialogRequest{
				Dialog: dialog, UUID: "u-1", Name: "Work", ServiceType: "org.freedesktop.NetworkManager.openconnect", ExternalUI: tt.externalUI,
				Data: map[string]string{"gateway": "vpn.example.com", "authtype": "cert"}, Secrets: map[string]string{"cookie": "old"},
			})
			assert.Less(t, time.Since(start), 5*time.Second)
			if tt.wantErr != nil || tt.wantErrText != "" {
				if tt.wantErr != nil {
					assert.ErrorIs(t, err, tt.wantErr)
				} else {
					assert.NotErrorIs(t, err, errVPNAuthDialogCancelled)
				}
				assert.ErrorContains(t, err, tt.wantErrText)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.wantSecrets, secrets)
			assert.Equal(t, tt.wantFields, fields)
		})
	}

	argv, _ := os.ReadFile(filepath.Join(dir, "argv"))
	assert.Equal(t, "-u\nu-1\n-n\nWork\n-s\norg.freedesktop.NetworkManager.openconnect\n-i\n", string(argv))
	quit, _ := os.ReadFile(filepath.Join(dir, "quit"))
	assert.Equal(t, "QUIT", string(quit))
	stdin, _ := os.ReadFile(filepath.Join(dir, "stdin"))
	_, err := vpnAuthDialogInput(map[string]string{"gateway": "x\nSECRET_KEY=cookie"}, nil)
	assert.Error(t, err)
	assert.True(t, strings.HasPrefix(string(stdin), "DATA_KEY=authtype\nDATA_VAL=cert\n\nDATA_KEY=gateway\nDATA_VAL=vpn.example.com\n\nSECRET_KEY=cookie\nSECRET_VAL=old\n\nDONE\n"), string(stdin))
}

func TestOpenConnectDialogClosedWithoutCookie(t *testing.T) {
	dialog := filepath.Join(t.TempDir(), "dialog")
	require.NoError(t, os.WriteFile(dialog, []byte("#!/bin/sh\ncat >/dev/null &\nprintf 'gwcert\\nstored\\n\\n\\n'\n"), 0o755))
	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetSecrets("vpn").Return(gonetworkmanager.ConnectionSettings{}, nil)

	_, err := (&NetworkManagerBackend{}).handleVPNAuthDialog(conn, VPNPlugin{AuthDialog: dialog}, "Work", "u-1",
		"org.freedesktop.NetworkManager.openconnect", map[string]string{"gateway": "vpn.example.com"})
	assert.ErrorIs(t, err, errVPNAuthDialogCancelled)
}
