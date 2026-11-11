package plugins

import (
	"testing"

	coreplugins "github.com/duxlabs-dev/dux-shell/core/internal/plugins"
	"github.com/stretchr/testify/assert"
)

func TestSortPluginInfoByFirstParty(t *testing.T) {
	plugins := []PluginInfo{
		{Name: "third-party", Repo: "https://github.com/other/test"},
		{Name: "first-party", Repo: "https://github.com/AvengeMedia/test"},
	}

	SortPluginInfoByFirstParty(plugins)

	assert.Equal(t, "first-party", plugins[0].Name)
	assert.Equal(t, "third-party", plugins[1].Name)
}

func TestNormalizeScreenshotURL(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want string
	}{
		{
			name: "raw github url is unchanged",
			raw:  "https://raw.githubusercontent.com/alcxyz/DankVault/main/docs/screenshot.png",
			want: "https://raw.githubusercontent.com/alcxyz/DankVault/main/docs/screenshot.png",
		},
		{
			name: "github blob url becomes raw content url",
			raw:  "https://github.com/acmagn/DMS-UPS-Monitor/blob/main/assets/screenshot.png",
			want: "https://raw.githubusercontent.com/acmagn/DMS-UPS-Monitor/main/assets/screenshot.png",
		},
		{
			name: "github raw url becomes raw content url",
			raw:  "https://github.com/antonjah/nix-monitor/raw/master/assets/scrot.png",
			want: "https://raw.githubusercontent.com/antonjah/nix-monitor/master/assets/scrot.png",
		},
		{
			name: "non github url is unchanged",
			raw:  "https://example.com/screenshot.png",
			want: "https://example.com/screenshot.png",
		},
		{
			name: "empty url is empty",
			raw:  " ",
			want: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, normalizeScreenshotURL(tt.raw))
		})
	}
}

func TestPluginInfoFromPluginIncludesScreenshot(t *testing.T) {
	info := pluginInfoFromPlugin(coreplugins.Plugin{
		ID:         "dankVault",
		Name:       "Vault",
		Repo:       "https://github.com/duxlabs-dev/dux-plugins",
		Screenshot: "https://github.com/duxlabs-dev/dux-plugins/blob/master/DankNotepadModule/screenshot.png",
	})

	assert.Equal(t, "https://raw.githubusercontent.com/duxlabs-dev/dux-plugins/master/DankNotepadModule/screenshot.png", info.Screenshot)
	assert.True(t, info.FirstParty)
}
