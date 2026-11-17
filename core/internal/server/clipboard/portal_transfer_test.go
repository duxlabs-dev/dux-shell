package clipboard

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type fakePortalClient struct {
	keys    []string
	stopped []string
	added   map[string]int
}

func (f *fakePortalClient) StartTransfer(_ context.Context) (string, error) {
	key := "key-" + string(rune('a'+len(f.keys)))
	f.keys = append(f.keys, key)
	return key, nil
}

func (f *fakePortalClient) AddFiles(_ context.Context, key string, fds []dbus.UnixFD) error {
	if f.added == nil {
		f.added = make(map[string]int)
	}
	f.added[key] += len(fds)
	return nil
}

func (f *fakePortalClient) StopTransfer(_ context.Context, key string) {
	f.stopped = append(f.stopped, key)
}

func TestExtensionForMime(t *testing.T) {
	assert.Equal(t, ".png", extensionForMime("image/png"))
	assert.Equal(t, ".jpg", extensionForMime("IMAGE/JPEG; charset=utf-8"))
	assert.Equal(t, ".webp", extensionForMime("image/webp"))
	assert.Equal(t, ".txt", extensionForMime("text/plain;charset=utf-8"))
	assert.Equal(t, ".bin", extensionForMime("application/x-unknown-dms-test"))
}

func TestCleanupExpiredDragFiles(t *testing.T) {
	dir := t.TempDir()
	oldFile := filepath.Join(dir, "old.png")
	newFile := filepath.Join(dir, "new.png")
	require.NoError(t, os.WriteFile(oldFile, []byte("old"), 0o600))
	require.NoError(t, os.WriteFile(newFile, []byte("new"), 0o600))

	expired := time.Now().Add(-dragTempFileTTL - time.Minute)
	require.NoError(t, os.Chtimes(oldFile, expired, expired))

	cleanupExpiredDragFiles(dir)

	_, oldErr := os.Stat(oldFile)
	_, newErr := os.Stat(newFile)
	assert.True(t, os.IsNotExist(oldErr))
	assert.NoError(t, newErr)
}

func TestExportPortalTransferReplacesPreviousKey(t *testing.T) {
	tmpFile := filepath.Join(t.TempDir(), "sample.png")
	require.NoError(t, os.WriteFile(tmpFile, []byte("png"), 0o600))

	m := &Manager{}
	client := &fakePortalClient{}

	first, err := m.exportPortalTransfer(context.Background(), client, []string{tmpFile})
	require.NoError(t, err)
	assert.Equal(t, "key-a", first)
	assert.Equal(t, 1, client.added["key-a"])
	assert.Empty(t, client.stopped)

	second, err := m.exportPortalTransfer(context.Background(), client, []string{tmpFile})
	require.NoError(t, err)
	assert.Equal(t, "key-b", second)
	assert.Equal(t, []string{"key-a"}, client.stopped)
	assert.Equal(t, "key-b", m.portalKey)
}

func TestParseURIListFiles(t *testing.T) {
	dir := t.TempDir()
	first := filepath.Join(dir, "my photo.png")
	second := filepath.Join(dir, "second.txt")
	require.NoError(t, os.WriteFile(first, []byte("png"), 0o600))
	require.NoError(t, os.WriteFile(second, []byte("txt"), 0o600))

	raw := "file://" + dir + "/my%20photo.png\r\n# comment\r\nfile://" + second + "\r\nfile://" + filepath.Join(dir, "missing.txt") + "\r\n"
	uris, paths := parseURIListFiles([]byte(raw))

	assert.Equal(t, []string{first, second}, paths)
	assert.Equal(t, []string{
		"file://" + dir + "/my%20photo.png",
		"file://" + second,
	}, uris)
}
