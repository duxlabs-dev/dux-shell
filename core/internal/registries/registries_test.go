package registries

import (
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/clipolicy"
	"github.com/spf13/afero"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupFs(t *testing.T) afero.Fs {
	t.Setenv("XDG_CONFIG_HOME", "/xdg")
	return afero.NewMemMapFs()
}

func TestAddAndLoad(t *testing.T) {
	fs := setupFs(t)

	require.NoError(t, Add(fs, "extra", "https://example.com/extra.git"))
	require.NoError(t, Add(fs, "another", "https://example.com/another.git"))

	sources := Load(fs)
	require.Len(t, sources, 3)
	assert.Equal(t, OfficialName, sources[0].Name)
	assert.Equal(t, "extra", sources[1].Name)
	assert.Equal(t, "another", sources[2].Name)
	assert.False(t, sources[1].Official())
}

func TestAddValidation(t *testing.T) {
	fs := setupFs(t)

	assert.Error(t, Add(fs, "", "https://example.com/x.git"))
	assert.Error(t, Add(fs, "Has Spaces", "https://example.com/x.git"))
	assert.Error(t, Add(fs, "UPPER", "https://example.com/x.git"))
	assert.Error(t, Add(fs, "../escape", "https://example.com/x.git"))
	assert.Error(t, Add(fs, OfficialName, "https://example.com/x.git"))
	assert.Error(t, Add(fs, "noname", ""))

	require.NoError(t, Add(fs, "extra", "https://example.com/x.git"))
	assert.Error(t, Add(fs, "extra", "https://example.com/other.git"), "duplicate name rejected")
	assert.Error(t, Add(fs, "extra2", "https://example.com/x.git"), "duplicate URL rejected")
}

func TestRemove(t *testing.T) {
	fs := setupFs(t)

	require.NoError(t, Add(fs, "extra", "https://example.com/x.git"))
	require.NoError(t, Remove(fs, "extra"))
	assert.Len(t, Load(fs), 1)

	assert.Error(t, Remove(fs, "extra"), "already removed")
	assert.Error(t, Remove(fs, OfficialName), "official is not removable")
}

func TestLoadIgnoresInvalidConfig(t *testing.T) {
	fs := setupFs(t)

	require.NoError(t, fs.MkdirAll("/xdg/dms", 0o755))
	require.NoError(t, afero.WriteFile(fs, "/xdg/dms/registries.json", []byte("{not json"), 0o644))
	assert.Len(t, Load(fs), 1)

	entries := `[{"name":"ok","url":"https://example.com/ok.git"},{"name":"Bad Name","url":"https://example.com/bad.git"},{"name":"official","url":"https://example.com/spoof.git"},{"name":"nourl","url":""}]`
	require.NoError(t, afero.WriteFile(fs, "/xdg/dms/registries.json", []byte(entries), 0o644))
	sources := Load(fs)
	require.Len(t, sources, 2, "invalid entries dropped")
	assert.Equal(t, "ok", sources[1].Name)
	assert.Equal(t, officialURL, sources[0].URL, "official cannot be spoofed from config")
}

func TestActive(t *testing.T) {
	fs := setupFs(t)
	require.NoError(t, Add(fs, "extra", "https://example.com/extra.git"))

	sources, err := Active(fs)
	require.NoError(t, err)
	require.Len(t, sources, 2)
	assert.Equal(t, Load(fs), sources, "registries are on without a policy")

	require.NoError(t, afero.WriteFile(fs, clipolicy.AdminPath, []byte(`{"disable_registries": true}`), 0o644))
	sources, err = Active(fs)
	require.NoError(t, err)
	assert.Empty(t, sources, "the extra registry is off too")
	assert.Len(t, Load(fs), 2, "Load still reports the configured registries")

	require.NoError(t, afero.WriteFile(fs, clipolicy.AdminPath, []byte("{not json"), 0o644))
	_, err = Active(fs)
	assert.Error(t, err, "a malformed policy is not ignored")
}
