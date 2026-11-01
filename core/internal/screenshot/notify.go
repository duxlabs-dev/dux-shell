package screenshot

import (
	"fmt"
	"path/filepath"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/notify"
	"github.com/godbus/dbus/v5"
)

const (
	notifyDest      = "org.freedesktop.Notifications"
	notifyPath      = "/org/freedesktop/Notifications"
	notifyInterface = "org.freedesktop.Notifications"
)

type NotifyResult struct {
	FilePath  string
	Clipboard bool
	ImageData []byte
	Width     int
	Height    int
}

func SendNotification(result NotifyResult) uint32 {
	conn, err := dbus.SessionBus()
	if err != nil {
		log.Debug("dbus session failed", "err", err)
		return 0
	}

	var actions []string
	if result.FilePath != "" {
		actions = []string{"default", "Open"}
	}

	hints := map[string]dbus.Variant{
		"desktop-entry": dbus.MakeVariant(notify.AppID),
	}
	if len(result.ImageData) > 0 && result.Width > 0 && result.Height > 0 {
		rowstride := result.Width * 4
		hints["image_data"] = dbus.MakeVariant(struct {
			Width         int32
			Height        int32
			Rowstride     int32
			HasAlpha      bool
			BitsPerSample int32
			Channels      int32
			Data          []byte
		}{
			Width:         int32(result.Width),
			Height:        int32(result.Height),
			Rowstride:     int32(rowstride),
			HasAlpha:      true,
			BitsPerSample: 8,
			Channels:      4,
			Data:          result.ImageData,
		})
	} else if result.FilePath != "" {
		hints["image_path"] = dbus.MakeVariant(result.FilePath)
	}

	summary := "Screenshot captured"
	body := ""
	switch {
	case result.FilePath != "" && result.Clipboard:
		body = fmt.Sprintf("%s\nCopied to clipboard", filepath.Base(result.FilePath))
	case result.FilePath != "":
		body = filepath.Base(result.FilePath)
	case result.Clipboard:
		body = "Copied to clipboard"
	}

	obj := conn.Object(notifyDest, notifyPath)
	call := obj.Call(
		notifyInterface+".Notify",
		0,
		"DMS",
		uint32(0),
		notify.AppID,
		summary,
		body,
		actions,
		hints,
		int32(5000),
	)

	if call.Err != nil {
		log.Debug("notify call failed", "err", call.Err)
		return 0
	}

	var notificationID uint32
	if err := call.Store(&notificationID); err != nil {
		log.Debug("failed to get notification id", "err", err)
		return 0
	}

	if len(actions) == 0 {
		return 0
	}
	return notificationID
}
