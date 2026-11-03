package clipboard

import (
	"bytes"
	"fmt"
	"image"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"

	"github.com/duxlabs-dev/dux-go/wayland/ext_data_control"
	"github.com/duxlabs-dev/dux-go/wlclipboard"
)

const envServe = "_DMS_CLIPBOARD_SERVE"
const envMime = "_DMS_CLIPBOARD_MIME"
const envPasteOnce = "_DMS_CLIPBOARD_PASTE_ONCE"
const envCacheFile = "_DMS_CLIPBOARD_CACHE"
const envReady = "_DMS_CLIPBOARD_READY"

// MaybeServeAndExit intercepts before cobra when re-exec'd as a clipboard
// child. Reads source data into memory, deletes any cache file, then serves.
func MaybeServeAndExit() {
	if os.Getenv(envServe) == "" {
		return
	}

	mimeType := os.Getenv(envMime)
	pasteOnce := os.Getenv(envPasteOnce) == "1"
	cachePath := os.Getenv(envCacheFile)

	var data []byte
	var err error

	switch {
	case cachePath != "":
		data, err = os.ReadFile(cachePath)
		os.Remove(cachePath)
	default:
		data, err = io.ReadAll(os.Stdin)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "clipboard: read source: %v\n", err)
		os.Exit(1)
	}

	if err := serveOffers(wlclipboard.ExpandOffers(data, mimeType), pasteOnce); err != nil {
		fmt.Fprintf(os.Stderr, "clipboard: serve: %v\n", err)
		os.Exit(1)
	}
	os.Exit(0)
}

func Copy(data []byte, mimeType string) error {
	return copyForkCached(data, mimeType, false)
}

func CopyText(text string) error {
	return Copy([]byte(text), "text/plain;charset=utf-8")
}

func CopyOpts(data []byte, mimeType string, foreground, pasteOnce bool) error {
	if foreground {
		return serveOffers(wlclipboard.ExpandOffers(data, mimeType), pasteOnce)
	}
	return copyForkCached(data, mimeType, pasteOnce)
}

func CopyReader(data io.Reader, mimeType string, foreground, pasteOnce bool) error {
	if !foreground {
		return copyFork(data, mimeType, pasteOnce)
	}
	buf, err := io.ReadAll(data)
	if err != nil {
		return fmt.Errorf("read source: %w", err)
	}
	return serveOffers(wlclipboard.ExpandOffers(buf, mimeType), pasteOnce)
}

func CopyMulti(offers []wlclipboard.Offer, foreground, pasteOnce bool) error {
	if foreground {
		return serveOffers(offers, pasteOnce)
	}
	return copyMultiFork(offers, pasteOnce)
}

// FileOffers builds the offers for copying a file; uriPath may differ from path when the file was exported for flatpak.
func FileOffers(uriPath, path string, data []byte) []wlclipboard.Offer {
	fileURI := (&url.URL{Scheme: "file", Path: uriPath}).String()
	offers := []wlclipboard.Offer{
		{MimeType: "x-special/gnome-copied-files", Data: []byte("copy\n" + fileURI)},
		{MimeType: "text/uri-list", Data: []byte(fileURI + "\r\n")},
		{MimeType: "text/plain", Data: []byte(path)},
	}
	if _, imgFormat, err := image.DecodeConfig(bytes.NewReader(data)); err == nil {
		offers = append(offers, wlclipboard.Offer{MimeType: "image/" + imgFormat, Data: data})
	}
	return offers
}

func newForkCmd(mimeType string, pasteOnce bool, extra ...string) *exec.Cmd {
	cmd := exec.Command(os.Args[0])
	cmd.Stderr = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Env = append(os.Environ(),
		envServe+"=1",
		envMime+"="+mimeType,
	)
	if pasteOnce {
		cmd.Env = append(cmd.Env, envPasteOnce+"=1")
	}
	cmd.Env = append(cmd.Env, extra...)
	return cmd
}

func waitReady(cmd *exec.Cmd) error {
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("stdout pipe: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start: %w", err)
	}
	var buf [1]byte
	if _, err := stdout.Read(buf[:]); err != nil {
		return fmt.Errorf("waiting for clipboard ready: %w", err)
	}
	return nil
}

func copyForkCached(data []byte, mimeType string, pasteOnce bool) error {
	cacheFile, err := createClipboardCacheFile()
	if err != nil {
		return fmt.Errorf("create cache file: %w", err)
	}
	cachePath := cacheFile.Name()

	if _, err := cacheFile.Write(data); err != nil {
		cacheFile.Close()
		os.Remove(cachePath)
		return fmt.Errorf("write cache file: %w", err)
	}
	if err := cacheFile.Close(); err != nil {
		os.Remove(cachePath)
		return fmt.Errorf("close cache file: %w", err)
	}

	cmd := newForkCmd(mimeType, pasteOnce, envCacheFile+"="+cachePath)
	cmd.Stdin = nil
	if err := waitReady(cmd); err != nil {
		os.Remove(cachePath)
		return err
	}
	return nil
}

func copyFork(data io.Reader, mimeType string, pasteOnce bool) error {
	cmd := newForkCmd(mimeType, pasteOnce)

	if src, ok := data.(*os.File); ok {
		cmd.Stdin = src
		return waitReady(cmd)
	}

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("stdin pipe: %w", err)
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("stdout pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start: %w", err)
	}
	if _, err := io.Copy(stdin, data); err != nil {
		stdin.Close()
		return fmt.Errorf("write stdin: %w", err)
	}
	if err := stdin.Close(); err != nil {
		return fmt.Errorf("close stdin: %w", err)
	}

	var buf [1]byte
	if _, err := stdout.Read(buf[:]); err != nil {
		return fmt.Errorf("waiting for clipboard ready: %w", err)
	}
	return nil
}

func copyMultiFork(offers []wlclipboard.Offer, pasteOnce bool) error {
	args := []string{os.Args[0], "cl", "copy", "--foreground", "--type", "__multi__"}
	if pasteOnce {
		args = append(args, "--paste-once")
	}

	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stderr = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Env = append(os.Environ(), envReady+"=1")

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("stdin pipe: %w", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("stdout pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start: %w", err)
	}

	for _, offer := range offers {
		fmt.Fprintf(stdin, "%s\x00%d\x00", offer.MimeType, len(offer.Data))
		if _, err := stdin.Write(offer.Data); err != nil {
			stdin.Close()
			return fmt.Errorf("write offer data: %w", err)
		}
	}
	if err := stdin.Close(); err != nil {
		return fmt.Errorf("close stdin: %w", err)
	}

	var buf [1]byte
	if _, err := stdout.Read(buf[:]); err != nil {
		return fmt.Errorf("waiting for clipboard ready: %w", err)
	}
	return nil
}

func signalReady() {
	if os.Getenv(envServe) == "" && os.Getenv(envReady) == "" {
		return
	}
	os.Stdout.Write([]byte{1})
}

func createClipboardCacheFile() (*os.File, error) {
	preferredDirs := []string{}

	if cacheDir, err := os.UserCacheDir(); err == nil {
		preferredDirs = append(preferredDirs, filepath.Join(cacheDir, "dms", "clipboard"))
	}
	preferredDirs = append(preferredDirs, "/var/tmp/dms/clipboard")

	for _, dir := range preferredDirs {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			continue
		}
		cachedData, err := os.CreateTemp(dir, "dms-clipboard-*")
		if err == nil {
			return cachedData, nil
		}
	}
	return os.CreateTemp("", "dms-clipboard-*")
}

// serveOffers owns the Wayland selection until cancelled (or first paste when
// pasteOnce is set), answering every offered mime type with its data.
func serveOffers(offers []wlclipboard.Offer, pasteOnce bool) error {
	if len(offers) == 0 {
		return fmt.Errorf("no offers to serve")
	}

	s, err := connectSession()
	if err != nil {
		return err
	}
	defer s.Close()

	dataControlMgr, err := s.requireDataControl()
	if err != nil {
		return err
	}

	device, err := dataControlMgr.GetDataDevice(s.seat)
	if err != nil {
		return fmt.Errorf("get data device: %w", err)
	}
	defer device.Destroy()

	source, err := dataControlMgr.CreateDataSource()
	if err != nil {
		return fmt.Errorf("create data source: %w", err)
	}

	offerData := make(map[string][]byte, len(offers))
	for _, offer := range offers {
		if err := source.Offer(offer.MimeType); err != nil {
			return fmt.Errorf("offer %s: %w", offer.MimeType, err)
		}
		offerData[offer.MimeType] = offer.Data
	}

	cancelled := make(chan struct{})
	pasted := make(chan struct{}, 1)

	source.SetSendHandler(func(e ext_data_control.ExtDataControlSourceV1SendEvent) {
		_ = syscall.SetNonblock(e.Fd, false)
		file := os.NewFile(uintptr(e.Fd), "pipe")
		defer file.Close()

		if data, ok := offerData[e.MimeType]; ok {
			_, _ = file.Write(data)
		}

		select {
		case pasted <- struct{}{}:
		default:
		}
	})

	source.SetCancelledHandler(func(e ext_data_control.ExtDataControlSourceV1CancelledEvent) {
		close(cancelled)
	})

	if err := device.SetSelection(source); err != nil {
		return fmt.Errorf("set selection: %w", err)
	}

	s.display.Roundtrip()
	signalReady()

	for {
		select {
		case <-cancelled:
			return nil
		case <-pasted:
			if pasteOnce {
				return nil
			}
		default:
			if err := s.ctx.Dispatch(); err != nil {
				return nil
			}
		}
	}
}

func IsImageMimeType(mime string) bool {
	return len(mime) > 6 && mime[:6] == "image/"
}
