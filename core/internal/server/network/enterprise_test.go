package network

import (
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Profiles that hold blobs or a ca-path decode without a file path, and an edit leaves those keys alone.
func TestEnterpriseBlobProfileSurvivesResave(t *testing.T) {
	v := dbus.MakeVariant
	for name, tt := range map[string]struct {
		eap, ca string
		stored  map[string]dbus.Variant
		lacks   []string
	}{
		"blob ca":      {"peap", "file", map[string]dbus.Variant{"ca-cert": v([]byte{1})}, []string{"ca-cert"}},
		"ca-path only": {"peap", "file", map[string]dbus.Variant{"ca-path": v("/etc/ssl/certs")}, []string{"ca-cert", "ca-path"}},
		"blob tls":     {"tls", "none", map[string]dbus.Variant{"client-cert": v([]byte{1}), "private-key": v([]byte{2})}, []string{"client-cert", "private-key"}},
	} {
		tt.stored["identity"], tt.stored["eap"] = v("u"), v([]string{tt.eap})
		cfg, ok := enterpriseConfigFromSettings(decodeSettingsForJSON(map[string]map[string]dbus.Variant{"802-1x": tt.stored}))
		require.True(t, ok, name)
		assert.Equal(t, tt.ca, cfg.CA, name)
		assert.Empty(t, cfg.CACertPath+cfg.ClientCertPath+cfg.PrivateKeyPath, name)
		cfg.Identity, cfg.Phase2 = "new", "mschapv2"
		p, err := enterprise8021xPatch(cfg, false)
		require.NoError(t, err, name)
		assert.Equal(t, "new", p["identity"], name)
		for _, k := range tt.lacks {
			assert.NotContains(t, p, k, name)
		}
	}
}
