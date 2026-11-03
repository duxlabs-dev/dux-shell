package screenshot

import "github.com/duxlabs-dev/dux-shell/core/internal/wayland/shm"

type PixelFormat = shm.PixelFormat

const (
	FormatARGB8888 = shm.FormatARGB8888
	FormatXRGB8888 = shm.FormatXRGB8888
	FormatABGR8888 = shm.FormatABGR8888
	FormatXBGR8888 = shm.FormatXBGR8888
	FormatRGB888   = shm.FormatRGB888
	FormatBGR888   = shm.FormatBGR888

	FormatARGB2101010 = shm.FormatARGB2101010
	FormatXRGB2101010 = shm.FormatXRGB2101010
	FormatABGR2101010 = shm.FormatABGR2101010
	FormatXBGR2101010 = shm.FormatXBGR2101010
)

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

type ShmBuffer = shm.Buffer

func CreateShmBuffer(width, height, stride int) (*ShmBuffer, error) {
	return shm.CreateBuffer(width, height, stride)
}

func InverseTransform(transform int32) int32 {
	return shm.InverseTransform(transform)
}
