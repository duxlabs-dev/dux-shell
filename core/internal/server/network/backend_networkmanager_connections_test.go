package network

import (
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	mock_dbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"maps"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

type editorFixture struct {
	backend  *NetworkManagerBackend
	nm       *mock_gonetworkmanager.MockNetworkManager
	settings *mock_gonetworkmanager.MockSettings
	objects  map[dbus.ObjectPath]*mock_dbus.MockBusObject
}

func newEditorFixture(t *testing.T) *editorFixture {
	f := &editorFixture{
		nm:       mock_gonetworkmanager.NewMockNetworkManager(t),
		settings: mock_gonetworkmanager.NewMockSettings(t),
		objects:  map[dbus.ObjectPath]*mock_dbus.MockBusObject{},
	}
	var err error
	f.backend, err = NewNetworkManagerBackend(f.nm)
	require.NoError(t, err)
	f.backend.settings = f.settings
	f.backend.nmObjectFn = func(p dbus.ObjectPath) dbus.BusObject {
		obj, ok := f.objects[p]
		require.True(t, ok, "unexpected object %s", p)
		return obj
	}
	return f
}

func (f *editorFixture) object(t *testing.T, path dbus.ObjectPath) *mock_dbus.MockBusObject {
	f.objects[path] = mock_dbus.NewMockBusObject(t)
	return f.objects[path]
}

func (f *editorFixture) profile(t *testing.T, uuid string, path dbus.ObjectPath) *mock_dbus.MockBusObject {
	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetPath().Return(path).Maybe()
	f.settings.EXPECT().GetConnectionByUUID(uuid).Return(conn, nil).Maybe()
	return f.object(t, path)
}

func connSection(uuid, id, typ string, extra map[string]dbus.Variant) nmSettings {
	c := map[string]dbus.Variant{"uuid": dbus.MakeVariant(uuid), "id": dbus.MakeVariant(id), "type": dbus.MakeVariant(typ)}
	maps.Copy(c, extra)
	return nmSettings{"connection": c}
}

func TestExportConnectionProfile_WireGuard(t *testing.T) {
	export := func(t *testing.T, path string) error {
		f := newEditorFixture(t)
		s := connSection("u1", "wg", "wireguard", nil)
		s["wireguard"] = map[string]dbus.Variant{"private-key-flags": dbus.MakeVariant(uint32(0)), "peers": dbus.MakeVariant([]map[string]dbus.Variant{
			{"public-key": dbus.MakeVariant("PUB1"), "allowed-ips": dbus.MakeVariant([]string{"10.0.0.0/24"})},
		})}
		obj := f.profile(t, "u1", "/s/1")
		expectGetSettings(obj, s)
		expectGetSecrets(obj, "wireguard", nmSettings{"wireguard": {"private-key": dbus.MakeVariant("PRIV")}})
		return f.backend.ExportConnectionProfile("u1", path)
	}
	dir := t.TempDir()
	path := filepath.Join(dir, "wg0.conf")
	require.NoError(t, os.WriteFile(path, []byte(strings.Repeat("old", 100)), 0o644))
	require.NoError(t, os.Chmod(path, 0o644))
	require.NoError(t, export(t, path))
	info, err := os.Stat(path)
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0o600), info.Mode().Perm(), "existing 0644 file is tightened")
	content, err := os.ReadFile(path)
	require.NoError(t, err)
	assert.Equal(t, "[Interface]\nPrivateKey = PRIV\n\n[Peer]\nPublicKey = PUB1\nAllowedIPs = 10.0.0.0/24\n", string(content))
	link := filepath.Join(dir, "link.conf")
	require.NoError(t, os.Symlink(filepath.Join(dir, "target"), link))
	assert.Error(t, export(t, link))
	assert.NoFileExists(t, filepath.Join(dir, "target"))
	fifo := filepath.Join(dir, "fifo.conf")
	require.NoError(t, syscall.Mkfifo(fifo, 0o600))
	assert.Error(t, export(t, fifo))
	info, err = os.Lstat(fifo)
	require.NoError(t, err)
	assert.Equal(t, os.ModeNamedPipe, info.Mode().Type())
}
