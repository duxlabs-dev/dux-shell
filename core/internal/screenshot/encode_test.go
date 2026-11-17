package screenshot

import (
	"encoding/binary"
	"path/filepath"
	"testing"
)

func newTenBitBuffer(t *testing.T, format PixelFormat, v uint32) *ShmBuffer {
	t.Helper()
	buf, err := CreateShmBuffer(1, 1, 4)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { buf.Close() })
	buf.Format = format
	binary.LittleEndian.PutUint32(buf.Data(), v)
	return buf
}

func TestBufferToImageWithFormat10Bit(t *testing.T) {
	const r10, g10, b10 = uint32(1023), uint32(512), uint32(0)

	cases := []struct {
		name   string
		format PixelFormat
		v      uint32
	}{
		{"XRGB2101010", FormatXRGB2101010, r10<<20 | g10<<10 | b10},
		{"XBGR2101010", FormatXBGR2101010, b10<<20 | g10<<10 | r10},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			buf := newTenBitBuffer(t, tc.format, tc.v)
			img := BufferToImageWithFormat(buf, uint32(tc.format))

			want := [4]uint8{255, 128, 0, 255}
			var got [4]uint8
			copy(got[:], img.Pix)
			if got != want {
				t.Errorf("pixel = %v, want %v", got, want)
			}
		})
	}
}

func TestGetOutputDirWithoutUserDirs(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("XDG_PICTURES_DIR", "")
	t.Setenv("DMS_SCREENSHOT_DIR", "")

	want := filepath.Join(home, "Pictures", "Screenshots")
	if got := GetOutputDir(); got != want {
		t.Fatalf("GetOutputDir() = %q, want %q", got, want)
	}
}
