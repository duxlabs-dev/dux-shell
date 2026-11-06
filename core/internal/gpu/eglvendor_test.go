package gpu

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
)

func writeICD(t *testing.T, dir, name, library string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(`{"file_format_version":"1.0.0","ICD":{"library_path":"`+library+`"}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestFindEGLVendorICDs(t *testing.T) {
	etc := t.TempDir()
	usr := t.TempDir()
	writeICD(t, usr, "10_nvidia.json", "libEGL_nvidia.so.0")
	mesaPath := writeICD(t, usr, "50_mesa.json", "libEGL_mesa.so.0")
	nvidiaPath := writeICD(t, etc, "10_nvidia.json", "/usr/lib/libEGL_nvidia.so.0")
	if err := os.WriteFile(filepath.Join(etc, "broken.json"), []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}

	mesa, nvidia := findEGLVendorICDs([]string{etc, usr})
	if mesa != mesaPath {
		t.Errorf("mesa = %q, want %q", mesa, mesaPath)
	}
	if nvidia != nvidiaPath {
		t.Errorf("nvidia = %q, want %q", nvidia, nvidiaPath)
	}

	mesa, nvidia = findEGLVendorICDs([]string{filepath.Join(etc, "missing")})
	if mesa != "" || nvidia != "" {
		t.Errorf("missing dir: got %q %q, want empty", mesa, nvidia)
	}
}

func TestDrmDeviceDriver(t *testing.T) {
	root := t.TempDir()
	charDir := filepath.Join(root, "char")
	deviceDir := filepath.Join(charDir, "226:128", "device")
	if err := os.MkdirAll(deviceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("../../../../bus/pci/drivers/amdgpu", filepath.Join(deviceDir, "driver")); err != nil {
		t.Fatal(err)
	}

	driver, err := drmDeviceDriver(charDir, 226<<8|128)
	if err != nil {
		t.Fatal(err)
	}
	if driver != "amdgpu" {
		t.Errorf("driver = %q, want amdgpu", driver)
	}
	if _, err := drmDeviceDriver(charDir, 226<<8|129); err == nil {
		t.Error("unknown device: want error")
	}
}

func TestMainDeviceFromEvent(t *testing.T) {
	raw := make([]byte, 8)
	binary.NativeEndian.PutUint64(raw, 226<<8|128)
	dev, err := mainDeviceFromEvent(raw)
	if err != nil {
		t.Fatal(err)
	}
	if dev != 226<<8|128 {
		t.Errorf("dev = %d", dev)
	}
	if _, err := mainDeviceFromEvent(raw[:4]); err == nil {
		t.Error("short array: want error")
	}
}

func TestShellEnvFor(t *testing.T) {
	unset := func(string) (string, bool) { return "", false }
	mesa := "/usr/share/glvnd/egl_vendor.d/50_mesa.json"
	if got := shellEnvFor("nvidia", mesa, unset); len(got) != 1 || got[0] != "QT_FFMPEG_DECODING_HW_DEVICE_TYPES=cuda" {
		t.Errorf("nvidia: got %q, want cuda decoding only", got)
	}
	want := []string{"QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi", "__EGL_VENDOR_LIBRARY_FILENAMES=" + mesa}
	if got := shellEnvFor("amdgpu", mesa, unset); len(got) != 2 || got[0] != want[0] || got[1] != want[1] {
		t.Errorf("amdgpu: got %q, want %q", got, want)
	}
	overridden := func(name string) (string, bool) { return "", name == "QT_FFMPEG_DECODING_HW_DEVICE_TYPES" }
	if got := shellEnvFor("nvidia", mesa, overridden); got != nil {
		t.Errorf("user override: got %q, want nothing", got)
	}
}
