package colorpicker

import "github.com/duxlabs-dev/dux-shell/core/internal/wayland/shm"

type ShmBuffer = shm.Buffer

const (
	TransformNormal     = shm.TransformNormal
	Transform90         = shm.Transform90
	Transform180        = shm.Transform180
	Transform270        = shm.Transform270
	TransformFlipped    = shm.TransformFlipped
	TransformFlipped90  = shm.TransformFlipped90
	TransformFlipped180 = shm.TransformFlipped180
	TransformFlipped270 = shm.TransformFlipped270
)

func CreateShmBuffer(width, height, stride int) (*ShmBuffer, error) {
	return shm.CreateBuffer(width, height, stride)
}

func InverseTransform(transform int32) int32 {
	return shm.InverseTransform(transform)
}

func GetPixelColor(buf *ShmBuffer, x, y int) Color {
	return GetPixelColorWithFormat(buf, x, y, FormatARGB8888)
}

func GetPixelColorWithFormat(buf *ShmBuffer, x, y int, format PixelFormat) Color {
	if x < 0 || x >= buf.Width || y < 0 || y >= buf.Height {
		return Color{}
	}

	data := buf.Data()
	offset := y*buf.Stride + x*4
	if offset+3 >= len(data) {
		return Color{}
	}

	if format == FormatABGR8888 || format == FormatXBGR8888 {
		return Color{
			R: data[offset],
			G: data[offset+1],
			B: data[offset+2],
			A: data[offset+3],
		}
	}
	return Color{
		B: data[offset],
		G: data[offset+1],
		R: data[offset+2],
		A: data[offset+3],
	}
}
