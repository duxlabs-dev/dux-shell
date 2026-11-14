package freedesktop

import (
	"image"
	"image/png"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStageIconFile(t *testing.T) {
	t.Run("empty path is passed through", func(t *testing.T) {
		staged, cleanup, err := stageIconFile("")
		require.NoError(t, err)
		assert.Equal(t, "", staged)
		cleanup()
	})

	t.Run("missing file", func(t *testing.T) {
		_, cleanup, err := stageIconFile(filepath.Join(t.TempDir(), "missing.png"))
		assert.Error(t, err)
		cleanup()
	})

	t.Run("copies content and cleanup removes the copy", func(t *testing.T) {
		src := filepath.Join(t.TempDir(), "avatar.png")
		require.NoError(t, os.WriteFile(src, []byte("image-bytes"), 0o600))

		staged, cleanup, err := stageIconFile(src)
		require.NoError(t, err)
		assert.NotEqual(t, src, staged)

		data, err := os.ReadFile(staged)
		require.NoError(t, err)
		assert.Equal(t, []byte("image-bytes"), data)

		cleanup()
		_, err = os.Stat(staged)
		assert.True(t, os.IsNotExist(err))
	})
}

func TestStageIconFileDownscalesLargeImages(t *testing.T) {
	src := filepath.Join(t.TempDir(), "big.png")
	f, err := os.Create(src)
	require.NoError(t, err)
	require.NoError(t, png.Encode(f, image.NewRGBA(image.Rect(0, 0, 1200, 800))))
	require.NoError(t, f.Close())

	staged, cleanup, err := stageIconFile(src)
	require.NoError(t, err)
	defer cleanup()

	out, err := os.Open(staged)
	require.NoError(t, err)
	defer out.Close()
	cfg, _, err := image.DecodeConfig(out)
	require.NoError(t, err)
	assert.Equal(t, 384, cfg.Width)
	assert.Equal(t, iconSize, cfg.Height)
}
