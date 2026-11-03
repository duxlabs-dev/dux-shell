package brightness

import (
	"maps"
	"os"
	"path/filepath"
	"testing"
)

func TestIsIgnorableI2CDeviceName(t *testing.T) {
	tests := []struct {
		name       string
		deviceName string
		driver     string
		want       bool
	}{
		{
			name:       "AMDGPU SMU should be ignored",
			deviceName: "AMDGPU SMU",
			driver:     "amdgpu",
			want:       true,
		},
		{
			name:       "Regular NVIDIA DDC should not be ignored",
			deviceName: "NVIDIA i2c adapter 1",
			driver:     "nvidia",
			want:       false,
		},
		{
			name:       "nouveau nvkm bus should not be ignored",
			deviceName: "nvkm-0000:01:00.0-bus-0000",
			driver:     "nouveau",
			want:       false,
		},
		{
			name:       "nouveau non-nvkm bus should be ignored",
			deviceName: "nouveau-other-bus",
			driver:     "nouveau",
			want:       true,
		},
		{
			name:       "Regular AMD display adapter should not be ignored",
			deviceName: "AMDGPU DM i2c hw bus 0",
			driver:     "amdgpu",
			want:       false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isIgnorableI2CDeviceName(tt.deviceName, tt.driver)
			if got != tt.want {
				t.Errorf("isIgnorableI2CDeviceName(%q, %q) = %v, want %v",
					tt.deviceName, tt.driver, got, tt.want)
			}
		})
	}
}

func TestDrmConnectorsByBusMapsBothDPBuses(t *testing.T) {
	root := t.TempDir()
	for _, dir := range []string{
		"card1-DP-2/i2c-13",
		"card1-DP-2/ddc/i2c-dev/i2c-4",
		"card1-HDMI-A-1/ddc/i2c-dev/i2c-2",
		"card1-DP-9",
		"renderD128",
	} {
		if err := os.MkdirAll(filepath.Join(root, dir), 0o755); err != nil {
			t.Fatal(err)
		}
	}

	got := drmConnectorsByBusIn(root)

	want := map[int]string{13: "card1-DP-2", 4: "card1-DP-2", 2: "card1-HDMI-A-1"}
	if !maps.Equal(got, want) {
		t.Fatalf("drmConnectorsByBusIn() = %v, want %v", got, want)
	}
}
