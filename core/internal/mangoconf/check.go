// Package mangoconf holds what DMS knows about Mango's config files: where they
// live, the session target, and the markers DMS leaves in the binds fragment.
package mangoconf

import (
	"fmt"
	"strings"
)

// Mango reads each line into a 512-byte buffer and the value into 255 bytes; longer is cut silently.
const maxValueLen = 255

func CheckLine(line string) error {
	_, value, ok := strings.Cut(line, "=")
	if !ok || len(strings.TrimSpace(value)) <= maxValueLen {
		return nil
	}
	return fmt.Errorf("line is %d characters after '='; Mango truncates past %d", len(strings.TrimSpace(value)), maxValueLen)
}
