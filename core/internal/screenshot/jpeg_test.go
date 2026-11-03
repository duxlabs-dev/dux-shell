package screenshot

import (
	"bytes"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"testing"
)

func noiseBuffer(t testing.TB, w, h int, format PixelFormat) *ShmBuffer {
	t.Helper()
	buf, err := CreateShmBuffer(w, h, w*4+16)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { buf.Close() })
	fillNoise(buf.Data(), uint64(w*h))
	buf.Format = format
	return buf
}

func decodeJPEGPix(t *testing.T, data []byte) *image.RGBA {
	t.Helper()
	dec, err := jpeg.Decode(bytes.NewReader(data))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	out := image.NewRGBA(dec.Bounds())
	for y := dec.Bounds().Min.Y; y < dec.Bounds().Max.Y; y++ {
		for x := dec.Bounds().Min.X; x < dec.Bounds().Max.X; x++ {
			out.Set(x, y, dec.At(x, y))
		}
	}
	return out
}

func TestEncodeBufferJPEGMatchesSerial(t *testing.T) {
	sizes := []image.Point{{64, 64}, {333, 529}, {1366, 731}}
	formats := []PixelFormat{FormatXRGB8888, FormatABGR8888, FormatARGB2101010}

	for _, sz := range sizes {
		for _, format := range formats {
			t.Run(fmt.Sprintf("%dx%d-%d", sz.X, sz.Y, format), func(t *testing.T) {
				buf := noiseBuffer(t, sz.X, sz.Y, format)

				var parallel, serial bytes.Buffer
				if err := EncodeBufferJPEG(&parallel, buf, uint32(format), 90); err != nil {
					t.Fatal(err)
				}
				if err := EncodeJPEG(&serial, BufferToImageWithFormat(buf, uint32(format)), 90); err != nil {
					t.Fatal(err)
				}

				got := decodeJPEGPix(t, parallel.Bytes())
				want := decodeJPEGPix(t, serial.Bytes())
				if got.Bounds() != want.Bounds() {
					t.Fatalf("bounds = %v, want %v", got.Bounds(), want.Bounds())
				}
				if !bytes.Equal(got.Pix, want.Pix) {
					t.Error("decoded pixels differ from serial encode")
				}
			})
		}
	}
}

func TestEncodeBufferJPEGEmpty(t *testing.T) {
	buf := &ShmBuffer{}
	if err := EncodeBufferJPEG(io.Discard, buf, uint32(FormatXRGB8888), 90); err == nil {
		t.Error("expected error for empty buffer")
	}
}

func BenchmarkEncodeBufferJPEG(b *testing.B) {
	buf := noiseBuffer(b, 2560, 1440, FormatXRGB8888)
	for b.Loop() {
		if err := EncodeBufferJPEG(io.Discard, buf, uint32(FormatXRGB8888), 90); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkEncodeJPEGSerial(b *testing.B) {
	buf := noiseBuffer(b, 2560, 1440, FormatXRGB8888)
	for b.Loop() {
		if err := EncodeJPEG(io.Discard, BufferToImageWithFormat(buf, uint32(FormatXRGB8888)), 90); err != nil {
			b.Fatal(err)
		}
	}
}
