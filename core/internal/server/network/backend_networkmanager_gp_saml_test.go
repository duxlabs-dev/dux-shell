package network

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
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

func TestSecretAgentExternalGPProducerDoesNotCacheDeliveredCookie(t *testing.T) {
	for _, convertedResolve := range []string{"", "redirect.example.test:192.0.2.10"} {
		t.Run("converted-resolve="+convertedResolve, func(t *testing.T) {
			binDir := t.TempDir()
			gpCount, ocCount := filepath.Join(binDir, "gp-count"), filepath.Join(binDir, "oc-count")
			argsPath, stdinPath := filepath.Join(binDir, "args"), filepath.Join(binDir, "stdin")
			require.NoError(t, os.WriteFile(filepath.Join(binDir, "gp-saml-gui"), []byte(`#!/bin/sh
n=0
if [ -f "$GP_COUNT" ]; then IFS= read -r n < "$GP_COUNT"; fi
n=$((n + 1))
printf '%s\n' "$n" > "$GP_COUNT"
printf '%s\n' "COOKIE='prelogin-$n'" "USER='dummy-user'" "HOST='initial.example.test'" "RESOLVE='initial.example.test:192.0.2.20'" "FINGERPRINT='pin-sha256:PRELOGIN'"
`), 0700))
			require.NoError(t, os.WriteFile(filepath.Join(binDir, "openconnect"), []byte(`#!/bin/sh
n=0
if [ -f "$OC_COUNT" ]; then IFS= read -r n < "$OC_COUNT"; fi
n=$((n + 1))
printf '%s\n' "$n" > "$OC_COUNT"
: > "$ARGS_FILE"
for arg in "$@"; do printf '%s\n' "$arg" >> "$ARGS_FILE"; done
IFS= read -r secret
printf '%s\n' "$secret" > "$STDIN_FILE"
printf '%s\n' "COOKIE='CONVERTED-$secret'" "HOST='192.0.2.10'" "RESOLVE='$CONVERTED_RESOLVE'" "FINGERPRINT='pin-sha256:CONVERTED'"
`), 0700))
			t.Setenv("PATH", binDir)
			t.Setenv("GP_COUNT", gpCount)
			t.Setenv("OC_COUNT", ocCount)
			t.Setenv("ARGS_FILE", argsPath)
			t.Setenv("STDIN_FILE", stdinPath)
			t.Setenv("CONVERTED_RESOLVE", convertedResolve)
			backend := &NetworkManagerBackend{state: &BackendState{}}
			agent := &SecretAgent{backend: backend}
			conn := helperAgentConnection("external-gp")
			conn["vpn"]["data"] = dbus.MakeVariant(map[string]string{"protocol": "gp", "gateway": "initial.example.test"})
			_, dbusErr := agent.GetSecrets(conn, "/settings/gp", "vpn", []string{"gp-saml"}, nmSecretAgentFlagUserRequested)
			require.NotNil(t, dbusErr)
			require.Equal(t, "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", dbusErr.Name)
			_, err := os.Stat(gpCount)
			require.ErrorIs(t, err, os.ErrNotExist)
			for activation := 1; activation <= 2; activation++ {
				out, dbusErr := agent.GetSecrets(conn, "/settings/gp", "vpn", []string{"gp-saml"}, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagUserRequested)
				require.Nil(t, dbusErr)
				resolve := convertedResolve
				if resolve == "" {
					resolve = "initial.example.test:192.0.2.20"
				}
				require.Equal(t, map[string]string{
					"cookie": fmt.Sprintf("CONVERTED-prelogin-%d", activation), "gateway": "192.0.2.10",
					"resolve": resolve, "gwcert": "pin-sha256:CONVERTED",
				}, out["vpn"]["secrets"].Value())
				require.Nil(t, backend.cachedOpenConnectAuth, "already-delivered GP cookies must never enter the preactivation handoff cache")
				for _, countPath := range []string{gpCount, ocCount} {
					raw, err := os.ReadFile(countPath)
					require.NoError(t, err)
					require.Equal(t, fmt.Sprintf("%d\n", activation), string(raw))
				}
				raw, err := os.ReadFile(stdinPath)
				require.NoError(t, err)
				require.Equal(t, fmt.Sprintf("prelogin-%d\n", activation), string(raw))
			}
			raw, err := os.ReadFile(argsPath)
			require.NoError(t, err)
			require.Equal(t, []string{"--protocol=gp", "--usergroup=gateway:prelogin-cookie", "--user=dummy-user", "--passwd-on-stdin", "--allow-insecure-crypto", "--authenticate", "initial.example.test"}, strings.Split(strings.TrimSpace(string(raw)), "\n"))
		})
	}
}

func TestRunFortinetPasswordAuth(t *testing.T) {
	tests := []struct {
		name             string
		protocol         string
		expectedProtocol string
		expectedHost     string
	}{
		{name: "Fortinet preserves initial gateway", protocol: "fortinet", expectedProtocol: "fortinet", expectedHost: "initial.example.test:443"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			binDir := t.TempDir()
			argsPath := filepath.Join(binDir, "args")
			stdinPath := filepath.Join(binDir, "stdin")
			openConnectPath := filepath.Join(binDir, "openconnect")
			script := `#!/bin/sh
: > "$ARGS_FILE"
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$ARGS_FILE"
done
IFS= read -r secret
printf '%s\n' "$secret" > "$STDIN_FILE"
printf '%s\n' "COOKIE='COOKIE-VALUE'" "HOST='192.0.2.10'" "CONNECT_URL='https://redirect.example.test/ssl-vpn'" "RESOLVE='redirect.example.test:192.0.2.10'" "FINGERPRINT='pin-sha256:RETURNED'"
`
			assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
			t.Setenv("PATH", binDir)
			t.Setenv("ARGS_FILE", argsPath)
			t.Setenv("STDIN_FILE", stdinPath)

			result, err := runOpenConnectPasswordAuth(context.Background(), map[string]string{
				"protocol":  tt.protocol,
				"authtype":  "password",
				"gateway":   "initial.example.test:443",
				"usergroup": "employees",
				"cacert":    "/etc/ssl/test-ca.pem",
			}, "test-user", "test-password", "pin-sha256:PINNED")
			assert.NoError(t, err)
			assert.Equal(t, "COOKIE-VALUE", result.Cookie)
			assert.Equal(t, tt.expectedHost, result.Host)
			assert.Equal(t, "redirect.example.test:192.0.2.10", result.Resolve)
			assert.Equal(t, "pin-sha256:RETURNED", result.Fingerprint)

			argsBytes, readErr := os.ReadFile(argsPath)
			assert.NoError(t, readErr)
			args := strings.Split(strings.TrimSpace(string(argsBytes)), "\n")
			assert.Equal(t, []string{
				"--protocol=" + tt.expectedProtocol,
				"--user=test-user",
				"--passwd-on-stdin",
				"--non-inter",
				"--usergroup=employees",
				"--cafile=/etc/ssl/test-ca.pem",
				"--servercert=pin-sha256:PINNED",
				"--authenticate",
				"initial.example.test:443",
			}, args)
			assert.NotContains(t, string(argsBytes), "test-password")

			stdinBytes, readErr := os.ReadFile(stdinPath)
			assert.NoError(t, readErr)
			assert.Equal(t, "test-password\n", string(stdinBytes))
		})
	}
}

func TestRunFortinetPasswordAuthStrictPKIIgnoresSavedPin(t *testing.T) {
	binDir := t.TempDir()
	argsPath := filepath.Join(binDir, "args")
	openConnectPath := filepath.Join(binDir, "openconnect")
	script := `#!/bin/sh
: > "$ARGS_FILE"
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$ARGS_FILE"
done
printf '%s\n' "COOKIE='COOKIE-VALUE'"
`
	assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
	t.Setenv("PATH", binDir)
	t.Setenv("ARGS_FILE", argsPath)

	result, err := runOpenConnectPasswordAuth(context.Background(), map[string]string{
		"protocol":             "fortinet",
		"authtype":             "password",
		"gateway":              "vpn.example.test",
		"cacert":               "/etc/ssl/test-ca.pem",
		"prevent_invalid_cert": "yes",
	}, "test-user", "test-password", "pin-sha256:SAVED")
	assert.NoError(t, err)
	assert.Equal(t, "vpn.example.test", result.Host)
	assert.Empty(t, result.Fingerprint)

	argsBytes, readErr := os.ReadFile(argsPath)
	assert.NoError(t, readErr)
	assert.Contains(t, string(argsBytes), "--cafile=/etc/ssl/test-ca.pem\n")
	assert.NotContains(t, string(argsBytes), "--servercert=")
}

func TestRunFortinetPasswordAuthErrors(t *testing.T) {
	for _, protocol := range []string{"pulse", "anyconnect", ""} {
		t.Run("unsupported protocol="+protocol, func(t *testing.T) {
			binDir := t.TempDir()
			marker := filepath.Join(binDir, "executed")
			assert.NoError(t, os.WriteFile(filepath.Join(binDir, "openconnect"), []byte("#!/bin/sh\n: > \"$EXEC_MARKER\"\nexit 1\n"), 0o755))
			t.Setenv("PATH", binDir)
			t.Setenv("EXEC_MARKER", marker)
			result, err := runOpenConnectPasswordAuth(context.Background(), map[string]string{
				"protocol": protocol, "authtype": "password", "gateway": "vpn.example.test",
			}, "test-user", "test-password", "")
			assert.ErrorContains(t, err, "not supported for protocol")
			assert.Nil(t, result)
			_, err = os.Stat(marker)
			assert.ErrorIs(t, err, os.ErrNotExist, "unsupported protocol must be rejected before exec")
		})
	}

	for _, tt := range []struct {
		name string
		exit string
	}{
		{name: "missing cookie", exit: "exit 0"},
		{name: "command failure", exit: "exit 1"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			binDir := t.TempDir()
			openConnectPath := filepath.Join(binDir, "openconnect")
			script := `#!/bin/sh
IFS= read -r secret
printf 'authentication failed for %s\n' "$secret" >&2
printf '%s\n' "HOST='vpn.example.test'"
` + tt.exit + "\n"
			assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
			t.Setenv("PATH", binDir)

			_, err := runOpenConnectPasswordAuth(context.Background(), map[string]string{
				"protocol": "fortinet",
				"authtype": "password",
				"gateway":  "vpn.example.test",
			}, "test-user", "do-not-leak", "")
			assert.Error(t, err)
			assert.NotContains(t, err.Error(), "do-not-leak")
			if tt.name == "missing cookie" {
				assert.ErrorContains(t, err, "no COOKIE")
			}
		})
	}
}

func TestRunFortinetPasswordAuthCancellation(t *testing.T) {
	binDir := t.TempDir()
	openConnectPath := filepath.Join(binDir, "openconnect")
	assert.NoError(t, os.WriteFile(openConnectPath, []byte("#!/bin/sh\nexec /bin/sleep 10\n"), 0o755))
	t.Setenv("PATH", binDir)

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	_, err := runOpenConnectPasswordAuth(ctx, map[string]string{
		"protocol": "fortinet",
		"authtype": "password",
		"gateway":  "vpn.example.test",
	}, "test-user", "test-password", "")
	assert.Error(t, err)
	assert.ErrorIs(t, err, context.DeadlineExceeded)
}
