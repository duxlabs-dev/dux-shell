package clipboard

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/duxlabs-dev/dux-go/wayland/ext_data_control"
)

// WatchAll subscribes to clipboard selection changes like wlclipboard.Watch,
// additionally reporting every mime type each selection offers.
func WatchAll(ctx context.Context, callback func(data []byte, mimeType string, allMimeTypes []string)) error {
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

	offerMimeTypes := make(map[*ext_data_control.ExtDataControlOfferV1][]string)

	device.SetDataOfferHandler(func(e ext_data_control.ExtDataControlDeviceV1DataOfferEvent) {
		if e.Id == nil {
			return
		}
		offerMimeTypes[e.Id] = nil
		e.Id.SetOfferHandler(func(me ext_data_control.ExtDataControlOfferV1OfferEvent) {
			offerMimeTypes[e.Id] = append(offerMimeTypes[e.Id], me.MimeType)
		})
	})

	device.SetSelectionHandler(func(e ext_data_control.ExtDataControlDeviceV1SelectionEvent) {
		if e.Id == nil {
			return
		}

		mimes := offerMimeTypes[e.Id]
		selectedMime := selectPreferredMimeType(mimes)
		if selectedMime == "" {
			return
		}

		mimesCopy := make([]string, len(mimes))
		copy(mimesCopy, mimes)

		r, w, err := os.Pipe()
		if err != nil {
			return
		}

		if err := e.Id.Receive(selectedMime, int(w.Fd())); err != nil {
			w.Close()
			r.Close()
			return
		}
		w.Close()

		go func() {
			defer r.Close()
			data, err := io.ReadAll(r)
			if err != nil || len(data) == 0 {
				return
			}
			callback(data, selectedMime, mimesCopy)
		}()
	})

	s.display.Roundtrip()
	s.display.Roundtrip()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			if err := s.ctx.SetReadDeadline(time.Now().Add(100 * time.Millisecond)); err != nil {
				return fmt.Errorf("set read deadline: %w", err)
			}
			if err := s.ctx.Dispatch(); err != nil {
				if isTimeoutError(err) {
					continue
				}
				return fmt.Errorf("dispatch: %w", err)
			}
		}
	}
}

func selectPreferredMimeType(mimes []string) string {
	preferred := []string{
		"text/plain;charset=utf-8",
		"text/plain",
		"UTF8_STRING",
		"STRING",
		"TEXT",
		"image/png",
		"image/jpeg",
	}

	for _, pref := range preferred {
		for _, mime := range mimes {
			if mime == pref {
				return mime
			}
		}
	}

	if len(mimes) > 0 {
		return mimes[0]
	}
	return ""
}

func isTimeoutError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, os.ErrDeadlineExceeded) {
		return true
	}
	if netErr, ok := err.(interface{ Timeout() bool }); ok && netErr.Timeout() {
		return true
	}
	return false
}
