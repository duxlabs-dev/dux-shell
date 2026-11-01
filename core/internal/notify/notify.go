package notify

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	AppID = "dev.duxlabs.shell"

	appName = "DMS"

	notifyDest      = "org.freedesktop.Notifications"
	notifyPath      = "/org/freedesktop/Notifications"
	notifyInterface = "org.freedesktop.Notifications"

	signalClosed        = notifyInterface + ".NotificationClosed"
	signalActionInvoked = notifyInterface + ".ActionInvoked"

	listenerMaxLifetime = time.Hour
)

type Notification struct {
	AppName string
	// Notify app_icon argument. Falls back to Icon.
	AppIcon  string
	Icon     string
	Summary  string
	Body     string
	FilePath string
	// Milliseconds; 0 never expires, -1 lets the server decide.
	Timeout   int32
	ReplaceID uint32
	// Pairs of id, label; ignored when FilePath is set.
	Actions []string
	Hints   map[string]dbus.Variant
}

func Send(n Notification) (uint32, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return 0, fmt.Errorf("dbus session failed: %w", err)
	}

	if n.AppName == "" {
		n.AppName = appName
	}
	if n.Icon == "" && n.AppName == appName {
		n.Icon = AppID
	}

	actions := n.Actions
	if n.FilePath != "" {
		actions = []string{
			"open", "Open",
			"folder", "Open Folder",
		}
	}
	if actions == nil {
		actions = []string{}
	}

	hints := map[string]dbus.Variant{}
	if n.AppName == appName {
		hints["desktop-entry"] = dbus.MakeVariant(AppID)
	}
	if n.FilePath != "" {
		hints["image_path"] = dbus.MakeVariant(fileURI(n.FilePath))
	}
	appIcon := n.Icon
	if n.AppIcon != "" {
		appIcon = n.AppIcon
		if n.Icon != "" {
			hints["image-path"] = dbus.MakeVariant(n.Icon)
		}
	}
	for k, v := range n.Hints {
		hints[k] = v
	}

	obj := conn.Object(notifyDest, notifyPath)
	call := obj.Call(
		notifyInterface+".Notify",
		0,
		n.AppName,
		n.ReplaceID,
		appIcon,
		n.Summary,
		n.Body,
		actions,
		hints,
		n.Timeout,
	)

	if call.Err != nil {
		return 0, fmt.Errorf("notify call failed: %w", call.Err)
	}

	var notificationID uint32
	if err := call.Store(&notificationID); err != nil {
		return 0, fmt.Errorf("failed to get notification id: %w", err)
	}

	return notificationID, nil
}

func fileURI(path string) string {
	if strings.HasPrefix(path, "file://") {
		return path
	}
	return "file://" + path
}

// Waiter subscribes to notification signals. Create it before Send so an
// instant action or close cannot slip past the subscription.
type Waiter struct {
	conn    *dbus.Conn
	signals chan *dbus.Signal
}

func NewWaiter() (*Waiter, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("dbus session failed: %w", err)
	}
	if err := conn.AddMatchSignal(
		dbus.WithMatchObjectPath(notifyPath),
		dbus.WithMatchInterface(notifyInterface),
	); err != nil {
		return nil, fmt.Errorf("dbus match failed: %w", err)
	}
	w := &Waiter{conn: conn, signals: make(chan *dbus.Signal, 10)}
	conn.Signal(w.signals)
	return w, nil
}

func (w *Waiter) Close() {
	w.conn.RemoveSignal(w.signals)
	_ = w.conn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(notifyPath),
		dbus.WithMatchInterface(notifyInterface),
	)
}

type WaitResult struct {
	Action   string
	Invoked  bool
	TimedOut bool
}

// Blocks until the notification closes or one of its actions fires.
// A timeout of zero or less waits forever.
func (w *Waiter) Wait(id uint32, timeout time.Duration) WaitResult {
	var deadline <-chan time.Time
	if timeout > 0 {
		deadline = time.After(timeout)
	}
	for {
		select {
		case <-deadline:
			return WaitResult{TimedOut: true}
		case sig, ok := <-w.signals:
			if !ok {
				return WaitResult{}
			}
			res, done := matchSignal(sig, id)
			if done {
				return res
			}
		}
	}
}

func matchSignal(sig *dbus.Signal, id uint32) (WaitResult, bool) {
	if sig == nil || len(sig.Body) < 1 {
		return WaitResult{}, false
	}
	sigID, ok := sig.Body[0].(uint32)
	if !ok || sigID != id {
		return WaitResult{}, false
	}
	switch sig.Name {
	case signalClosed:
		return WaitResult{}, true
	case signalActionInvoked:
		if len(sig.Body) < 2 {
			return WaitResult{}, false
		}
		action, ok := sig.Body[1].(string)
		if !ok {
			return WaitResult{}, false
		}
		return WaitResult{Action: action, Invoked: true}, true
	}
	return WaitResult{}, false
}

func SpawnActionListener(notificationID uint32, filePath string) {
	exe, err := os.Executable()
	if err != nil {
		return
	}

	cmd := exec.Command(exe, "notify-action-generic", fmt.Sprintf("%d", notificationID), filePath)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setsid: true,
	}
	cmd.Start()
}

func RunActionListener(args []string) {
	if len(args) < 2 {
		return
	}

	notificationID, err := strconv.ParseUint(args[0], 10, 32)
	if err != nil {
		return
	}

	filePath := args[1]

	w, err := NewWaiter()
	if err != nil {
		return
	}
	defer w.Close()

	res := w.Wait(uint32(notificationID), listenerMaxLifetime)
	if !res.Invoked {
		return
	}
	handleAction(res.Action, filePath)
}

func handleAction(action, filePath string) {
	switch action {
	case "open", "default":
		openPath(filePath)
	case "folder":
		openPath(filepath.Dir(filePath))
	}
}

func openPath(path string) {
	cmd := exec.Command("xdg-open", path)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setsid: true,
	}
	cmd.Start()
}
