package brightness

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/pilebones/go-udev/netlink"
)

func setupTestManager(t *testing.T) (*Manager, string) {
	tmpDir := t.TempDir()

	backlightDir := filepath.Join(tmpDir, "backlight", "intel_backlight")
	if err := os.MkdirAll(backlightDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(backlightDir, "max_brightness"), []byte("1000\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(backlightDir, "brightness"), []byte("500\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	sysfs := &SysfsBackend{
		basePath: tmpDir,
		classes:  []string{"backlight"},
	}
	if err := sysfs.scanDevices(); err != nil {
		t.Fatal(err)
	}

	m := &Manager{
		sysfsBackend: sysfs,
		nativeReady:  true,
		stopChan:     make(chan struct{}),
	}

	m.state = State{
		Devices: []Device{
			{
				Class:          ClassBacklight,
				ID:             "backlight:intel_backlight",
				Name:           "intel_backlight",
				Current:        500,
				Max:            1000,
				CurrentPercent: 50,
				Backend:        "sysfs",
			},
		},
	}

	return m, tmpDir
}

func TestHandleUdevBrightnessChange_UpdatesState(t *testing.T) {
	m, _ := setupTestManager(t)

	m.handleUdevBrightnessChange("backlight:intel_backlight", 750)

	state := m.GetState()
	if len(state.Devices) != 1 {
		t.Fatalf("expected 1 device, got %d", len(state.Devices))
	}

	dev := state.Devices[0]
	if dev.Current != 750 {
		t.Errorf("expected Current=750, got %d", dev.Current)
	}
	if dev.CurrentPercent != 75 {
		t.Errorf("expected CurrentPercent=75, got %d", dev.CurrentPercent)
	}
}

func TestHandleUdevBrightnessChange_NoChangeWhenSameValue(t *testing.T) {
	m, _ := setupTestManager(t)

	updateCh := m.SubscribeUpdates("test")
	defer m.UnsubscribeUpdates("test")

	m.handleUdevBrightnessChange("backlight:intel_backlight", 500)

	select {
	case <-updateCh:
		t.Error("should not broadcast when brightness unchanged")
	default:
	}
}

func TestHandleUdevBrightnessChange_BroadcastsOnChange(t *testing.T) {
	m, _ := setupTestManager(t)

	updateCh := m.SubscribeUpdates("test")
	defer m.UnsubscribeUpdates("test")

	m.handleUdevBrightnessChange("backlight:intel_backlight", 750)

	select {
	case update := <-updateCh:
		if update.Device.Current != 750 {
			t.Errorf("broadcast had wrong Current: got %d, want 750", update.Device.Current)
		}
	default:
		t.Error("expected broadcast on brightness change")
	}
}

func TestHandleUdevBrightnessChange_UnknownDevice(t *testing.T) {
	m, _ := setupTestManager(t)

	m.handleUdevBrightnessChange("backlight:unknown_device", 500)

	state := m.GetState()
	if len(state.Devices) != 1 {
		t.Errorf("state should be unchanged, got %d devices", len(state.Devices))
	}
}

func TestHandleUdevBrightnessChange_DeviceNotInState(t *testing.T) {
	m, _ := setupTestManager(t)

	m.sysfsBackend.deviceCache.Store("backlight:other_device", &sysfsDevice{
		class:         ClassBacklight,
		id:            "backlight:other_device",
		name:          "other_device",
		maxBrightness: 100,
		minValue:      1,
	})

	m.handleUdevBrightnessChange("backlight:other_device", 50)

	state := m.GetState()
	for _, d := range state.Devices {
		if d.ID == "backlight:other_device" {
			t.Error("device should not be added to state via udev change event")
		}
	}
}

func TestHandleEvent_ChangeAction(t *testing.T) {
	m, tmpDir := setupTestManager(t)
	um := &UdevMonitor{stop: make(chan struct{})}

	brightnessPath := filepath.Join(tmpDir, "backlight", "intel_backlight", "brightness")
	if err := os.WriteFile(brightnessPath, []byte("800\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	event := netlink.UEvent{
		Action: netlink.CHANGE,
		Env: map[string]string{
			"SUBSYSTEM": "backlight",
			"DEVPATH":   "/devices/pci0000:00/0000:00:02.0/drm/card0/card0-eDP-1/intel_backlight",
		},
	}

	um.handleEvent(m, event)

	state := m.GetState()
	if state.Devices[0].Current != 800 {
		t.Errorf("expected Current=800 after change event, got %d", state.Devices[0].Current)
	}
}

func TestHandleEvent_MissingEnvVars(t *testing.T) {
	m, _ := setupTestManager(t)
	um := &UdevMonitor{stop: make(chan struct{})}

	event := netlink.UEvent{
		Action: netlink.CHANGE,
		Env:    map[string]string{},
	}

	um.handleEvent(m, event)

	state := m.GetState()
	if state.Devices[0].Current != 500 {
		t.Error("state should be unchanged with missing env vars")
	}
}

func TestHandleChange_BrightnessFileNotFound(t *testing.T) {
	m, _ := setupTestManager(t)
	um := &UdevMonitor{stop: make(chan struct{})}

	um.handleChange(m, "backlight", "nonexistent_device")

	state := m.GetState()
	if state.Devices[0].Current != 500 {
		t.Error("state should be unchanged when brightness file not found")
	}
}

func TestHandleChange_InvalidBrightnessValue(t *testing.T) {
	m, tmpDir := setupTestManager(t)
	um := &UdevMonitor{stop: make(chan struct{})}

	brightnessPath := filepath.Join(tmpDir, "backlight", "intel_backlight", "brightness")
	if err := os.WriteFile(brightnessPath, []byte("not_a_number\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	um.handleChange(m, "backlight", "intel_backlight")

	state := m.GetState()
	if state.Devices[0].Current != 500 {
		t.Error("state should be unchanged with invalid brightness value")
	}
}
