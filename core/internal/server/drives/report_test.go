package drives

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestFullReportRejectsNonDevices(t *testing.T) {
	for _, dev := range []string{"", "nvme0n1", "/dev/../etc/passwd", "/dev/nvme0n1 -d", "/tmp/x", "/dev/null"} {
		_, err := FullReport(dev)
		assert.Error(t, err, dev)
	}
}
