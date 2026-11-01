package plugins

import (
	"encoding/json"
	"testing"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/mocks/net"
	coreplugins "github.com/duxlabs-dev/dux-shell/core/internal/plugins"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func TestHandleInstallMissingName(t *testing.T) {
	mc := net.NewMockConn(t)
	mc.EXPECT().SetWriteDeadline(mock.Anything).Return(nil).Maybe()
	conn := ipc.NewConnWriter(mc)
	var written []byte
	mc.EXPECT().Write(mock.Anything).RunAndReturn(func(b []byte) (int, error) {
		written = b
		return len(b), nil
	}).Maybe()

	req := ipc.Request{
		ID:     123,
		Method: "plugins.install",
		Params: map[string]any{},
	}

	HandleInstall(conn, req)

	var resp ipc.Response[SuccessResult]
	err := json.Unmarshal(written, &resp)
	assert.NoError(t, err)
	assert.NotEmpty(t, resp.Error)
	assert.Contains(t, resp.Error, "missing or invalid 'name' parameter")
}

func TestHandleUninstallMissingName(t *testing.T) {
	mc := net.NewMockConn(t)
	mc.EXPECT().SetWriteDeadline(mock.Anything).Return(nil).Maybe()
	conn := ipc.NewConnWriter(mc)
	var written []byte
	mc.EXPECT().Write(mock.Anything).RunAndReturn(func(b []byte) (int, error) {
		written = b
		return len(b), nil
	}).Maybe()

	req := ipc.Request{
		ID:     123,
		Method: "plugins.uninstall",
		Params: map[string]any{},
	}

	HandleUninstall(conn, req)

	var resp ipc.Response[SuccessResult]
	err := json.Unmarshal(written, &resp)
	assert.NoError(t, err)
	assert.NotEmpty(t, resp.Error)
}

func TestHandleUpdateMissingName(t *testing.T) {
	mc := net.NewMockConn(t)
	mc.EXPECT().SetWriteDeadline(mock.Anything).Return(nil).Maybe()
	conn := ipc.NewConnWriter(mc)
	var written []byte
	mc.EXPECT().Write(mock.Anything).RunAndReturn(func(b []byte) (int, error) {
		written = b
		return len(b), nil
	}).Maybe()

	req := ipc.Request{
		ID:     123,
		Method: "plugins.update",
		Params: map[string]any{},
	}

	HandleUpdate(conn, req)

	var resp ipc.Response[SuccessResult]
	err := json.Unmarshal(written, &resp)
	assert.NoError(t, err)
	assert.NotEmpty(t, resp.Error)
}

func TestHandleSearchMissingQuery(t *testing.T) {
	mc := net.NewMockConn(t)
	mc.EXPECT().SetWriteDeadline(mock.Anything).Return(nil).Maybe()
	conn := ipc.NewConnWriter(mc)
	var written []byte
	mc.EXPECT().Write(mock.Anything).RunAndReturn(func(b []byte) (int, error) {
		written = b
		return len(b), nil
	}).Maybe()

	req := ipc.Request{
		ID:     123,
		Method: "plugins.search",
		Params: map[string]any{},
	}

	HandleSearch(conn, req)

	var resp ipc.Response[[]PluginInfo]
	err := json.Unmarshal(written, &resp)
	assert.NoError(t, err)
	assert.NotEmpty(t, resp.Error)
}

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

func TestApplyFeedbackCarriesDirectoryMetadata(t *testing.T) {
	info := pluginInfoFromPlugin(coreplugins.Plugin{ID: "demo", Name: "Demo"})

	applyFeedback(&info, coreplugins.Feedback{
		Upvotes:     7,
		Status:      []string{"reviewed"},
		IssueURL:    "https://example.com/issues/1",
		Similar:     []string{"other"},
		Version:     "1.2.0",
		Icon:        "extension",
		Permissions: []string{"settings_read"},
		CreatedAt:   "2026-01-02T03:04:05Z",
		UpdatedAt:   "2026-02-03T04:05:06Z",
	})

	raw, err := json.Marshal(info)
	assert.NoError(t, err)

	var decoded map[string]any
	assert.NoError(t, json.Unmarshal(raw, &decoded))
	assert.Equal(t, float64(7), decoded["upvotes"])
	assert.Equal(t, "1.2.0", decoded["version"])
	assert.Equal(t, "extension", decoded["icon"])
	assert.Equal(t, []any{"settings_read"}, decoded["permissions"])
	assert.Equal(t, "2026-01-02T03:04:05Z", decoded["created_at"])
	assert.Equal(t, "2026-02-03T04:05:06Z", decoded["updated_at"])
}

func TestApplyFeedbackOmitsMissingMetadata(t *testing.T) {
	info := pluginInfoFromPlugin(coreplugins.Plugin{ID: "demo", Name: "Demo"})

	applyFeedback(&info, coreplugins.Feedback{})

	raw, err := json.Marshal(info)
	assert.NoError(t, err)
	assert.NotContains(t, string(raw), "created_at")
	assert.NotContains(t, string(raw), "updated_at")
	assert.NotContains(t, string(raw), "version")
}
