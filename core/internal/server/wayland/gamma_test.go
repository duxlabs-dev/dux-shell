package wayland

import (
	"math"
	"slices"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/icc"
)

func TestGenerateGammaRamp(t *testing.T) {
	tests := []struct {
		name  string
		size  uint32
		temp  int
		gamma float64
	}{
		{"large_warm", 256, 6500, 1.0},
		{"custom_gamma", 64, 5500, 1.2},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ramp := GenerateGammaRamp(tt.size, tt.temp, tt.gamma, 1.0)

			if len(ramp.Red) != int(tt.size) {
				t.Errorf("expected %d red values, got %d", tt.size, len(ramp.Red))
			}
			if len(ramp.Green) != int(tt.size) {
				t.Errorf("expected %d green values, got %d", tt.size, len(ramp.Green))
			}
			if len(ramp.Blue) != int(tt.size) {
				t.Errorf("expected %d blue values, got %d", tt.size, len(ramp.Blue))
			}

			if ramp.Red[0] != 0 || ramp.Green[0] != 0 || ramp.Blue[0] != 0 {
				t.Errorf("first values should be 0, got R:%d G:%d B:%d",
					ramp.Red[0], ramp.Green[0], ramp.Blue[0])
			}

			lastIdx := tt.size - 1
			if ramp.Red[lastIdx] == 0 || ramp.Green[lastIdx] == 0 || ramp.Blue[lastIdx] == 0 {
				t.Errorf("last values should be non-zero, got R:%d G:%d B:%d",
					ramp.Red[lastIdx], ramp.Green[lastIdx], ramp.Blue[lastIdx])
			}

			for i := uint32(1); i < tt.size; i++ {
				if ramp.Red[i] < ramp.Red[i-1] {
					t.Errorf("red ramp not monotonic at index %d", i)
				}
			}
		})
	}
}

func TestWhitepointProgression(t *testing.T) {
	temps := []int{3000, 4000, 5000, 6000, 6500}

	var prevBlue float64
	for i, temp := range temps {
		wp := calcWhitepoint(temp)
		if i > 0 && wp.b < prevBlue {
			t.Errorf("blue should increase with temperature, %d->%d: %f->%f",
				temps[i-1], temp, prevBlue, wp.b)
		}
		prevBlue = wp.b
	}
}

func TestGenerateGammaRamp_NeutralContrastMatchesLegacy(t *testing.T) {
	legacy := GenerateGammaRamp(256, 4000, 1.2, 1.0)
	for i := range legacy.Red {
		want := uint16(clamp01(math.Pow(float64(i)/255.0*calcWhitepoint(4000).r, 1.0/1.2)) * 65535.0)
		if legacy.Red[i] != want {
			t.Fatalf("index %d: got %d want %d", i, legacy.Red[i], want)
		}
	}
}

func TestGenerateGammaRamp_ContrastPivotsAtMidGray(t *testing.T) {
	const size = 257
	mid := size / 2

	for _, contrast := range []float64{0.5, 1.0, 2.0} {
		ramp := GenerateGammaRamp(size, 6500, 1.0, contrast)
		if ramp.Red[mid] != 32767 {
			t.Errorf("contrast %.1f: mid-gray moved to %d", contrast, ramp.Red[mid])
		}
		for i := 1; i < size; i++ {
			if ramp.Red[i] < ramp.Red[i-1] {
				t.Fatalf("contrast %.1f: not monotonic at %d", contrast, i)
			}
		}
	}

	high := GenerateGammaRamp(size, 6500, 1.0, 2.0)
	if high.Red[size/4] != 0 || high.Red[size*3/4] != 65535 {
		t.Errorf("contrast 2.0 should clip quarter points, got %d and %d", high.Red[size/4], high.Red[size*3/4])
	}

	low := GenerateGammaRamp(size, 6500, 1.0, 0.5)
	if low.Red[0] != 16383 || low.Red[size-1] != 49151 {
		t.Errorf("contrast 0.5 should compress endpoints to quarter points, got %d and %d", low.Red[0], low.Red[size-1])
	}
}

// Profile ramps are composed with a target temperature relative to the white
// point display profiles are produced at (D65): no target keeps the profile as
// measured, a target shifts it.
func TestProfileRampWithTemp(t *testing.T) {
	const size = uint32(256)
	mid := int(size) / 2

	// Only vcgt carries a video card gamma table, so the fixture is a profile
	// whose table is the identity ramp: that keeps the expectations below about
	// the temperature composition readable.
	identityTable := func(entries int) []uint16 {
		out := make([]uint16, entries)
		for i := range out {
			out[i] = uint16(float64(i) / float64(entries-1) * 65535.0)
		}
		return out
	}
	profile := &icc.Profile{
		HasVCGT: true,
		VCGT: &icc.VCGT{
			Channels: 3,
			Entries:  256,
			Red:      identityTable(256),
			Green:    identityTable(256),
			Blue:     identityTable(256),
		},
	}
	identity := GenerateIdentityRamp(size)

	t.Run("no target keeps the profile as measured", func(t *testing.T) {
		ramp, err := ProfileRampWithTemp(size, profile, neutralTemp, noTempTarget, 1, 1)
		if err != nil {
			t.Fatalf("ProfileRampWithTemp: %v", err)
		}
		if !slices.Equal(identity.Red, ramp.Red) || !slices.Equal(identity.Blue, ramp.Blue) {
			t.Fatal("profile ramp should be unchanged without a temperature target")
		}
	})

	t.Run("target equal to the reference leaves the profile alone", func(t *testing.T) {
		ramp, err := ProfileRampWithTemp(size, profile, neutralTemp, neutralTemp, 1, 1)
		if err != nil {
			t.Fatalf("ProfileRampWithTemp: %v", err)
		}
		if !slices.Equal(identity.Red, ramp.Red) {
			t.Fatal("profile ramp should be unchanged at its reference white point")
		}
	})

	t.Run("cooler target cools the output", func(t *testing.T) {
		ramp, err := ProfileRampWithTemp(size, profile, neutralTemp, 7000, 1, 1)
		if err != nil {
			t.Fatalf("ProfileRampWithTemp: %v", err)
		}
		if ramp.Red[mid] >= identity.Red[mid] {
			t.Errorf("red should be pulled down: got %d, want < %d", ramp.Red[mid], identity.Red[mid])
		}
		if ramp.Green[mid] >= identity.Green[mid] {
			t.Errorf("green should be pulled down: got %d, want < %d", ramp.Green[mid], identity.Green[mid])
		}
		if ramp.Blue[mid] != identity.Blue[mid] {
			t.Errorf("blue is the reference channel and should be unchanged: got %d, want %d", ramp.Blue[mid], identity.Blue[mid])
		}
	})

	t.Run("warmer target warms the output", func(t *testing.T) {
		ramp, err := ProfileRampWithTemp(size, profile, neutralTemp, 5000, 1, 1)
		if err != nil {
			t.Fatalf("ProfileRampWithTemp: %v", err)
		}
		if ramp.Red[mid] != identity.Red[mid] {
			t.Errorf("red is the reference channel and should be unchanged: got %d, want %d", ramp.Red[mid], identity.Red[mid])
		}
		if ramp.Green[mid] >= identity.Green[mid] {
			t.Errorf("green should be pulled down: got %d, want < %d", ramp.Green[mid], identity.Green[mid])
		}
		if ramp.Blue[mid] >= identity.Blue[mid] {
			t.Errorf("blue should be pulled down: got %d, want < %d", ramp.Blue[mid], identity.Blue[mid])
		}
	})
}

func identityVCGTProfile(entries int) *icc.Profile {
	table := func() []uint16 {
		out := make([]uint16, entries)
		for i := range out {
			out[i] = uint16(float64(i) / float64(entries-1) * 65535.0)
		}
		return out
	}
	return &icc.Profile{
		HasVCGT: true,
		VCGT:    &icc.VCGT{Channels: 3, Entries: entries, Red: table(), Green: table(), Blue: table()},
	}
}

func TestProfileRampWithTempAppliesGammaAndContrast(t *testing.T) {
	const size = uint32(256)
	const tolerance = 2
	profile := identityVCGTProfile(256)

	closeTo := func(t *testing.T, name string, got, want []uint16) {
		t.Helper()
		for i := range want {
			diff := int(got[i]) - int(want[i])
			if diff < -tolerance || diff > tolerance {
				t.Fatalf("%s[%d] = %d, want %d (±%d)", name, i, got[i], want[i], tolerance)
			}
		}
	}

	cases := []struct {
		name     string
		target   int
		gamma    float64
		contrast float64
	}{
		{"no target, gamma only", noTempTarget, 1.8, 1.0},
		{"reference target, both", neutralTemp, 0.8, 0.7},
		{"warm target, both", 4000, 1.5, 1.3},
		{"cool target, both", 8000, 0.9, 0.6},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ramp, err := ProfileRampWithTemp(size, profile, neutralTemp, tc.target, tc.gamma, tc.contrast)
			if err != nil {
				t.Fatalf("ProfileRampWithTemp: %v", err)
			}
			plainTemp := tc.target
			if plainTemp <= 0 {
				plainTemp = neutralTemp
			}
			want := GenerateGammaRamp(size, plainTemp, tc.gamma, tc.contrast)
			closeTo(t, "red", ramp.Red, want.Red)
			closeTo(t, "green", ramp.Green, want.Green)
			closeTo(t, "blue", ramp.Blue, want.Blue)
		})
	}
}

func TestBrightnessScale_NeverReachesBlack(t *testing.T) {
	if got := brightnessScale(0); got != outputBrightnessFloor {
		t.Errorf("brightnessScale(0) = %v, want the floor %v", got, outputBrightnessFloor)
	}
	if got := brightnessScale(100); got != 1 {
		t.Errorf("brightnessScale(100) = %v, want 1", got)
	}
}
