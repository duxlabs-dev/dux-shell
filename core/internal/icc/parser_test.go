package icc

import (
	"encoding/binary"
	"math"
	"slices"
	"strings"
	"testing"
)

func TestSampleCurve(t *testing.T) {
	t.Run("Identity", func(t *testing.T) {
		c := Curve{Type: CurveIdentity}
		for _, tt := range []float64{0, 0.25, 0.5, 0.75, 1.0} {
			got := SampleCurve(c, tt)
			if got != tt {
				t.Errorf("SampleCurve(identity, %f) = %f, want %f", tt, got, tt)
			}
		}
	})

	t.Run("Parametric", func(t *testing.T) {
		c := Curve{Type: CurveParametric, Gamma: 2.2}
		if got := SampleCurve(c, 0.5); math.Abs(got-0.7297) > 0.001 {
			t.Errorf("SampleCurve(gamma2.2, 0.5) = %f, want ~0.7297", got)
		}

		// Boundary conditions
		if v := SampleCurve(c, 0); v != 0 {
			t.Errorf("SampleCurve(gamma2.2, 0) = %f, want 0", v)
		}
		if v := SampleCurve(c, 1); v != 1 {
			t.Errorf("SampleCurve(gamma2.2, 1) = %f, want 1", v)
		}
	})

	t.Run("Table", func(t *testing.T) {
		// Identity table: 2 entries [0, 65535]
		c := Curve{
			Type:    CurveTable,
			Entries: []uint16{0, 65535},
		}
		if v := SampleCurve(c, 0.5); math.Abs(v-0.5) > 0.001 {
			t.Errorf("SampleCurve(identityTable, 0.5) = %f, want ~0.5", v)
		}

		// 4-entry table: [0, 21845, 43690, 65535] (approx 1/3, 2/3, 3/3)
		c2 := Curve{
			Type:    CurveTable,
			Entries: []uint16{0, 21845, 43690, 65535},
		}
		if v := SampleCurve(c2, 0); v != 0 {
			t.Errorf("SampleCurve(4entry, 0) = %f, want 0", v)
		}
		if v := SampleCurve(c2, 1.0); math.Abs(v-1.0) > 0.001 {
			t.Errorf("SampleCurve(4entry, 1.0) = %f, want ~1.0", v)
		}
	})

	t.Run("ClampInput", func(t *testing.T) {
		c := Curve{Type: CurveIdentity}
		// Negative t should be clamped to 0
		if v := SampleCurve(c, -0.5); v != 0 {
			t.Errorf("SampleCurve(identity, -0.5) = %f, want 0", v)
		}
		// t > 1 should be clamped to 1
		if v := SampleCurve(c, 1.5); v != 1 {
			t.Errorf("SampleCurve(identity, 1.5) = %f, want 1", v)
		}
	})
}

func TestParseBytes(t *testing.T) {
	t.Run("TooShort", func(t *testing.T) {
		_, err := ParseBytes([]byte{0, 1, 2})
		if err == nil {
			t.Error("expected error for short data")
		}
	})
}

// --- synthetic profile tests (self-contained; also cover CI) ---

func putS15Fixed16(b []byte, off int, v float64) {
	binary.BigEndian.PutUint32(b[off:], uint32(int32(math.Round(v*65536))))
}

func putU8Fixed8(b []byte, off int, v float64) {
	binary.BigEndian.PutUint16(b[off:], uint16(math.Round(v*256)))
}

// buildSyntheticProfile builds a minimal but valid ICC v2 monitor profile with
// desc, rXYZ/gXYZ/bXYZ, rTRC/gTRC/bTRC (single gamma per channel), wtpt and a
// table vcgt tag, so parsing and ramp generation can be exercised without a
// vendor profile on disk.
func buildSyntheticProfile(desc string, gamma float64) []byte {
	xyzTag := func(x, y, z float64) []byte {
		d := make([]byte, 20)
		copy(d[0:], "XYZ ")
		putS15Fixed16(d, 8, x)
		putS15Fixed16(d, 12, y)
		putS15Fixed16(d, 16, z)
		return d
	}
	curvTag := func(g float64) []byte {
		d := make([]byte, 16)
		copy(d[0:], "curv")
		binary.BigEndian.PutUint32(d[8:], 1) // count=1 -> single gamma value
		putU8Fixed8(d, 12, g)
		return d
	}
	descTag := make([]byte, 12+len(desc)+1)
	copy(descTag[0:], "desc")
	binary.BigEndian.PutUint32(descTag[8:], uint32(len(desc)+1)) // length includes NUL
	copy(descTag[12:], desc)

	const vcgtEntries = 4
	vcgtTag := make([]byte, 18+3*vcgtEntries*2)
	copy(vcgtTag[0:], "vcgt")
	binary.BigEndian.PutUint16(vcgtTag[12:], 3)           // channels
	binary.BigEndian.PutUint16(vcgtTag[14:], vcgtEntries) // entries per channel
	binary.BigEndian.PutUint16(vcgtTag[16:], 2)           // entry size in bytes
	for ch := 0; ch < 3; ch++ {
		for i := 0; i < vcgtEntries; i++ {
			v := uint16(math.Round(65535.0 * float64(i) / float64(vcgtEntries-1)))
			binary.BigEndian.PutUint16(vcgtTag[18+(ch*vcgtEntries+i)*2:], v)
		}
	}

	type tag struct {
		sig  string
		data []byte
	}
	tags := []tag{
		{"desc", descTag},
		{"rXYZ", xyzTag(0.4360, 0.2225, 0.0139)},
		{"gXYZ", xyzTag(0.3851, 0.7169, 0.0971)},
		{"bXYZ", xyzTag(0.1431, 0.0606, 0.7141)},
		{"rTRC", curvTag(gamma)},
		{"gTRC", curvTag(gamma)},
		{"bTRC", curvTag(gamma)},
		{"wtpt", xyzTag(0.9642, 1.0, 0.8249)},
		{"vcgt", vcgtTag},
	}

	const headerSize = 128
	tableSize := 4 + 12*len(tags)
	total := headerSize + tableSize
	for _, tg := range tags {
		total += len(tg.data)
	}

	buf := make([]byte, total)

	binary.BigEndian.PutUint32(buf[0:], uint32(total))
	binary.BigEndian.PutUint32(buf[8:], 0x02100000) // version 2.1.0
	copy(buf[12:], "mntr")
	copy(buf[16:], "RGB ")
	copy(buf[20:], "XYZ ")
	binary.BigEndian.PutUint16(buf[24:], 2026)
	binary.BigEndian.PutUint16(buf[26:], 9)
	binary.BigEndian.PutUint16(buf[28:], 10)
	copy(buf[36:], "acsp")
	putS15Fixed16(buf, 68, 0.9642) // D50 illuminant
	putS15Fixed16(buf, 72, 1.0)
	putS15Fixed16(buf, 76, 0.8249)

	binary.BigEndian.PutUint32(buf[128:], uint32(len(tags)))
	off := headerSize + tableSize
	for i, tg := range tags {
		base := 132 + i*12
		copy(buf[base:], tg.sig)
		binary.BigEndian.PutUint32(buf[base+4:], uint32(off))
		binary.BigEndian.PutUint32(buf[base+8:], uint32(len(tg.data)))
		copy(buf[off:], tg.data)
		off += len(tg.data)
	}
	return buf
}

func TestParseBytesSynthetic(t *testing.T) {
	const desc = "Synthetic Test Display"
	data := buildSyntheticProfile(desc, 2.2)

	p, err := ParseBytes(data)
	if err != nil {
		t.Fatalf("ParseBytes failed: %v", err)
	}

	if p.Size != uint32(len(data)) {
		t.Errorf("Size = %d, want %d", p.Size, len(data))
	}
	if p.Version != "2.1.0" {
		t.Errorf("Version = %q, want %q", p.Version, "2.1.0")
	}
	if p.Class != "mntr" {
		t.Errorf("Class = %q, want %q", p.Class, "mntr")
	}
	if p.ColorSpace != "RGB" {
		t.Errorf("ColorSpace = %q, want %q", p.ColorSpace, "RGB")
	}
	if p.Description != desc {
		t.Errorf("Description = %q, want %q", p.Description, desc)
	}
	if !p.HasMatrix {
		t.Error("HasMatrix = false, want true")
	}
	if !p.HasTRC {
		t.Error("HasTRC = false, want true")
	}
	if !p.HasVCGT {
		t.Error("HasVCGT = false, want true")
	}
	if got := p.TRC[0].Gamma; math.Abs(got-2.2) > 0.01 {
		t.Errorf("TRC[0].Gamma = %f, want ~2.2", got)
	}
	if got := p.WhitePoint[0]; math.Abs(got-0.9642) > 0.001 {
		t.Errorf("WhitePoint X = %f, want ~0.9642", got)
	}
}

func TestGenerateGammaRampSynthetic(t *testing.T) {
	p, err := ParseBytes(buildSyntheticProfile("Synthetic Test Display", 2.2))
	if err != nil {
		t.Fatalf("ParseBytes failed: %v", err)
	}

	const size = 256
	ramp, err := GenerateGammaRamp(size, p)
	if err != nil {
		t.Fatalf("GenerateGammaRamp failed: %v", err)
	}
	if len(ramp.Red) != size || len(ramp.Green) != size || len(ramp.Blue) != size {
		t.Fatalf("ramp lengths = %d/%d/%d, want %d", len(ramp.Red), len(ramp.Green), len(ramp.Blue), size)
	}
	if ramp.Red[size-1] <= ramp.Red[0] {
		t.Errorf("ramp not increasing: first=%d last=%d", ramp.Red[0], ramp.Red[size-1])
	}
}

// A profile without a vcgt table has no video card gamma ramp: the TRC tags
// describe the display's own transfer function, so writing them into the GPU
// LUT washes the output out instead of calibrating it.
func TestGenerateGammaRampRequiresVCGT(t *testing.T) {
	trcOnly := &Profile{
		HasTRC:  true,
		HasVCGT: false,
		TRC: [3]Curve{
			{Type: CurveParametric, Gamma: 2.2},
			{Type: CurveParametric, Gamma: 2.2},
			{Type: CurveParametric, Gamma: 2.2},
		},
	}
	if _, err := GenerateGammaRamp(256, trcOnly); err == nil {
		t.Fatal("expected an error for a profile without a vcgt table")
	}

	// A vcgt tag with no channel data is unusable in the same way.
	emptyVCGT := &Profile{HasVCGT: true}
	if _, err := GenerateGammaRamp(256, emptyVCGT); err == nil {
		t.Fatal("expected an error for a profile without a vcgt table")
	}

	// The ramp size has to be at least 2: the values are spread over size-1.
	if _, err := GenerateGammaRamp(1, &Profile{HasVCGT: true, VCGT: &VCGT{Channels: 3, Entries: 4}}); err == nil {
		t.Fatal("expected an error for a ramp size below 2")
	}
}

// TestParseDescriptionMalformed feeds desc/mluc tags whose offsets or lengths
// point outside the buffer. These must return an error or a clamped string
// instead of a slice-bounds panic: `dms icc list` parses every file in the
// profile directory and the daemon parses user-picked files in-process, so a
// panic here takes the whole daemon down.
func TestParseDescriptionMalformed(t *testing.T) {
	descSig := [4]byte{'d', 'e', 's', 'c'}
	mlucSig := [4]byte{'m', 'l', 'u', 'c'}

	t.Run("desc length wraps past end", func(t *testing.T) {
		data := make([]byte, 32)
		copy(data[0:], "desc")
		// 12 + 0xFFFFFFF8 wraps to 4 in uint32 arithmetic.
		binary.BigEndian.PutUint32(data[8:], 0xFFFFFFF8)

		if _, err := parseDescription(data, tagEntry{sig: descSig, offset: 0, size: 32}); err != nil {
			t.Fatalf("expected clamped string, got error %v", err)
		}
	})

	t.Run("desc length past end", func(t *testing.T) {
		data := make([]byte, 24)
		copy(data[0:], "desc")
		binary.BigEndian.PutUint32(data[8:], 4096)

		desc, err := parseDescription(data, tagEntry{sig: descSig, offset: 0, size: 24})
		if err != nil {
			t.Fatalf("expected clamped string, got error %v", err)
		}
		if desc != "" {
			t.Errorf("expected empty description, got %q", desc)
		}
	})

	t.Run("mluc record header past end", func(t *testing.T) {
		data := make([]byte, 16)
		copy(data[0:], "mluc")
		binary.BigEndian.PutUint32(data[8:], 1)   // numRecords
		binary.BigEndian.PutUint32(data[12:], 12) // recordSize

		if _, err := parseDescription(data, tagEntry{sig: mlucSig, offset: 0, size: 16}); err == nil {
			t.Fatal("expected error for truncated mluc record header")
		}
	})

	t.Run("mluc string offset past end", func(t *testing.T) {
		data := make([]byte, 32)
		copy(data[0:], "mluc")
		binary.BigEndian.PutUint32(data[8:], 1)   // numRecords
		binary.BigEndian.PutUint32(data[12:], 12) // recordSize
		binary.BigEndian.PutUint32(data[20:], 4)  // string length
		binary.BigEndian.PutUint32(data[24:], 0xFFFFFF00)

		if _, err := parseDescription(data, tagEntry{sig: mlucSig, offset: 0, size: 32}); err == nil {
			t.Fatal("expected error for out-of-bounds mluc string")
		}
	})
}

// TestParseBytesTagTableBounds feeds tag counts that do not fit in the file.
// The count sizes a slice before any entry is read, so a wrapping count has to
// be rejected up front: with tagCount*12 wrapping in uint32, a 140-byte profile
// passed the old bounds check, allocated a ~4 GB tag slice and then panicked
// with slice bounds out of range. ParseFile runs on the wayland actor goroutine,
// which has no recover(), so that panic took the dms daemon down at startup.
func TestParseBytesTagTableBounds(t *testing.T) {
	t.Run("count wraps in uint32 arithmetic", func(t *testing.T) {
		data := buildSyntheticProfile("Wrapping tag count", 2.2)
		binary.BigEndian.PutUint32(data[128:132], 0x15555556) // *12 == 8

		_, err := ParseBytes(data)
		if err == nil {
			t.Fatal("expected error for a tag count that does not fit in the profile")
		}
		if !strings.Contains(err.Error(), "tag entries") {
			t.Fatalf("ParseBytes() error = %v, want a tag entry count error", err)
		}
	})

	t.Run("count exceeds remaining bytes", func(t *testing.T) {
		data := buildSyntheticProfile("Too many tags", 2.2)
		binary.BigEndian.PutUint32(data[128:132], uint32((len(data)-132)/12+1))

		_, err := ParseBytes(data)
		if err == nil {
			t.Fatal("expected error for more tag entries than the profile can hold")
		}
		if !strings.Contains(err.Error(), "tag entries") {
			t.Fatalf("ParseBytes() error = %v, want a tag entry count error", err)
		}
	})

	t.Run("count filling the file exactly still parses", func(t *testing.T) {
		data := buildSyntheticProfile("Exact fit", 2.2)
		binary.BigEndian.PutUint32(data[128:132], uint32((len(data)-132)/12))

		if _, err := ParseBytes(data); err != nil {
			t.Fatalf("ParseBytes() = %v, want the boundary count accepted", err)
		}
	})
}

func vcgtTableTag(channels int, entries []uint16) []byte {
	tag := make([]byte, 18+channels*len(entries)*2)
	copy(tag[0:], "vcgt")
	binary.BigEndian.PutUint16(tag[12:], uint16(channels))
	binary.BigEndian.PutUint16(tag[14:], uint16(len(entries)))
	binary.BigEndian.PutUint16(tag[16:], 2)
	for ch := 0; ch < channels; ch++ {
		for i, v := range entries {
			binary.BigEndian.PutUint16(tag[18+(ch*len(entries)+i)*2:], v)
		}
	}
	return tag
}

func TestParseVCGTChannelCount(t *testing.T) {
	entries := []uint16{0, 21845, 43690, 65535}

	t.Run("one channel is replicated to all three", func(t *testing.T) {
		tag := vcgtTableTag(1, entries)
		vcgt, err := parseVCGT(tag, tagEntry{offset: 0, size: uint32(len(tag))})
		if err != nil {
			t.Fatalf("parseVCGT: %v", err)
		}
		if !slices.Equal(vcgt.Red, entries) {
			t.Fatalf("red = %v, want %v", vcgt.Red, entries)
		}
		if !slices.Equal(vcgt.Green, entries) || !slices.Equal(vcgt.Blue, entries) {
			t.Fatalf("green/blue must copy the single curve: green=%v blue=%v", vcgt.Green, vcgt.Blue)
		}
	})

	t.Run("three channels are read independently", func(t *testing.T) {
		tag := vcgtTableTag(3, entries)
		vcgt, err := parseVCGT(tag, tagEntry{offset: 0, size: uint32(len(tag))})
		if err != nil {
			t.Fatalf("parseVCGT: %v", err)
		}
		if !slices.Equal(vcgt.Blue, entries) {
			t.Fatalf("blue = %v, want %v", vcgt.Blue, entries)
		}
	})

	t.Run("two channels are rejected", func(t *testing.T) {
		tag := vcgtTableTag(2, entries)
		if _, err := parseVCGT(tag, tagEntry{offset: 0, size: uint32(len(tag))}); err == nil {
			t.Fatal("expected an error for a 2-channel vcgt")
		}
	})
}
