package screenshot

import (
	"bufio"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"net"
	"os"
	"path/filepath"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const niriScreenshotTimeout = 5 * time.Second

// CaptureNiriWindowImage captures the focused window through niri's
// ScreenshotWindow action; niri replies before writing the file, so a second
// event-stream connection waits for ScreenshotCaptured. niri also copies the
// capture to its own clipboard, which cannot be disabled.
func CaptureNiriWindowImage(showPointer bool) (image.Image, error) {
	socket := os.Getenv("NIRI_SOCKET")
	if socket == "" {
		return nil, fmt.Errorf("NIRI_SOCKET not set")
	}

	path := filepath.Join(utils.RuntimeDir(), fmt.Sprintf("dms-window-%d.png", os.Getpid()))

	events, err := subscribeNiriEvents(socket)
	if err != nil {
		return nil, err
	}
	defer events.Close()

	if err := requestNiriWindowScreenshot(socket, path, showPointer); err != nil {
		return nil, err
	}
	defer os.Remove(path)

	if err := awaitNiriScreenshot(events, path); err != nil {
		return nil, err
	}

	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open niri screenshot: %w", err)
	}
	defer f.Close()

	img, err := png.Decode(f)
	if err != nil {
		return nil, fmt.Errorf("decode niri screenshot: %w", err)
	}
	return img, nil
}

func subscribeNiriEvents(socket string) (net.Conn, error) {
	conn, err := net.DialTimeout("unix", socket, 2*time.Second)
	if err != nil {
		return nil, fmt.Errorf("connect niri socket: %w", err)
	}
	_ = conn.SetDeadline(time.Now().Add(niriScreenshotTimeout))

	if _, err := conn.Write([]byte("\"EventStream\"\n")); err != nil {
		conn.Close()
		return nil, fmt.Errorf("subscribe niri events: %w", err)
	}
	return conn, nil
}

func awaitNiriScreenshot(events net.Conn, path string) error {
	scanner := bufio.NewScanner(events)
	scanner.Buffer(make([]byte, 0, 64<<10), 1<<20)

	for scanner.Scan() {
		var event struct {
			ScreenshotCaptured *struct {
				Path string `json:"path"`
			} `json:"ScreenshotCaptured"`
		}
		if json.Unmarshal(scanner.Bytes(), &event) != nil {
			continue
		}
		if event.ScreenshotCaptured != nil && event.ScreenshotCaptured.Path == path {
			return nil
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("await niri screenshot: %w", err)
	}
	return fmt.Errorf("niri event stream closed before screenshot completed")
}

func requestNiriWindowScreenshot(socket, path string, showPointer bool) error {
	conn, err := net.DialTimeout("unix", socket, 2*time.Second)
	if err != nil {
		return fmt.Errorf("connect niri socket: %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(3 * time.Second))

	request := map[string]any{
		"Action": map[string]any{
			"ScreenshotWindow": map[string]any{
				"id":            nil,
				"write_to_disk": true,
				"show_pointer":  showPointer,
				"path":          path,
			},
		},
	}
	payload, err := json.Marshal(request)
	if err != nil {
		return err
	}
	if _, err := conn.Write(append(payload, '\n')); err != nil {
		return fmt.Errorf("niri request: %w", err)
	}

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		return fmt.Errorf("niri reply: %w", err)
	}

	var reply map[string]json.RawMessage
	if err := json.Unmarshal(line, &reply); err != nil {
		return fmt.Errorf("parse niri reply: %w", err)
	}
	if raw, ok := reply["Err"]; ok {
		var msg string
		_ = json.Unmarshal(raw, &msg)
		return fmt.Errorf("niri screenshot: %s", msg)
	}
	return nil
}

func (s *Screenshoter) captureNiriWindow() (*CaptureResult, error) {
	img, err := CaptureNiriWindowImage(s.config.Cursor == CursorOn)
	if err != nil {
		return nil, err
	}

	buf, err := ImageToBuffer(img)
	if err != nil {
		return nil, err
	}

	scale := 1.0
	if output := s.findOutputByName(GetFocusedMonitor()); output != nil {
		scale = output.effectiveScale()
	}

	return &CaptureResult{
		Buffer: buf,
		Region: Region{
			Width:  int32(img.Bounds().Dx()),
			Height: int32(img.Bounds().Dy()),
		},
		YInverted: false,
		Format:    uint32(FormatARGB8888),
		Scale:     scale,
	}, nil
}
