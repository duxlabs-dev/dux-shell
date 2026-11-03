package clipboard

import (
	"bytes"
	"image"
	"image/png"
	"testing"

	"github.com/duxlabs-dev/dux-go/wlclipboard"
	"github.com/stretchr/testify/assert"
)

func TestFileOffers(t *testing.T) {
	var buf bytes.Buffer
	assert.NoError(t, png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 2, 2))))
	pngData := buf.Bytes()

	assert.Equal(t, []wlclipboard.Offer{
		{MimeType: "x-special/gnome-copied-files", Data: []byte("copy\nfile:///exported/shot.png")},
		{MimeType: "text/uri-list", Data: []byte("file:///exported/shot.png\r\n")},
		{MimeType: "text/plain", Data: []byte("/home/u/shot.png")},
		{MimeType: "image/png", Data: pngData},
	}, FileOffers("/exported/shot.png", "/home/u/shot.png", pngData))

	assert.Equal(t, []wlclipboard.Offer{
		{MimeType: "x-special/gnome-copied-files", Data: []byte("copy\nfile:///tmp/my%20notes%23.txt")},
		{MimeType: "text/uri-list", Data: []byte("file:///tmp/my%20notes%23.txt\r\n")},
		{MimeType: "text/plain", Data: []byte("/tmp/my notes#.txt")},
	}, FileOffers("/tmp/my notes#.txt", "/tmp/my notes#.txt", []byte("hello")))
}
