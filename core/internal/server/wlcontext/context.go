package wlcontext

import (
	"fmt"
	"golang.org/x/sys/unix"
	"os"
	"sync"
	"time"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

type WaylandContext interface {
	Display() *wlclient.Display
	Post(fn func())
	FatalError() <-chan error
	Start()
	Close()
}

var _ WaylandContext = (*SharedContext)(nil)

type SharedContext struct {
	display    *wlclient.Display
	stopChan   chan struct{}
	fatalError chan error
	cmdQueue   chan func()
	wakeR      int
	wakeW      int
	wg         sync.WaitGroup
	mu         sync.Mutex
	started    bool
}

func New() (*SharedContext, error) {
	display, err := wlclient.Connect("")
	if err != nil {
		return nil, fmt.Errorf("%w: %v", errdefs.ErrNoWaylandDisplay, err)
	}

	fds := make([]int, 2)
	if err := unix.Pipe(fds); err != nil {
		display.Context().Close()
		return nil, fmt.Errorf("failed to create wake pipe: %w", err)
	}
	if err := unix.SetNonblock(fds[0], true); err != nil {
		unix.Close(fds[0])
		unix.Close(fds[1])
		display.Context().Close()
		return nil, fmt.Errorf("failed to set wake pipe nonblock: %w", err)
	}
	if err := unix.SetNonblock(fds[1], true); err != nil {
		unix.Close(fds[0])
		unix.Close(fds[1])
		display.Context().Close()
		return nil, fmt.Errorf("failed to set wake pipe nonblock: %w", err)
	}

	sc := &SharedContext{
		display:    display,
		stopChan:   make(chan struct{}),
		fatalError: make(chan error, 1),
		cmdQueue:   make(chan func(), 256),
		wakeR:      fds[0],
		wakeW:      fds[1],
		started:    false,
	}

	return sc, nil
}

func (sc *SharedContext) Start() {
	sc.mu.Lock()
	defer sc.mu.Unlock()

	if sc.started {
		return
	}

	sc.started = true
	sc.wg.Add(1)
	go sc.eventDispatcher()
}

func (sc *SharedContext) Display() *wlclient.Display {
	return sc.display
}

func (sc *SharedContext) Post(fn func()) {
	select {
	case sc.cmdQueue <- fn:
		if _, err := unix.Write(sc.wakeW, []byte{1}); err != nil && err != unix.EAGAIN {
			log.Errorf("wake pipe write error: %v", err)
		}
	default:
	}
}

func (sc *SharedContext) FatalError() <-chan error {
	return sc.fatalError
}

func (sc *SharedContext) eventDispatcher() {
	defer sc.wg.Done()
	defer func() {
		if r := recover(); r != nil {
			err := fmt.Errorf("FATAL: Wayland event dispatcher panic: %v", r)
			log.Error(err)
			sc.signalFatal(err)
		}
	}()

	ctx := sc.display.Context()
	wlFd := ctx.Fd()

	pollFds := []unix.PollFd{
		{Fd: int32(wlFd), Events: unix.POLLIN},
		{Fd: int32(sc.wakeR), Events: unix.POLLIN},
	}

	consecutiveErrors := 0
	const maxConsecutiveErrors = 20

	for {
		sc.drainCmdQueue()

		select {
		case <-sc.stopChan:
			return
		default:
		}

		_, err := unix.Poll(pollFds, -1)
		switch {
		case err == unix.EINTR:
			continue
		case err != nil:
			log.Errorf("Poll error: %v", err)
			sc.signalFatal(fmt.Errorf("wayland poll error: %w", err))
			return
		}

		if pollFds[1].Revents&unix.POLLIN != 0 {
			var buf [64]byte
			if _, err := unix.Read(sc.wakeR, buf[:]); err != nil && err != unix.EAGAIN {
				log.Errorf("wake pipe read error: %v", err)
			}
		}

		if pollFds[0].Revents&unix.POLLIN == 0 {
			continue
		}

		if err := ctx.Dispatch(); err != nil && !os.IsTimeout(err) {
			consecutiveErrors++
			log.Warnf("Wayland connection error (%d/%d): %v", consecutiveErrors, maxConsecutiveErrors, err)

			if consecutiveErrors >= maxConsecutiveErrors {
				log.Errorf("Fatal: Wayland connection unrecoverable after %d attempts. Exiting dispatcher.", maxConsecutiveErrors)
				sc.signalFatal(fmt.Errorf("wayland connection unrecoverable after %d dispatch failures: %w", maxConsecutiveErrors, err))
				return
			}

			time.Sleep(100 * time.Millisecond * time.Duration(consecutiveErrors))
			continue
		}

		consecutiveErrors = 0
	}
}

func (sc *SharedContext) signalFatal(err error) {
	select {
	case sc.fatalError <- err:
	default:
	}
}

func (sc *SharedContext) drainCmdQueue() {
	for {
		select {
		case fn := <-sc.cmdQueue:
			fn()
		default:
			return
		}
	}
}

func (sc *SharedContext) Close() {
	close(sc.stopChan)
	if _, err := unix.Write(sc.wakeW, []byte{1}); err != nil && err != unix.EAGAIN {
		log.Errorf("wake pipe write error on close: %v", err)
	}
	sc.wg.Wait()

	unix.Close(sc.wakeR)
	unix.Close(sc.wakeW)

	if sc.display == nil {
		return
	}
	sc.display.Context().Close()
}
