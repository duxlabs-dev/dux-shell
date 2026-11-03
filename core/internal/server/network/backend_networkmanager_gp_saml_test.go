package network

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
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
