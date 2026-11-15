package pubsub

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRunDebouncedNotifier_CoalescesAndFiltersUnchanged(t *testing.T) {
	var broker Broker[int]
	ch := broker.Subscribe("client-1")
	defer broker.Unsubscribe("client-1", ch)

	stop := make(chan struct{})
	dirty := make(chan struct{}, 1)
	var val atomic.Int32
	val.Store(1)

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		RunDebouncedNotifier(DebouncedConfig[int]{
			MinGap:   20 * time.Millisecond,
			Stop:     stop,
			Dirty:    dirty,
			Snapshot: func() int { return int(val.Load()) },
			Changed:  func(prev, cur *int) bool { return *prev != *cur },
			Broker:   &broker,
		})
	}()

	// Burst of dirty signals should coalesce into a single notification.
	for range 3 {
		select {
		case dirty <- struct{}{}:
		default:
		}
	}

	select {
	case got := <-ch:
		assert.Equal(t, 1, got)
	case <-time.After(200 * time.Millisecond):
		require.Fail(t, "timed out waiting for first notification")
	}

	// Dirty with unchanged state should not publish.
	dirty <- struct{}{}
	select {
	case got := <-ch:
		require.Failf(t, "unexpected notification for unchanged state", "got %d", got)
	case <-time.After(60 * time.Millisecond):
	}

	// Dirty with changed state should publish.
	val.Store(2)
	dirty <- struct{}{}
	select {
	case got := <-ch:
		assert.Equal(t, 2, got)
	case <-time.After(200 * time.Millisecond):
		require.Fail(t, "timed out waiting for changed notification")
	}

	close(stop)
	wg.Wait()
}
