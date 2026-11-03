package brightness

import (
	"errors"
	"testing"

	mocks_brightness "github.com/duxlabs-dev/dux-shell/core/internal/mocks/brightness"
	mock_dbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/mock"
)

func TestLogindBackend_SetBrightness_Success(t *testing.T) {
	mockConn := mocks_brightness.NewMockDBusConn(t)
	mockObj := mock_dbus.NewMockBusObject(t)

	backend := NewLogindBackendWithConn(mockConn)

	mockConn.EXPECT().
		Object("org.freedesktop.login1", dbus.ObjectPath("/org/freedesktop/login1/session/auto")).
		Return(mockObj).
		Once()

	mockObj.EXPECT().
		Call("org.freedesktop.login1.Session.SetBrightness", dbus.Flags(0), "backlight", "nvidia_0", uint32(75)).
		Return(&dbus.Call{Err: nil}).
		Once()

	err := backend.SetBrightness("backlight", "nvidia_0", 75)
	if err != nil {
		t.Errorf("SetBrightness() error = %v, want nil", err)
	}
}

func TestLogindBackend_SetBrightness_DBusError(t *testing.T) {
	mockConn := mocks_brightness.NewMockDBusConn(t)
	mockObj := mock_dbus.NewMockBusObject(t)

	backend := NewLogindBackendWithConn(mockConn)

	mockConn.EXPECT().
		Object("org.freedesktop.login1", dbus.ObjectPath("/org/freedesktop/login1/session/auto")).
		Return(mockObj).
		Once()

	dbusErr := errors.New("permission denied")
	mockObj.EXPECT().
		Call("org.freedesktop.login1.Session.SetBrightness", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&dbus.Call{Err: dbusErr}).
		Once()

	err := backend.SetBrightness("backlight", "test_device", 50)
	if err == nil {
		t.Error("SetBrightness() error = nil, want error")
	}
}
