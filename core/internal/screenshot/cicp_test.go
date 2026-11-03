package screenshot

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/png"
	"testing"
)

func TestEncodePNGTagged(t *testing.T) {
	img := image.NewNRGBA64(image.Rect(0, 0, 2, 2))
	cicp := &CICP{Primaries: 9, TF: 16} // BT.2020 PQ

	var buf bytes.Buffer
	if err := EncodePNGTagged(&buf, img, cicp); err != nil {
		t.Fatal(err)
	}

	// cICP chunk sits right after signature (8) + IHDR (25)
	data := buf.Bytes()
	const off = 33
	if got := string(data[off+4 : off+8]); got != "cICP" {
		t.Fatalf("chunk type = %q, want cICP", got)
	}
	if length := binary.BigEndian.Uint32(data[off:]); length != 4 {
		t.Errorf("chunk length = %d, want 4", length)
	}
	if payload := data[off+8 : off+12]; !bytes.Equal(payload, []byte{9, 16, 0, 1}) {
		t.Errorf("payload = %v, want [9 16 0 1]", payload)
	}

	// still a decodable PNG
	if _, err := png.Decode(bytes.NewReader(data)); err != nil {
		t.Fatalf("decode tagged PNG: %v", err)
	}
}

func TestEncodePNGTaggedNil(t *testing.T) {
	var tagged, plain bytes.Buffer
	img := image.NewRGBA(image.Rect(0, 0, 1, 1))

	if err := EncodePNGTagged(&tagged, img, nil); err != nil {
		t.Fatal(err)
	}
	if err := EncodePNG(&plain, img); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(tagged.Bytes(), plain.Bytes()) {
		t.Error("nil CICP must not alter PNG output")
	}
}

func TestCICPFromNamed(t *testing.T) {
	cases := []struct {
		name          string
		primaries, tf uint32
		want          *CICP
	}{
		{"bt2020-pq", 6, 11, &CICP{Primaries: 9, TF: 16}},
		{"bt2020-hlg", 6, 13, &CICP{Primaries: 9, TF: 18}},
		{"display_p3-srgb", 9, 9, &CICP{Primaries: 12, TF: 13}},
		{"srgb-srgb", 1, 9, nil},
		{"unmapped-adobe", 10, 9, nil},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := cicpFromNamed(tc.primaries, tc.tf)
			switch {
			case got == nil && tc.want == nil:
			case got == nil || tc.want == nil || *got != *tc.want:
				t.Errorf("cicpFromNamed(%d, %d) = %v, want %v", tc.primaries, tc.tf, got, tc.want)
			}
		})
	}
}
