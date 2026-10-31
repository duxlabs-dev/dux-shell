package network

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
)

func TestSafeOpenConnectMetadataError(t *testing.T) {
	const secret = "DUMMY-SECRET-NOT-FOR-LOGS"
	const busName = "org.freedesktop.NetworkManager.Settings.Connection.VersionIdMismatch"
	for _, tt := range []struct {
		name string
		err  error
		want string
	}{
		{name: "cancelled", err: fmt.Errorf("%s: %w", secret, context.Canceled), want: "context canceled"},
		{name: "timed out", err: context.DeadlineExceeded, want: "context deadline exceeded"},
		{name: "local conflict", err: openConnectMetadataError("OpenConnect profile changed while reading secrets"), want: "OpenConnect profile changed while reading secrets"},
		{name: "D-Bus value body", err: dbus.Error{Name: busName, Body: []any{secret}}, want: busName},
		{name: "wrapped D-Bus pointer body", err: fmt.Errorf("%s: %w", secret, dbus.NewError(busName, []any{secret})), want: busName},
		{name: "invalid error name", err: dbus.NewError(busName+"\n"+secret, nil), want: "unexpected profile response"},
		{name: "unknown error name", err: dbus.NewError(secret, nil), want: "unexpected profile response"},
		{name: "unknown response", err: errors.New(secret), want: "unexpected profile response"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			message := safeOpenConnectMetadataError(tt.err)
			assert.Equal(t, tt.want, message)
			assert.NotContains(t, message, secret)
		})
	}
}
