package brightness

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSysfsBackend_PercentConversions(t *testing.T) {
	tests := []struct {
		name      string
		device    *sysfsDevice
		percent   int
		wantValue int
		tolerance int
	}{
		{
			name:      "backlight 0% should be minValue=1",
			device:    &sysfsDevice{maxBrightness: 100, minValue: 1, class: ClassBacklight},
			percent:   0,
			wantValue: 1,
			tolerance: 0,
		},
		{
			name:      "backlight 50% should be ~50",
			device:    &sysfsDevice{maxBrightness: 100, minValue: 1, class: ClassBacklight},
			percent:   50,
			wantValue: 50,
			tolerance: 1,
		},
		{
			name:      "backlight 100% should be max",
			device:    &sysfsDevice{maxBrightness: 100, minValue: 1, class: ClassBacklight},
			percent:   100,
			wantValue: 100,
			tolerance: 0,
		},
		{
			name:      "led 50% should be ~127",
			device:    &sysfsDevice{maxBrightness: 255, minValue: 0, class: ClassLED},
			percent:   50,
			wantValue: 127,
			tolerance: 2,
		},
	}

	b := &SysfsBackend{}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := b.PercentToValue(tt.percent, tt.device, false)
			diff := got - tt.wantValue
			if diff < 0 {
				diff = -diff
			}
			if diff > tt.tolerance {
				t.Errorf("percentToValue() = %v, want %v (±%d)", got, tt.wantValue, tt.tolerance)
			}

			gotPercent := b.ValueToPercent(got, tt.device, false)
			if tt.percent > 1 && gotPercent == 0 {
				t.Errorf("valueToPercent() returned 0 for non-zero input (percent=%d, got value=%d)", tt.percent, got)
			}
		})
	}
}

func TestSysfsBackend_ValueToPercent(t *testing.T) {
	tests := []struct {
		name        string
		device      *sysfsDevice
		value       int
		wantPercent int
	}{
		{
			name:        "backlight min value",
			device:      &sysfsDevice{maxBrightness: 100, minValue: 1, class: ClassBacklight},
			value:       1,
			wantPercent: 1,
		},
		{
			name:        "backlight max value",
			device:      &sysfsDevice{maxBrightness: 100, minValue: 1, class: ClassBacklight},
			value:       100,
			wantPercent: 100,
		},
		{
			name:        "led zero",
			device:      &sysfsDevice{maxBrightness: 255, minValue: 0, class: ClassLED},
			value:       0,
			wantPercent: 0,
		},
	}

	b := &SysfsBackend{}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := b.ValueToPercent(tt.value, tt.device, false)
			if got != tt.wantPercent {
				t.Errorf("valueToPercent() = %v, want %v", got, tt.wantPercent)
			}
		})
	}
}

func TestSysfsBackend_ScanDevices(t *testing.T) {
	tmpDir := t.TempDir()

	backlightDir := filepath.Join(tmpDir, "backlight", "test_backlight")
	if err := os.MkdirAll(backlightDir, 0o755); err != nil {
		t.Fatal(err)
	}

	if err := os.WriteFile(filepath.Join(backlightDir, "max_brightness"), []byte("100\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(backlightDir, "brightness"), []byte("50\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	ledsDir := filepath.Join(tmpDir, "leds", "test_led")
	if err := os.MkdirAll(ledsDir, 0o755); err != nil {
		t.Fatal(err)
	}

	if err := os.WriteFile(filepath.Join(ledsDir, "max_brightness"), []byte("255\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(ledsDir, "brightness"), []byte("128\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	b := &SysfsBackend{
		basePath: tmpDir,
		classes:  []string{"backlight", "leds"},
	}

	if err := b.scanDevices(); err != nil {
		t.Fatalf("scanDevices() error = %v", err)
	}

	backlightID := "backlight:test_backlight"
	if _, ok := b.deviceCache.Load(backlightID); !ok {
		t.Errorf("backlight device not found")
	}

	ledID := "leds:test_led"
	if _, ok := b.deviceCache.Load(ledID); !ok {
		t.Errorf("LED device not found")
	}
}

func TestSysfsBackend_GetDevicesHidesIndicatorLEDs(t *testing.T) {
	tmpDir := t.TempDir()

	writeLED := func(name, trigger string) {
		t.Helper()
		dir := filepath.Join(tmpDir, "leds", name)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		files := map[string]string{
			"max_brightness": "1\n",
			"brightness":     "0\n",
			"trigger":        trigger,
		}
		for file, content := range files {
			if err := os.WriteFile(filepath.Join(dir, file), []byte(content), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}

	writeLED("phy0-led", "none phy0rx phy0tx [phy0radio] rfkill1\n")
	writeLED("kbd_backlight", "[none] rc-feedback\n")

	b := &SysfsBackend{basePath: tmpDir, classes: []string{"leds"}}
	if err := b.scanDevices(); err != nil {
		t.Fatalf("scanDevices() error = %v", err)
	}

	devices, err := b.GetDevices()
	if err != nil {
		t.Fatalf("GetDevices() error = %v", err)
	}

	ids := make(map[string]bool, len(devices))
	for _, dev := range devices {
		ids[dev.ID] = true
	}

	if ids["leds:phy0-led"] {
		t.Error("trigger-driven indicator LED listed as a brightness device")
	}
	if !ids["leds:kbd_backlight"] {
		t.Error("user-controlled LED missing from brightness devices")
	}
}
