package plugins

import (
	"path/filepath"
	"testing"

	"github.com/spf13/afero"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWeatherProvider(t *testing.T) {
	manager, fs, pluginsDir := setupTestManager(t)
	write := func(id, manifest string) {
		require.NoError(t, afero.WriteFile(fs, filepath.Join(pluginsDir, id, "plugin.json"), []byte(manifest), 0o644))
	}
	write("meteoswiss", `{"id":"meteoswiss","name":"MeteoSwiss","weather":{"command":"bin/fetch","url":"https://meteoswiss.admin.ch"}}`)
	write("named", `{"id":"named","name":"Plugin","weather":{"command":"fetch","name":"Provider"}}`)
	write("nocommand", `{"id":"nocommand","name":"Empty","weather":{"name":"Empty"}}`)
	write("lyricsonly", `{"id":"lyricsonly","name":"Lyrics","lyrics":{"command":"fetch"}}`)

	provider, ok := manager.WeatherProvider("meteoswiss")
	require.True(t, ok)
	assert.Equal(t, WeatherProvider{Command: filepath.Join(pluginsDir, "meteoswiss", "bin/fetch"), Name: "MeteoSwiss", URL: "https://meteoswiss.admin.ch"}, provider)

	provider, ok = manager.WeatherProvider("named")
	require.True(t, ok)
	assert.Equal(t, "Provider", provider.Name)

	for _, id := range []string{"nocommand", "lyricsonly", "missing"} {
		_, ok := manager.WeatherProvider(id)
		assert.False(t, ok, id)
	}
}
