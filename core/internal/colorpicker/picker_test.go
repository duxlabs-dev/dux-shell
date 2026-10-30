package colorpicker

import "testing"

func TestUntransformFrameLeavesAnUprightFrame(t *testing.T) {
	buf, err := CreateShmBuffer(1080, 1920, 1080*4)
	if err != nil {
		t.Fatal(err)
	}
	defer buf.Close()

	output := &Output{width: 1920, height: 1080, transform: Transform90}
	got, err := output.untransformFrame(buf)
	if err != nil {
		t.Fatal(err)
	}
	if got != buf {
		defer got.Close()
		t.Fatalf("rotated a frame already in logical orientation to %dx%d", got.Width, got.Height)
	}
}
