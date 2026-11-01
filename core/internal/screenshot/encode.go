package screenshot

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

func BufferToImage(buf *ShmBuffer) *image.RGBA {
	return BufferToImageWithFormat(buf, uint32(FormatARGB8888))
}

func tenBitSwapRB(format uint32) bool {
	return format == uint32(FormatARGB2101010) || format == uint32(FormatXRGB2101010)
}

func tenBitRowsToRGBA(buf *ShmBuffer, format uint32, y0, y1 int) *image.RGBA {
	img := image.NewRGBA(image.Rect(0, 0, buf.Width, y1-y0))
	data := buf.Data()
	swapRB := tenBitSwapRB(format)

	for y := y0; y < y1; y++ {
		srcOff := y * buf.Stride
		dstOff := (y - y0) * img.Stride
		for x := 0; x < buf.Width; x++ {
			si := srcOff + x*4
			di := dstOff + x*4
			if si+4 > len(data) || di+4 > len(img.Pix) {
				continue
			}
			v := binary.LittleEndian.Uint32(data[si:])
			c0, c1, c2 := uint8(v>>2), uint8(v>>12), uint8(v>>22)
			if swapRB {
				c0, c2 = c2, c0
			}
			img.Pix[di+0], img.Pix[di+1], img.Pix[di+2], img.Pix[di+3] = c0, c1, c2, 255
		}
	}
	return img
}

func BufferToImageWithFormat(buf *ShmBuffer, format uint32) *image.RGBA {
	return bufferRowsToRGBA(buf, format, 0, buf.Height)
}

func bufferRowsToRGBA(buf *ShmBuffer, format uint32, y0, y1 int) *image.RGBA {
	if PixelFormat(format).Is10Bit() {
		return tenBitRowsToRGBA(buf, format, y0, y1)
	}

	img := image.NewRGBA(image.Rect(0, 0, buf.Width, y1-y0))
	data := buf.Data()

	var swapRB bool
	switch format {
	case uint32(FormatABGR8888), uint32(FormatXBGR8888):
		swapRB = false
	default:
		swapRB = true
	}

	for y := y0; y < y1; y++ {
		srcOff := y * buf.Stride
		dstOff := (y - y0) * img.Stride
		for x := 0; x < buf.Width; x++ {
			si := srcOff + x*4
			di := dstOff + x*4
			if si+3 >= len(data) || di+3 >= len(img.Pix) {
				continue
			}
			if swapRB {
				img.Pix[di+0] = data[si+2]
				img.Pix[di+1] = data[si+1]
				img.Pix[di+2] = data[si+0]
			} else {
				img.Pix[di+0] = data[si+0]
				img.Pix[di+1] = data[si+1]
				img.Pix[di+2] = data[si+2]
			}
			img.Pix[di+3] = 255
		}
	}
	return img
}

func ImageToBuffer(img image.Image) (*ShmBuffer, error) {
	bounds := img.Bounds()
	w, h := bounds.Dx(), bounds.Dy()
	buf, err := CreateShmBuffer(w, h, w*4)
	if err != nil {
		return nil, err
	}

	data := buf.Data()
	switch src := img.(type) {
	case *image.NRGBA:
		for y := range h {
			srcOff := y * src.Stride
			dstOff := y * buf.Stride
			for x := range w {
				si, di := srcOff+x*4, dstOff+x*4
				a := uint32(src.Pix[si+3])
				data[di+0] = uint8(uint32(src.Pix[si+2]) * a / 255)
				data[di+1] = uint8(uint32(src.Pix[si+1]) * a / 255)
				data[di+2] = uint8(uint32(src.Pix[si+0]) * a / 255)
				data[di+3] = uint8(a)
			}
		}
	case *image.RGBA:
		for y := range h {
			srcOff := y * src.Stride
			dstOff := y * buf.Stride
			for x := range w {
				si, di := srcOff+x*4, dstOff+x*4
				data[di+0] = src.Pix[si+2]
				data[di+1] = src.Pix[si+1]
				data[di+2] = src.Pix[si+0]
				data[di+3] = src.Pix[si+3]
			}
		}
	default:
		for y := range h {
			dstOff := y * buf.Stride
			for x := range w {
				cr, cg, cb, ca := img.At(bounds.Min.X+x, bounds.Min.Y+y).RGBA()
				di := dstOff + x*4
				data[di+0] = uint8(cb >> 8)
				data[di+1] = uint8(cg >> 8)
				data[di+2] = uint8(cr >> 8)
				data[di+3] = uint8(ca >> 8)
			}
		}
	}
	buf.Format = FormatARGB8888
	return buf, nil
}

func EncodeJPEG(w io.Writer, img image.Image, quality int) error {
	return jpeg.Encode(w, img, &jpeg.Options{Quality: quality})
}

func EncodePPM(w io.Writer, img *image.RGBA) error {
	bw := bufio.NewWriter(w)
	bounds := img.Bounds()
	if _, err := fmt.Fprintf(bw, "P6\n%d %d\n255\n", bounds.Dx(), bounds.Dy()); err != nil {
		return err
	}
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			off := (y-bounds.Min.Y)*img.Stride + (x-bounds.Min.X)*4
			if err := bw.WriteByte(img.Pix[off+0]); err != nil {
				return err
			}
			if err := bw.WriteByte(img.Pix[off+1]); err != nil {
				return err
			}
			if err := bw.WriteByte(img.Pix[off+2]); err != nil {
				return err
			}
		}
	}
	return bw.Flush()
}

func GenerateFilename(format Format) string {
	t := time.Now()
	ext := "png"
	switch format {
	case FormatJPEG:
		ext = "jpg"
	case FormatPPM:
		ext = "ppm"
	}
	return fmt.Sprintf("screenshot_%s.%s", t.Format("2006-01-02_15-04-05"), ext)
}

func GetOutputDir() string {
	if dir := os.Getenv("DMS_SCREENSHOT_DIR"); dir != "" {
		return dir
	}

	if xdgPics := utils.XDGPicturesDir(); xdgPics != "" {
		screenshotDir := filepath.Join(xdgPics, "Screenshots")
		if err := os.MkdirAll(screenshotDir, 0o755); err == nil {
			return screenshotDir
		}
		return xdgPics
	}

	if home, err := os.UserHomeDir(); err == nil {
		return home
	}
	return "."
}

func WriteToFile(buf *ShmBuffer, path string, format Format, quality int) error {
	return WriteToFileWithFormat(buf, path, format, quality, uint32(FormatARGB8888), nil)
}

func WriteToFileWithFormat(buf *ShmBuffer, path string, format Format, quality int, pixelFormat uint32, cicp *CICP) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	switch format {
	case FormatJPEG:
		return EncodeBufferJPEG(f, buf, pixelFormat, quality)
	case FormatPPM:
		return EncodePPM(f, BufferToImageWithFormat(buf, pixelFormat))
	default:
		return EncodeBufferPNG(f, buf, pixelFormat, cicp)
	}
}
