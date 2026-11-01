package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestProbeNiriCapabilities(t *testing.T) {
	cases := []struct {
		name     string
		accepts  map[string]bool
		mismatch bool
		want     []string
	}{
		{"niri 26.04", nil, false, nil},
		{"niri main", map[string]bool{NiriBindsNextConfig: true, niriConfigNextProbe: true}, false, []string{NiriCapBindsNext, NiriCapConfigNext}},
		{"binds only", map[string]bool{NiriBindsNextConfig: true}, false, []string{NiriCapBindsNext}},
		{"upgraded mid-session", map[string]bool{NiriBindsNextConfig: true, niriConfigNextProbe: true}, true, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := probeNiriCapabilities(func(s string) bool { return tc.accepts[s] }, func() bool { return tc.mismatch })
			assert.Equal(t, tc.want, got)
		})
	}
}

func TestDeployNiriWritesBindsNextOnlyWhenChanged(t *testing.T) {
	prev := niriCapabilityProbe
	t.Cleanup(func() { niriCapabilityProbe = prev })

	t.Setenv("HOME", t.TempDir())
	path := filepath.Join(os.Getenv("HOME"), ".config", "niri", "dms", NiriBindsNextFile)
	old := time.Now().Add(-time.Hour).Truncate(time.Second)

	for _, tc := range []struct {
		caps []string
		want string
	}{
		{nil, NiriBindsNext2604Config},
		{[]string{NiriCapBindsNext}, NiriBindsNextConfig},
	} {
		niriCapabilityProbe = func() []string { return tc.caps }
		_, err := NewConfigDeployer(nil).deployNiriConfig("kitty", true)
		require.NoError(t, err)
		got, err := os.ReadFile(path)
		require.NoError(t, err)
		assert.Equal(t, tc.want, string(got))

		require.NoError(t, os.Chtimes(path, old, old))
		written, err := WriteNiriBindsNext(filepath.Dir(path), tc.caps)
		require.NoError(t, err)
		assert.False(t, written)
		info, err := os.Stat(path)
		require.NoError(t, err)
		assert.True(t, info.ModTime().Equal(old), "unchanged content must not touch the file niri watches")
	}
}
