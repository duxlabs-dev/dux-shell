package gpu

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/linux_dmabuf"
	"golang.org/x/sys/unix"
)

var eglVendorDirs = []string{"/etc/glvnd/egl_vendor.d", "/usr/share/glvnd/egl_vendor.d"}

const (
	dmabufFeedbackMinVersion = 4
	// v6 stops sending main_device
	dmabufMainDeviceMaxVersion = 5
	compositorProbeTimeout     = 2 * time.Second
	sysDevCharDir              = "/sys/dev/char"
)

const decodeDeviceTypesVar = "QT_FFMPEG_DECODING_HW_DEVICE_TYPES"

// ShellEnv picks GPU driver env for the shell from the device the compositor renders on.
func ShellEnv() []string {
	mesa, nvidia := findEGLVendorICDs(eglVendorDirs)
	driver := ""
	if nvidia != "" {
		probed, err := compositorRenderDriver()
		if err != nil {
			log.Debugf("gpu: keeping driver defaults: %v", err)
		}
		driver = probed
	}
	return shellEnvFor(driver, mesa, os.LookupEnv)
}

func shellEnvFor(driver, mesaICD string, lookupEnv func(string) (string, bool)) []string {
	env := decodeEnv(driver, lookupEnv)
	if driver == "" || driver == "nvidia" || mesaICD == "" {
		return env
	}
	if envSet(lookupEnv, "__EGL_VENDOR_LIBRARY_FILENAMES") || envSet(lookupEnv, "__EGL_VENDOR_LIBRARY_DIRS") {
		return env
	}
	log.Infof("egl: compositor renders on %s, loading mesa vendor only", driver)
	return append(env, "__EGL_VENDOR_LIBRARY_FILENAMES="+mesaICD)
}

// nvidia-vaapi-driver rejects the composed-layer export Qt's VAAPI path asks for (#4133).
func decodeEnv(driver string, lookupEnv func(string) (string, bool)) []string {
	if envSet(lookupEnv, decodeDeviceTypesVar) {
		return nil
	}
	if driver == "nvidia" {
		log.Infof("gpu: compositor renders on nvidia, decoding video on cuda")
		return []string{decodeDeviceTypesVar + "=cuda"}
	}
	return []string{decodeDeviceTypesVar + "=vaapi"}
}

func envSet(lookupEnv func(string) (string, bool), name string) bool {
	_, set := lookupEnv(name)
	return set
}

type eglVendorICD struct {
	ICD struct {
		LibraryPath string `json:"library_path"`
	} `json:"ICD"`
}

func findEGLVendorICDs(dirs []string) (mesa, nvidia string) {
	for _, dir := range dirs {
		entries, err := filepath.Glob(filepath.Join(dir, "*.json"))
		if err != nil {
			continue
		}
		for _, path := range entries {
			switch eglVendorLibrary(path) {
			case "libEGL_mesa":
				if mesa == "" {
					mesa = path
				}
			case "libEGL_nvidia":
				if nvidia == "" {
					nvidia = path
				}
			}
		}
	}
	return mesa, nvidia
}

func eglVendorLibrary(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	var icd eglVendorICD
	if err := json.Unmarshal(data, &icd); err != nil {
		return ""
	}
	base := filepath.Base(icd.ICD.LibraryPath)
	name, _, _ := strings.Cut(base, ".so")
	return name
}

func compositorRenderDriver() (string, error) {
	dev, err := compositorMainDevice()
	if err != nil {
		return "", err
	}
	return drmDeviceDriver(sysDevCharDir, dev)
}

func drmDeviceDriver(charDir string, dev uint64) (string, error) {
	link := filepath.Join(charDir, fmt.Sprintf("%d:%d", unix.Major(dev), unix.Minor(dev)), "device", "driver")
	target, err := os.Readlink(link)
	if err != nil {
		return "", err
	}
	return filepath.Base(target), nil
}

func compositorMainDevice() (uint64, error) {
	display, err := wlclient.Connect("")
	if err != nil {
		return 0, err
	}
	ctx := display.Context()
	defer ctx.Close()
	if err := ctx.SetReadDeadline(time.Now().Add(compositorProbeTimeout)); err != nil {
		return 0, err
	}

	registry, err := display.GetRegistry()
	if err != nil {
		return 0, err
	}
	var dmabuf *linux_dmabuf.ZwpLinuxDmabufV1
	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		if e.Interface != linux_dmabuf.ZwpLinuxDmabufV1InterfaceName || e.Version < dmabufFeedbackMinVersion {
			return
		}
		candidate := linux_dmabuf.NewZwpLinuxDmabufV1(ctx)
		if err := registry.Bind(e.Name, e.Interface, min(e.Version, dmabufMainDeviceMaxVersion), candidate); err != nil {
			return
		}
		dmabuf = candidate
	})
	if err := display.Roundtrip(); err != nil {
		return 0, err
	}
	if dmabuf == nil {
		return 0, errors.New("compositor lacks linux-dmabuf feedback")
	}
	defer dmabuf.Destroy()

	feedback, err := dmabuf.GetDefaultFeedback()
	if err != nil {
		return 0, err
	}
	defer feedback.Destroy()

	var device []byte
	done := false
	feedback.SetMainDeviceHandler(func(e linux_dmabuf.ZwpLinuxDmabufFeedbackV1MainDeviceEvent) {
		device = e.Device
	})
	feedback.SetDoneHandler(func(linux_dmabuf.ZwpLinuxDmabufFeedbackV1DoneEvent) {
		done = true
	})
	for !done {
		if err := ctx.Dispatch(); err != nil {
			return 0, err
		}
	}
	return mainDeviceFromEvent(device)
}

func mainDeviceFromEvent(device []byte) (uint64, error) {
	if len(device) != 8 {
		return 0, fmt.Errorf("main_device has %d bytes, want 8", len(device))
	}
	return binary.NativeEndian.Uint64(device), nil
}
