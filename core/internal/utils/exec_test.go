package utils

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCommandExistsFallsBackToLocalBin(t *testing.T) {
	home := t.TempDir()
	binDir := filepath.Join(home, ".local", "bin")
	require.NoError(t, os.MkdirAll(binDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(binDir, "pywalfox"), []byte("#!/bin/sh\n"), 0o755))

	t.Setenv("HOME", home)
	t.Setenv("PATH", t.TempDir())

	assert.True(t, CommandExists("pywalfox"))
}

func TestCommandExistsIgnoresNonExecutableLocalBinFile(t *testing.T) {
	home := t.TempDir()
	binDir := filepath.Join(home, ".local", "bin")
	require.NoError(t, os.MkdirAll(binDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(binDir, "pywalfox"), []byte("not executable"), 0o644))

	t.Setenv("HOME", home)
	t.Setenv("PATH", t.TempDir())

	assert.False(t, CommandExists("pywalfox"))
}

func TestEnvWithUserBinPathPrependsLocalBin(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	env := EnvWithUserBinPath([]string{"PATH=/usr/bin", "OTHER=value"})
	var pathValue string
	for _, entry := range env {
		if after, ok := strings.CutPrefix(entry, "PATH="); ok {
			pathValue = after
			break
		}
	}

	parts := filepath.SplitList(pathValue)
	require.NotEmpty(t, parts)
	assert.Equal(t, filepath.Join(home, ".local", "bin"), parts[0])
	assert.Equal(t, filepath.Join(home, ".nix-profile", "bin"), parts[1])
	assert.Contains(t, parts, filepath.Join("/etc/profiles/per-user", filepath.Base(home), "bin"))
	assert.Contains(t, parts, "/usr/local/bin")
	assert.Contains(t, env, "OTHER=value")
}
