package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/notify"
	"github.com/godbus/dbus/v5"
	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
)

var (
	notifyAppName   string
	notifyAppIcon   string
	notifyIcon      string
	notifyFile      string
	notifyTimeout   int
	notifyUrgency   string
	notifyCategory  string
	notifyTransient bool
	notifyHints     []string
	notifyActions   []string
	notifyPrintID   bool
	notifyReplaceID uint32
	notifyWait      bool
	notifyIDFd      int
	notifyActionFd  int
)

var notifyCmd = &cobra.Command{
	Use:   "notify <summary> [body]",
	Short: "Send a desktop notification",
	Long: `Send a desktop notification. Flags follow notify-send.

If --file is provided, the notification gets "Open" and "Open Folder" actions
that open the file or its directory when clicked.

Examples:
  dms notify "Hello" "World"
  dms notify -u critical -t 0 "Disk almost full"
  dms notify -a "Backup" -i drive-harddisk -c transfer.complete "Backup finished"
  dms notify "File received" "photo.jpg" --file ~/Downloads/photo.jpg
  dms notify -A retry=Retry -A "Dismiss" "Build failed"
  dms notify -h string:x-dms-tag:build -h int:value:42 "Hinted"`,
	Args: cobra.MinimumNArgs(1),
	Run:  runNotify,
}

var genericNotifyActionCmd = &cobra.Command{
	Use:    "notify-action-generic",
	Hidden: true,
	Run: func(cmd *cobra.Command, args []string) {
		notify.RunActionListener(args)
	},
}

var notifyFlagAliases = map[string]string{
	"app":     "app-name",
	"timeout": "expire-time",
}

func init() {
	f := notifyCmd.Flags()
	f.SetNormalizeFunc(func(fs *pflag.FlagSet, name string) pflag.NormalizedName {
		if alias, ok := notifyFlagAliases[name]; ok {
			return pflag.NormalizedName(alias)
		}
		return pflag.NormalizedName(name)
	})
	// Frees -h for --hint like notify-send; cobra skips its own help flag when one exists.
	f.Bool("help", false, "Show help")
	f.StringVarP(&notifyUrgency, "urgency", "u", "", "Urgency level: low, normal, critical")
	f.IntVarP(&notifyTimeout, "expire-time", "t", -1, "Timeout in milliseconds (0 never expires, -1 server default)")
	f.StringVarP(&notifyAppName, "app-name", "a", "DMS", "Application name")
	f.StringVarP(&notifyIcon, "icon", "i", "", "Icon name or path")
	f.StringVarP(&notifyAppIcon, "app-icon", "n", "", "Application icon name or path; --icon then becomes the image")
	f.StringVar(&notifyCategory, "category", "", "Notification category, comma separated (-c is taken by the global --config)")
	f.BoolVarP(&notifyTransient, "transient", "e", false, "Do not keep the notification in history")
	f.StringArrayVarP(&notifyHints, "hint", "h", nil, "Extra hint as TYPE:NAME:VALUE (boolean, int, double, string, byte)")
	f.BoolVarP(&notifyPrintID, "print-id", "p", false, "Print the notification id")
	f.IntVar(&notifyIDFd, "id-fd", -1, "File descriptor to write the notification id to")
	f.Uint32VarP(&notifyReplaceID, "replace-id", "r", 0, "Id of the notification to replace")
	f.BoolVarP(&notifyWait, "wait", "w", false, "Wait until the notification closes")
	f.StringArrayVarP(&notifyActions, "action", "A", nil, "Action as [NAME=]Text; implies --wait, prints the chosen NAME (repeatable)")
	f.IntVar(&notifyActionFd, "selected-action-fd", -1, "File descriptor to write the chosen action to")
	f.StringVar(&notifyFile, "file", "", "File path (enables Open/Open Folder actions)")
}

func runNotify(cmd *cobra.Command, args []string) {
	n, err := buildNotification(args)
	if err != nil {
		fail(err)
	}

	wait := notifyWait || len(n.Actions) > 0
	var waiter *notify.Waiter
	if wait {
		waiter, err = notify.NewWaiter()
		if err != nil {
			fail(err)
		}
		defer waiter.Close()
	}

	id, err := notify.Send(n)
	if err != nil {
		fail(err)
	}
	reportID(id)

	if n.FilePath != "" {
		watchNotificationAction(id, n.FilePath)
	}
	if !wait {
		return
	}
	if id == 0 {
		return
	}
	res := waiter.Wait(id, waitTimeout())
	if res.TimedOut {
		fmt.Fprintln(os.Stderr, "Wait timeout expired")
		return
	}
	if !res.Invoked {
		return
	}
	fmt.Println(res.Action)
	writeFd(notifyActionFd, res.Action)
}

func buildNotification(args []string) (notify.Notification, error) {
	n := notify.Notification{
		AppName:   notifyAppName,
		AppIcon:   notifyAppIcon,
		Icon:      notifyIcon,
		Summary:   args[0],
		FilePath:  notifyFile,
		Timeout:   int32(notifyTimeout),
		ReplaceID: notifyReplaceID,
		Hints:     map[string]dbus.Variant{},
	}
	if len(args) > 1 {
		n.Body = args[1]
	}
	if notifyFile != "" && len(notifyActions) > 0 {
		return n, fmt.Errorf("--file and --action cannot be combined")
	}
	if notifyUrgency != "" {
		level, err := parseUrgency(notifyUrgency)
		if err != nil {
			return n, err
		}
		n.Hints["urgency"] = dbus.MakeVariant(level)
	}
	if notifyCategory != "" {
		n.Hints["category"] = dbus.MakeVariant(notifyCategory)
	}
	if notifyTransient {
		n.Hints["transient"] = dbus.MakeVariant(true)
	}
	for _, spec := range notifyHints {
		name, value, err := parseHint(spec)
		if err != nil {
			return n, err
		}
		n.Hints[name] = value
	}
	n.Actions = parseActions(notifyActions)
	return n, nil
}

func parseUrgency(s string) (byte, error) {
	switch strings.ToLower(s) {
	case "low", "0":
		return 0, nil
	case "normal", "1":
		return 1, nil
	case "critical", "2":
		return 2, nil
	}
	return 0, fmt.Errorf("invalid urgency %q: use low, normal or critical", s)
}

func parseHint(spec string) (string, dbus.Variant, error) {
	parts := strings.SplitN(spec, ":", 3)
	if len(parts) != 3 || parts[1] == "" {
		return "", dbus.Variant{}, fmt.Errorf("invalid hint %q: expected TYPE:NAME:VALUE", spec)
	}
	typ, name, value := strings.ToLower(parts[0]), parts[1], parts[2]
	switch typ {
	case "string":
		return name, dbus.MakeVariant(value), nil
	case "int":
		v, err := strconv.ParseInt(value, 10, 32)
		if err != nil {
			return "", dbus.Variant{}, fmt.Errorf("hint %s: invalid int %q", name, value)
		}
		return name, dbus.MakeVariant(int32(v)), nil
	case "double":
		v, err := strconv.ParseFloat(value, 64)
		if err != nil {
			return "", dbus.Variant{}, fmt.Errorf("hint %s: invalid double %q", name, value)
		}
		return name, dbus.MakeVariant(v), nil
	case "byte":
		v, err := strconv.ParseUint(value, 0, 8)
		if err != nil {
			return "", dbus.Variant{}, fmt.Errorf("hint %s: invalid byte %q", name, value)
		}
		return name, dbus.MakeVariant(byte(v)), nil
	case "boolean":
		v, err := parseBoolean(value)
		if err != nil {
			return "", dbus.Variant{}, fmt.Errorf("hint %s: invalid boolean %q", name, value)
		}
		return name, dbus.MakeVariant(v), nil
	}
	return "", dbus.Variant{}, fmt.Errorf("invalid hint type %q: use boolean, int, double, string or byte", parts[0])
}

func parseBoolean(s string) (bool, error) {
	switch strings.ToLower(s) {
	case "true":
		return true, nil
	case "false":
		return false, nil
	}
	v, err := strconv.ParseUint(s, 10, 64)
	if err != nil {
		return false, err
	}
	return v != 0, nil
}

func parseActions(specs []string) []string {
	if len(specs) == 0 {
		return nil
	}
	actions := make([]string, 0, len(specs)*2)
	for i, spec := range specs {
		name, label, hasName := strings.Cut(spec, "=")
		if !hasName {
			name, label = strconv.Itoa(i), spec
		}
		actions = append(actions, name, label)
	}
	return actions
}

func waitTimeout() time.Duration {
	if notifyTimeout <= 0 {
		return 0
	}
	return time.Duration(notifyTimeout) * time.Millisecond
}

func reportID(id uint32) {
	if notifyPrintID {
		fmt.Println(id)
	}
	writeFd(notifyIDFd, strconv.FormatUint(uint64(id), 10))
}

func writeFd(fd int, line string) {
	if fd < 0 {
		return
	}
	f := os.NewFile(uintptr(fd), "")
	if f == nil {
		return
	}
	fmt.Fprintln(f, line)
	_ = f.Sync()
}

func fail(err error) {
	fmt.Fprintf(os.Stderr, "Error: %v\n", err)
	os.Exit(1)
}

func watchNotificationAction(id uint32, path string) {
	if id == 0 {
		return
	}
	resp, ok := tryServerRequest(ipc.Request{
		Method: "notify.watchAction",
		Params: map[string]any{"id": id, "path": path},
	})
	if ok && resp.Error == "" {
		return
	}
	notify.SpawnActionListener(id, path)
}
