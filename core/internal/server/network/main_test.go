package network

import (
	"os"
	"testing"
)

// Tests must never reach the real NetworkManager.
func TestMain(m *testing.M) {
	os.Setenv("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/nonexistent")
	os.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent")
	os.Exit(m.Run())
}
