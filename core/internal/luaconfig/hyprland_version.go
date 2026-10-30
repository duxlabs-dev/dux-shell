package luaconfig

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"sync"
)

// HyprlandVersion is the running compositor's major.minor, 0.0 when hyprctl is unavailable. Tests replace it.
var HyprlandVersion = sync.OnceValues(func() (int, int) {
	output, err := exec.Command("hyprctl", "-j", "version").Output()
	if err != nil {
		return 0, 0
	}
	var info struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(output, &info); err != nil {
		return 0, 0
	}
	var major, minor int
	fmt.Sscanf(info.Version, "%d.%d", &major, &minor)
	return major, minor
})

func HyprlandAtLeast(major, minor int) bool {
	haveMajor, haveMinor := HyprlandVersion()
	if haveMajor != major {
		return haveMajor > major
	}
	return haveMinor >= minor
}
