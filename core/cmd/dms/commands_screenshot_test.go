package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/screenshot"
)

func thumbnailTestBuffer(t testing.TB, width, height int) *screenshot.ShmBuffer {
	t.Helper()
	buf, err := screenshot.CreateShmBuffer(width, height, width*4+16)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { buf.Close() })
	return buf
}

func TestBufferToRGBAThumbnailPixels(t *testing.T) {
	formats := []struct {
		name   string
		format screenshot.PixelFormat
		swapRB bool
		tenBit bool
	}{
		{"argb", screenshot.FormatARGB8888, true, false},
		{"xrgb", screenshot.FormatXRGB8888, true, false},
		{"abgr", screenshot.FormatABGR8888, false, false},
		{"xbgr", screenshot.FormatXBGR8888, false, false},
		{"argb10", screenshot.FormatARGB2101010, true, true},
		{"xrgb10", screenshot.FormatXRGB2101010, true, true},
		{"abgr10", screenshot.FormatABGR2101010, false, true},
		{"xbgr10", screenshot.FormatXBGR2101010, false, true},
	}
	for _, tc := range formats {
		t.Run(tc.name, func(t *testing.T) {
			buf := thumbnailTestBuffer(t, 4, 2)
			data := buf.Data()
			var originalRGBA []byte
			for y := range buf.Height {
				for x := range buf.Width {
					r, g, b := byte(20), byte(40), byte(60)
					if (x+y)%2 != 0 {
						r, g, b = 100, 160, 220
					}
					originalRGBA = append(originalRGBA, r, g, b, 255)
					if tc.swapRB {
						r, b = b, r
					}
					i := y*buf.Stride + x*4
					if tc.tenBit {
						binary.LittleEndian.PutUint32(data[i:], uint32(r)<<2|uint32(g)<<12|uint32(b)<<22)
						continue
					}
					data[i], data[i+1], data[i+2] = r, g, b
				}
			}
			original := bytes.Clone(data)
			got, width, height := bufferToRGBAThumbnail(buf, 2, uint32(tc.format))
			want := []byte{60, 100, 140, 255, 60, 100, 140, 255}
			if width != 2 || height != 1 || !bytes.Equal(got, want) {
				t.Fatalf("averaged thumbnail = %dx%d %v, want 2x1 %v", width, height, got, want)
			}
			got, width, height = bufferToRGBAThumbnail(buf, 640, uint32(tc.format))
			if width != 4 || height != 2 || !bytes.Equal(got, originalRGBA) {
				t.Fatalf("unscaled thumbnail = %dx%d %v, want 4x2 %v", width, height, got, originalRGBA)
			}
			if !bytes.Equal(data, original) {
				t.Fatal("source pixels changed")
			}
		})
	}
}

func TestBufferToRGBAThumbnailDimensions(t *testing.T) {
	for _, tc := range []struct {
		width, height         int
		wantWidth, wantHeight int
	}{
		{1920, 1080, 640, 360},
		{1080, 1920, 360, 640},
		{1365, 767, 640, 359},
		{1, 10000, 1, 640},
		{10000, 1, 640, 1},
		{1, 1, 1, 1},
	} {
		t.Run(fmt.Sprintf("%dx%d", tc.width, tc.height), func(t *testing.T) {
			buf := thumbnailTestBuffer(t, tc.width, tc.height)
			got, width, height := bufferToRGBAThumbnail(buf, 640, uint32(screenshot.FormatXRGB8888))
			if width != tc.wantWidth || height != tc.wantHeight || len(got) != width*height*4 {
				t.Fatalf("thumbnail = %dx%d, %d bytes; want %dx%d RGBA", width, height, len(got), tc.wantWidth, tc.wantHeight)
			}
		})
	}
}

func TestBufferToRGBAThumbnailOddWidthRows(t *testing.T) {
	for _, width := range []int{319, 321, 361} {
		t.Run(fmt.Sprint(width), func(t *testing.T) {
			buf := thumbnailTestBuffer(t, width, 64)
			data := buf.Data()
			for y := range buf.Height {
				for x := range width {
					i := y*buf.Stride + x*4
					data[i], data[i+1], data[i+2] = byte(y), byte(x>>8), byte(x)
				}
			}
			got, gotWidth, height := bufferToRGBAThumbnail(buf, 640, uint32(screenshot.FormatXRGB8888))
			if gotWidth != width || height != buf.Height || len(got) != width*height*4 {
				t.Fatalf("thumbnail = %dx%d, %d bytes; want %dx%d RGBA", gotWidth, height, len(got), width, buf.Height)
			}
			for y := range height {
				for x := range width {
					i := y*width*4 + x*4
					want := []byte{byte(x), byte(x >> 8), byte(y), 255}
					if !bytes.Equal(got[i:i+4], want) {
						t.Fatalf("pixel (%d, %d) = %v, want %v", x, y, got[i:i+4], want)
					}
				}
			}
		})
	}
}

func TestBufferToRGBAThumbnailEmpty(t *testing.T) {
	for _, buf := range []*screenshot.ShmBuffer{nil, {}} {
		data, width, height := bufferToRGBAThumbnail(buf, 640, uint32(screenshot.FormatXRGB8888))
		if data != nil || width != 0 || height != 0 {
			t.Fatalf("empty thumbnail = %dx%d %v", width, height, data)
		}
	}
}

func BenchmarkBufferToRGBAThumbnail(b *testing.B) {
	for _, size := range [][2]int{{3840, 2160}, {3840, 3840}, {1920, 10000}} {
		b.Run(fmt.Sprintf("%dx%d", size[0], size[1]), func(b *testing.B) {
			buf := thumbnailTestBuffer(b, size[0], size[1])
			b.ReportAllocs()
			for b.Loop() {
				bufferToRGBAThumbnail(buf, 640, uint32(screenshot.FormatXRGB8888))
			}
		})
	}
}
