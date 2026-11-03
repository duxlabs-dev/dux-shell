package systemd

import (
	"context"
	"errors"
	"testing"
	"testing/synctest"
	"time"

	"github.com/stretchr/testify/require"
)

func TestReadinessBackoffAndSuccess(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		r := NewReadiness()
		r.ShellReady(42)
		start := time.Now()
		var checks []time.Duration
		err := r.wait(context.Background(), time.Minute, func(_ context.Context, pid uint32) (bool, error) {
			require.Equal(t, uint32(42), pid)
			checks = append(checks, time.Since(start))
			if len(checks) == 1 {
				return false, errors.New("temporary bus failure")
			}
			if len(checks) == 2 {
				return false, &BusNameConflictError{Name: "tray host", OwnerPID: 43}
			}
			return len(checks) == 11, nil
		})
		require.NoError(t, err)
		for i, ms := range []int{20, 40, 80, 160, 320, 640, 1280, 2560, 5120, 10120, 15120} {
			require.Equal(t, time.Duration(ms)*time.Millisecond, checks[i])
		}
		time.Sleep(time.Minute)
		require.Len(t, checks, 11)
	})
}

func TestReadinessDeadlineBeforeUI(t *testing.T) {
	for _, timeout := range []time.Duration{0, 150 * time.Millisecond, 30 * time.Second, 3 * time.Minute} {
		t.Run(timeout.String(), func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				start := time.Now()
				err := NewReadiness().wait(context.Background(), timeout, func(context.Context, uint32) (bool, error) {
					t.Fatal("must not check services before the UI is loaded")
					return false, nil
				})
				require.ErrorIs(t, err, ErrReadinessTimeout)
				require.Equal(t, timeout, time.Since(start))
			})
		})
	}
}

func TestReadinessLateAndDuplicateUIKeepDeadline(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		r := NewReadiness()
		start := time.Now()
		go func() {
			time.Sleep(50 * time.Second)
			r.ShellReady(42)
			time.Sleep(9 * time.Second)
			r.ShellReady(43)
		}()
		err := r.wait(context.Background(), time.Minute, func(_ context.Context, pid uint32) (bool, error) {
			require.Equal(t, uint32(42), pid)
			return false, nil
		})
		require.ErrorIs(t, err, ErrReadinessTimeout)
		require.Equal(t, time.Minute, time.Since(start))
	})
}

func TestReadinessDeadlineDuringCheck(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		r := NewReadiness()
		r.ShellReady(42)
		start := time.Now()
		err := r.wait(context.Background(), time.Minute, func(ctx context.Context, _ uint32) (bool, error) {
			<-ctx.Done()
			return true, nil
		})
		require.ErrorIs(t, err, ErrReadinessTimeout)
		require.Equal(t, time.Minute, time.Since(start))
	})
}

func TestReadinessCancellation(t *testing.T) {
	for _, uiReady := range []bool{false, true} {
		synctest.Test(t, func(t *testing.T) {
			r := NewReadiness()
			if uiReady {
				r.ShellReady(42)
			}
			ctx, cancel := context.WithCancel(context.Background())
			go func() {
				time.Sleep(time.Second)
				cancel()
			}()
			start := time.Now()
			err := r.wait(ctx, time.Minute, func(context.Context, uint32) (bool, error) { return false, nil })
			require.NoError(t, err)
			require.Equal(t, time.Second, time.Since(start))
		})
	}
}
