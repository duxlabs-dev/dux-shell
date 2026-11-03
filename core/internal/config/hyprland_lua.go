package config

import (
	"fmt"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	hyprlandStartupBegin = "-- DMS_STARTUP_BEGIN"
	hyprlandStartupEnd   = "-- DMS_STARTUP_END"
)

func transformHyprlandLuaForNonSystemd(config, terminalCommand string) string {
	start := strings.Index(config, hyprlandStartupBegin)
	end := strings.Index(config, hyprlandStartupEnd)
	if start == -1 || end == -1 || end <= start {
		return config
	}
	endClose := end + len(hyprlandStartupEnd)
	replacement := hyprlandStartupBegin + "\n" +
		`hl.env("QT_QPA_PLATFORM", "wayland;xcb")` + "\n" +
		`hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")` + "\n" +
		`hl.env("QT_QPA_PLATFORMTHEME", "gtk3")` + "\n" +
		`hl.env("QT_QPA_PLATFORMTHEME_QT6", "gtk3")` + "\n" +
		fmt.Sprintf(`hl.env("TERMINAL", %s)`, strconv.Quote(terminalCommand)) + "\n\n" +
		`hl.on("hyprland.start", function()` + "\n" +
		`	hl.exec_cmd("dms run")` + "\n" +
		`end)` + "\n" +
		hyprlandStartupEnd
	return config[:start] + replacement + config[endClose:]
}

func HyprlandConfigDir() string {
	return filepath.Join(utils.XDGConfigHome(), "hypr")
}
