package niriconf

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"time"
)

var ErrReloadFailed = errors.New("niri could not load the new config, the previous version is back")

const subscribeTimeout = 2 * time.Second

type Events interface {
	Subscribe() (Waiter, error)
}

// Waiter is single use: Wait closes the connection when it returns.
// A timeout returns an error matching os.ErrDeadlineExceeded.
type Waiter interface {
	Wait(timeout time.Duration) (failed bool, err error)
	Close() error
}

type SocketEvents struct {
	Socket string
}

type socketWaiter struct {
	conn    net.Conn
	scanner *bufio.Scanner
}

func (e SocketEvents) Subscribe() (Waiter, error) {
	conn, err := net.DialTimeout("unix", e.Socket, subscribeTimeout)
	if err != nil {
		return nil, fmt.Errorf("connect niri socket: %w", err)
	}
	_ = conn.SetDeadline(time.Now().Add(subscribeTimeout))

	if _, err := conn.Write([]byte("\"EventStream\"\n")); err != nil {
		conn.Close()
		return nil, fmt.Errorf("subscribe niri events: %w", err)
	}

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 0, 64<<10), 1<<20)
	w := &socketWaiter{conn: conn, scanner: scanner}

	// niri opens the stream with a replica of its state, including the
	// current ConfigLoaded: skip it so Wait only sees the next reload.
	if _, err := w.next(); err != nil {
		conn.Close()
		return nil, fmt.Errorf("read niri initial state: %w", err)
	}
	return w, nil
}

func (w *socketWaiter) Wait(timeout time.Duration) (bool, error) {
	defer w.Close()
	_ = w.conn.SetReadDeadline(time.Now().Add(timeout))
	return w.next()
}

func (w *socketWaiter) Close() error {
	if err := w.conn.Close(); err != nil && !errors.Is(err, net.ErrClosed) {
		return err
	}
	return nil
}

func (w *socketWaiter) next() (bool, error) {
	for w.scanner.Scan() {
		var event struct {
			ConfigLoaded *struct {
				Failed bool `json:"failed"`
			} `json:"ConfigLoaded"`
		}
		if json.Unmarshal(w.scanner.Bytes(), &event) != nil {
			continue
		}
		if event.ConfigLoaded != nil {
			return event.ConfigLoaded.Failed, nil
		}
	}
	if err := w.scanner.Err(); err != nil {
		return false, err
	}
	return false, errors.New("niri event stream closed")
}
