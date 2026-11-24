package network

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUnshellQuote(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "single quoted",
			input:    "'hello world'",
			expected: "hello world",
		},
		{
			name:     "double quoted",
			input:    `"hello world"`,
			expected: "hello world",
		},
		{
			name:     "unquoted",
			input:    "hello",
			expected: "hello",
		},
		{
			name:     "empty single quotes",
			input:    "''",
			expected: "",
		},
		{
			name:     "single quote only",
			input:    "'",
			expected: "'",
		},
		{
			name:     "mismatched quotes",
			input:    "'hello\"",
			expected: "'hello\"",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := unshellQuote(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestParseGPSamlFromCommandLine(t *testing.T) {
	tests := []struct {
		name           string
		line           string
		initialResult  *openConnectAuthResult
		expectedCookie string
		expectedUser   string
		expectedFP     string
	}{
		{
			name:           "full openconnect command",
			line:           "openconnect --protocol=gp --cookie=AUTH123 --servercert=pin-sha256:ABC --user=john",
			initialResult:  &openConnectAuthResult{},
			expectedCookie: "AUTH123",
			expectedUser:   "john",
			expectedFP:     "pin-sha256:ABC",
		},
		{
			name:           "with equals signs in cookie",
			line:           "openconnect --cookie=authcookie=xyz123&portal=GATE --user=jane",
			initialResult:  &openConnectAuthResult{},
			expectedCookie: "authcookie=xyz123&portal=GATE",
			expectedUser:   "jane",
			expectedFP:     "",
		},
		{
			name:           "non-openconnect line",
			line:           "some other output",
			initialResult:  &openConnectAuthResult{},
			expectedCookie: "",
			expectedUser:   "",
			expectedFP:     "",
		},
		{
			name:           "preserves existing values",
			line:           "openconnect --user=newuser",
			initialResult:  &openConnectAuthResult{Cookie: "existing", Fingerprint: "existing-fp"},
			expectedCookie: "existing",
			expectedUser:   "newuser",
			expectedFP:     "existing-fp",
		},
		{
			name:           "real gp-saml-gui output",
			line:           "openconnect --protocol=gp --user=john.doe@example.com --os=linux-64 --usergroup=gateway:prelogin-cookie --passwd-on-stdin",
			initialResult:  &openConnectAuthResult{},
			expectedCookie: "",
			expectedUser:   "john.doe@example.com",
			expectedFP:     "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.initialResult
			parseGPSamlFromCommandLine(tt.line, result)

			assert.Equal(t, tt.expectedCookie, result.Cookie, "cookie mismatch")
			assert.Equal(t, tt.expectedUser, result.User, "user mismatch")
			assert.Equal(t, tt.expectedFP, result.Fingerprint, "fingerprint mismatch")
		})
	}
}

func TestRunOpenConnectAuthenticateSanitizesFailure(t *testing.T) {
	binDir := t.TempDir()
	openConnectPath := filepath.Join(binDir, "openconnect")
	script := "#!/bin/sh\nprintf '%s\\n' 'Cookie: should-not-leak' 'Add --servercert pin-sha256:TEST-FINGERPRINT' >&2\nexit 1\n"
	assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
	t.Setenv("PATH", binDir)

	_, err := runOpenConnectAuthenticate(context.Background(), []string{"--authenticate", "vpn.example.test"}, "password")
	assert.Error(t, err)
	assert.NotContains(t, err.Error(), "should-not-leak")

	var authErr *openConnectAuthError
	assert.True(t, errors.As(err, &authErr))
	assert.Equal(t, "pin-sha256:TEST-FINGERPRINT", authErr.serverCert)
}

func TestRunOpenConnectPasswordAuth(t *testing.T) {
	binDir := t.TempDir()
	script := `#!/bin/sh
printf '%s\n' "$@" > "$0.args"
case "$*" in
  *--usergroup=again*) echo 'User input required in non-interactive mode' >&2; exit 1 ;;
esac
printf '%s\n' "COOKIE='c'" "HOST='192.0.2.1'" "CONNECT_URL='https://vpn.example.test/'" "RESOLVE='vpn.example.test:192.0.2.1'"
`
	require.NoError(t, os.WriteFile(filepath.Join(binDir, "openconnect"), []byte(script), 0o755))
	t.Setenv("PATH", binDir)

	tests := []struct {
		name, protocol, usergroup   string
		wantProtocol, wantHost      string
		wantResolve                 string
		wantErr, wantDialogFallback bool
	}{
		{"anyconnect default", "", "", "--protocol=anyconnect", "https://vpn.example.test/", "vpn.example.test:192.0.2.1", false, false},
		{"fortinet keeps gateway", "fortinet", "", "--protocol=fortinet", "vpn.example.test", "", false, false},
		{"asked again", "pulse", "again", "--protocol=pulse", "", "", true, true},
		{"fortinet asked again", "fortinet", "again", "--protocol=fortinet", "", "", true, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data := map[string]string{"gateway": "vpn.example.test", "protocol": tt.protocol, "usergroup": tt.usergroup}
			result, err := runOpenConnectPasswordAuth(context.Background(), data, "user", "pw", "")
			assert.Equal(t, tt.wantErr, err != nil)
			assert.Equal(t, tt.wantDialogFallback, openConnectDialogFallback(err, data))
			args, _ := os.ReadFile(filepath.Join(binDir, "openconnect.args"))
			assert.Contains(t, strings.Split(string(args), "\n"), tt.wantProtocol)
			if err == nil {
				assert.Equal(t, tt.wantHost, result.Host)
				assert.Equal(t, tt.wantResolve, result.Resolve)
			}
		})
	}
}
