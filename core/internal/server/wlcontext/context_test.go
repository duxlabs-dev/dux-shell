package wlcontext

import (
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"golang.org/x/sys/unix"
)

func newTestSharedContext(t *testing.T, queueSize int) *SharedContext {
	t.Helper()
	fds := make([]int, 2)
	if err := unix.Pipe(fds); err != nil {
		t.Fatalf("failed to create test pipe: %v", err)
	}
	t.Cleanup(func() {
		unix.Close(fds[0])
		unix.Close(fds[1])
	})
	return &SharedContext{
		cmdQueue: make(chan func(), queueSize),
		stopChan: make(chan struct{}),
		wakeR:    fds[0],
		wakeW:    fds[1],
	}
}

func TestSharedContext_PostQueueFull(t *testing.T) {
	sc := newTestSharedContext(t, 2)

	sc.Post(func() {})
	sc.Post(func() {})
	sc.Post(func() {})
	sc.Post(func() {})

	assert.Len(t, sc.cmdQueue, 2)
}

func TestSharedContext_DrainCmdQueue(t *testing.T) {
	sc := newTestSharedContext(t, 256)

	counter := 0
	for range 10 {
		sc.cmdQueue <- func() {
			counter++
		}
	}

	sc.drainCmdQueue()

	assert.Equal(t, 10, counter)
	assert.Len(t, sc.cmdQueue, 0)
}

func TestSharedContext_ConcurrentDrainAndPost(t *testing.T) {
	sc := newTestSharedContext(t, 256)

	var wg sync.WaitGroup

	wg.Go(func() {
		for range 100 {
			sc.Post(func() {})
		}
	})

	wg.Go(func() {
		for range 50 {
			sc.drainCmdQueue()
		}
	})

	wg.Wait()
}
