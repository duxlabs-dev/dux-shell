package server

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/niriconf"
	"github.com/stretchr/testify/require"
)

func setupNiriConfig(t *testing.T) {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", home)
	t.Setenv("NIRI_SOCKET", "")
	require.NoError(t, os.MkdirAll(filepath.Join(home, "niri"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(home, "niri", "config.kdl"), []byte("layout {}\n"), 0o644))

	fake, err := filepath.Abs("../niriconf/testdata/fake-niri.sh")
	require.NoError(t, err)
	oldBin := niriconf.NiriBin
	niriconf.NiriBin = fake
	niriConfigStore = sync.OnceValue(newNiriConfigStore)
	t.Cleanup(func() {
		niriconf.NiriBin = oldBin
		niriConfigStore = sync.OnceValue(newNiriConfigStore)
	})
}

func callNiriConfig(t *testing.T, method string, params map[string]any) (json.RawMessage, string) {
	t.Helper()
	conn := &mockConn{}
	RouteRequest(context.Background(), ipc.NewConnWriter(conn), ipc.Request{ID: 1, Method: method, Params: params})
	var resp struct {
		Result json.RawMessage `json:"result"`
		Error  string          `json:"error"`
	}
	require.NoError(t, json.Unmarshal(conn.written, &resp), string(conn.written))
	return resp.Result, resp.Error
}

func TestNiriConfigErrors(t *testing.T) {
	setupNiriConfig(t)
	tests := []struct {
		method string
		params map[string]any
		err    string
	}{
		{"niri.config.read", map[string]any{}, "missing or invalid 'fragment' parameter"},
		{"niri.config.read", map[string]any{"fragment": "binds.kdl"}, "bad name"},
		{"niri.config.history", map[string]any{"fragment": "../x.kdl"}, "bad name"},
		{"niri.config.history", map[string]any{"fragment": "outputs.kdl"}, "bad name"},
		{"niri.config.apply", applyParams("Bad.kdl", "", "", custom("")), "bad name"},
		{"niri.config.apply", applyParams("binds.kdl", "", emptyHash, custom("")), "bad name"},
		{"niri.config.apply", applyParams("niri.kdl", "", emptyHash, map[string]any{"binds.kdl": ""}), "bad name"},
		{"niri.config.apply", applyParams("niri.kdl", "", emptyHash, map[string]any{"niri-custom.kdl": "", "binds.kdl": ""}), "bad name"},
		{"niri.config.apply", applyParams("niri.kdl", strings.Repeat("a", maxNiriFragmentSize+1), emptyHash, custom("")), "too large"},
		{"niri.config.apply", applyParams("niri.kdl", "", emptyHash, custom(strings.Repeat("a", maxNiriFragmentSize+1))), "too large"},
		{"niri.config.apply", applyParams("niri.kdl", "layout {}", "stale", custom("")), "changed"},
		{"niri.config.apply", applyParams("niri.kdl", "BAD", emptyHash, custom("")), "invalid: error: bad\n"},
		{"niri.config.restore", map[string]any{"fragment": "niri.kdl", "version": float64(7)}, "no such version"},
		{"niri.config.restore", map[string]any{"fragment": "binds.kdl", "version": float64(1)}, "bad name"},
	}
	for _, tt := range tests {
		t.Run(tt.method+"/"+tt.err, func(t *testing.T) {
			_, errText := callNiriConfig(t, tt.method, tt.params)
			require.Equal(t, tt.err, errText)
		})
	}
}

const emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

func applyParams(fragment, content, baseHash string, extra map[string]any) map[string]any {
	return map[string]any{"fragment": fragment, "content": content, "baseHash": baseHash, "extra": extra}
}

func custom(text string) map[string]any {
	return map[string]any{"niri-custom.kdl": text}
}

func TestNiriConfigErrorsHaveNoPath(t *testing.T) {
	setupNiriConfig(t)
	dir := filepath.Join(os.Getenv("XDG_CONFIG_HOME"), "niri")
	require.NoError(t, os.Remove(filepath.Join(dir, "config.kdl")))

	_, errText := callNiriConfig(t, "niri.config.apply", applyParams("niri.kdl", "layout {}\n", emptyHash, custom("")))
	require.Equal(t, "open: no such file or directory", errText)
}

func TestNiriConfigApplyHashCoversCustom(t *testing.T) {
	setupNiriConfig(t)
	result, errText := callNiriConfig(t, "niri.config.apply", applyParams("niri.kdl", "layout {}\n", emptyHash, custom("layout { gaps 2; }\n")))
	require.Empty(t, errText)
	var applied struct{ Hash string }
	require.NoError(t, json.Unmarshal(result, &applied))

	result, errText = callNiriConfig(t, "niri.config.read", map[string]any{"fragment": "niri.kdl"})
	require.Empty(t, errText)
	var read struct{ Hash string }
	require.NoError(t, json.Unmarshal(result, &read))
	require.Equal(t, applied.Hash, read.Hash)

	dir := filepath.Join(os.Getenv("XDG_CONFIG_HOME"), "niri")
	require.NoError(t, os.WriteFile(filepath.Join(dir, "dms", "niri-custom.kdl"), []byte("by hand\n"), 0o644))
	_, errText = callNiriConfig(t, "niri.config.apply", applyParams("niri.kdl", "layout {}\n", applied.Hash, custom("")))
	require.Equal(t, "changed", errText)
}

func TestNiriConfigApplyThenHistory(t *testing.T) {
	setupNiriConfig(t)

	result, errText := callNiriConfig(t, "niri.config.read", map[string]any{"fragment": "niri.kdl"})
	require.Empty(t, errText)
	var read struct{ Content, Hash string }
	require.NoError(t, json.Unmarshal(result, &read))
	require.Equal(t, emptyHash, read.Hash)

	result, errText = callNiriConfig(t, "niri.config.apply", applyParams("niri.kdl", "layout { gaps 40; }\n", read.Hash, custom("")))
	require.Empty(t, errText)
	var applied struct {
		Version int
		Hash    string
	}
	require.NoError(t, json.Unmarshal(result, &applied))
	require.Equal(t, 1, applied.Version)

	result, errText = callNiriConfig(t, "niri.config.history", map[string]any{"fragment": "niri.kdl"})
	require.Empty(t, errText)
	var history []map[string]any
	require.NoError(t, json.Unmarshal(result, &history))
	require.Len(t, history, 1)
	require.Equal(t, float64(1), history[0]["n"])
	require.Equal(t, applied.Hash, history[0]["hash"])
	require.Equal(t, false, history[0]["failed"])
	require.NotEmpty(t, history[0]["time"])
}

func TestNiriConfigApplyExtra(t *testing.T) {
	setupNiriConfig(t)
	dir := filepath.Join(os.Getenv("XDG_CONFIG_HOME"), "niri")
	apply := func(custom string) string {
		_, errText := callNiriConfig(t, "niri.config.apply", map[string]any{
			"fragment": "niri.kdl", "content": "layout {}\n", "baseHash": emptyHash,
			"extra": map[string]any{"niri-custom.kdl": custom},
		})
		return errText
	}

	require.Equal(t, "invalid: error: bad\n", apply("BAD\n"))
	_, err := os.Stat(filepath.Join(dir, "dms", "niri-custom.kdl"))
	require.ErrorIs(t, err, os.ErrNotExist)

	require.Empty(t, apply("layout { gaps 20; }\n"))
	got, err := os.ReadFile(filepath.Join(dir, "dms", "niri-custom.kdl"))
	require.NoError(t, err)
	require.Equal(t, "layout { gaps 20; }\n", string(got))
	config, err := os.ReadFile(filepath.Join(dir, "config.kdl"))
	require.NoError(t, err)
	require.NotContains(t, string(config), "niri-custom.kdl")
}
