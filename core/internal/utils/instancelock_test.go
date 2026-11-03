package utils

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTryLockRejectsSecondHolder(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())

	held, err := TryLock(SelectionOverlayLock)
	require.NoError(t, err)

	_, err = TryLock(SelectionOverlayLock)
	assert.ErrorIs(t, err, ErrLockHeld)

	held.Release()

	reacquired, err := TryLock(SelectionOverlayLock)
	require.NoError(t, err)
	reacquired.Release()
}

func TestTryLockSeparatesNames(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())

	first, err := TryLock("dms-test-a")
	require.NoError(t, err)
	defer first.Release()

	second, err := TryLock("dms-test-b")
	require.NoError(t, err)
	second.Release()
}

func TestTryLockSeparatesWaylandDisplays(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())

	t.Setenv("WAYLAND_DISPLAY", "wayland-1")
	first, err := TryLock(SelectionOverlayLock)
	require.NoError(t, err)
	defer first.Release()

	t.Setenv("WAYLAND_DISPLAY", "wayland-2")
	second, err := TryLock(SelectionOverlayLock)
	require.NoError(t, err)
	second.Release()
}

func TestTryLockWithoutWaylandDisplay(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("WAYLAND_DISPLAY", "")
	os.Unsetenv("WAYLAND_DISPLAY")

	unset, err := TryLock(SelectionOverlayLock)
	require.NoError(t, err)
	assert.Equal(t, fmt.Sprintf("%s-%d-wayland-0.lock", SelectionOverlayLock, os.Getuid()), filepath.Base(lockPath(SelectionOverlayLock)))

	t.Setenv("WAYLAND_DISPLAY", "wayland-1")
	other, err := TryLock(SelectionOverlayLock)
	require.NoError(t, err)
	other.Release()

	os.Unsetenv("WAYLAND_DISPLAY")
	_, err = TryLock(SelectionOverlayLock)
	assert.ErrorIs(t, err, ErrLockHeld)

	unset.Release()
}

func TestDisplayScopeStaysASingleName(t *testing.T) {
	cases := []struct{ display, want string }{
		{"", "wayland-0"},
		{"/", "wayland-0"},
		{"..", "wayland-0"},
		{"wayland-1", "wayland-1"},
		{"/run/user/1000/wayland-2", "wayland-2"},
		{"/run/user/1000/wayland-3/", "wayland-3"},
	}

	for _, tc := range cases {
		t.Setenv("WAYLAND_DISPLAY", tc.display)
		assert.Equal(t, tc.want, displayScope(), tc.display)
	}
}

func TestLockSelectionOverlayReportsHolder(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())

	held, err := LockSelectionOverlay()
	require.NoError(t, err)
	require.NotNil(t, held)
	defer held.Release()

	lock, err := LockSelectionOverlay()
	assert.Nil(t, lock)
	assert.ErrorIs(t, err, ErrOverlayActive)
	assert.Contains(t, err.Error(), fmt.Sprintf("pid %d", os.Getpid()))
}

func TestLockSelectionOverlayFallsBackWhenUnavailable(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", filepath.Join(t.TempDir(), "missing"))

	lock, err := LockSelectionOverlay()
	assert.NoError(t, err)
	assert.Nil(t, lock)
	lock.Release()
}
