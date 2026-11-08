package tailscale

import (
	"context"
	"net/netip"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"tailscale.com/ipn/ipnstate"
)

func TestE2E_TailscaleWithoutOperatorThenGrant(t *testing.T) {
	var permitted atomic.Bool
	denied := errAccessDenied
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		profileStatusFn: func(ctx context.Context) (loginProfile, []loginProfile, error) {
			if !permitted.Load() {
				return loginProfile{}, nil, denied
			}
			return loginProfile{ID: "p1"}, []loginProfile{{ID: "p1", Name: "me@example.com"}}, nil
		},
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error {
			if !permitted.Load() {
				return denied
			}
			return nil
		},
	}
	var ran [][]string
	fakeOperatorEnv(t, map[string]string{"pkexec": "/usr/bin/pkexec", "tailscale": "/usr/bin/tailscale"},
		func(ctx context.Context, argv []string) ([]byte, int, error) {
			ran = append(ran, argv)
			permitted.Store(true)
			return nil, 0, nil
		})
	m := newManager(client)
	defer m.Close()

	resp := callHandler[ProfilesResult](t, m, "tailscale.profiles", nil)
	require.Empty(t, resp.Error)
	assert.False(t, resp.Result.CanOperate)
	assert.True(t, resp.Result.GrantAvailable)

	set := callHandler[map[string]any](t, m, "tailscale.setPrefs", map[string]any{"acceptRoutes": true})
	assert.Contains(t, strings.ToLower(set.Error), "access denied")
	assert.Empty(t, ran)

	grant := callHandler[ProfilesResult](t, m, "tailscale.grantOperator", nil)
	require.Empty(t, grant.Error)
	assert.Equal(t, [][]string{{"/usr/bin/pkexec", "/usr/bin/tailscale", "set", "--operator=tester"}}, ran)
	assert.True(t, grant.Result.CanOperate)
	assert.Equal(t, "p1", grant.Result.Current)
}

func TestE2E_TailscaleAdvertiseExitNode(t *testing.T) {
	existing := netip.MustParsePrefix("192.168.1.0/24")
	routes := []netip.Prefix{existing}
	var edited *maskedPrefs
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		getPrefsFn: func(ctx context.Context) (*prefs, error) {
			return &prefs{AdvertiseRoutes: routes}, nil
		},
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error {
			edited = mp
			routes = mp.AdvertiseRoutes
			return nil
		},
	}
	m := newManager(client)
	defer m.Close()

	resp := callHandler[map[string]any](t, m, "tailscale.setPrefs", map[string]any{"advertiseExitNode": true})
	require.Empty(t, resp.Error)
	require.NotNil(t, edited)
	assert.True(t, edited.AdvertiseRoutesSet)
	assert.ElementsMatch(t, []netip.Prefix{existing, netip.MustParsePrefix("0.0.0.0/0"), netip.MustParsePrefix("::/0")}, edited.AdvertiseRoutes)

	status := callHandler[TailscaleState](t, m, "tailscale.getStatus", nil)
	require.Empty(t, status.Error)
	assert.True(t, status.Result.Prefs.AdvertiseExitNode)
	assert.Equal(t, []string{"192.168.1.0/24"}, status.Result.Prefs.AdvertiseRoutes)
}
