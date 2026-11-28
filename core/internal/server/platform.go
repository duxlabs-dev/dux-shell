package server

import (
	"os"
	"strings"
	"sync"
)

// Read once: the device tree only changes across reboots.
var deviceCompatible = sync.OnceValue(func() []string {
	data, err := os.ReadFile("/proc/device-tree/compatible")
	if err != nil {
		return nil
	}
	return parseCompatible(data)
})

func parseCompatible(data []byte) []string {
	var out []string
	for entry := range strings.SplitSeq(string(data), "\x00") {
		if entry != "" {
			out = append(out, entry)
		}
	}
	return out
}
