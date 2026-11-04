package niriconf

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

const initialState = `{"Ok":"Handled"}
{"WorkspacesChanged":{"workspaces":[]}}
{"ConfigLoaded":{"failed":false}}
`

// fakeNiri serves one event stream; the returned channel closes once the
// client has closed its side, so a leaked connection fails the test.
func fakeNiri(t *testing.T, lines string) (string, <-chan struct{}) {
	t.Helper()
	socket := filepath.Join(t.TempDir(), "niri.sock")
	ln, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		defer ln.Close()
		conn, err := ln.Accept()
		if err != nil {
			t.Error(err)
			return
		}
		defer conn.Close()
		request, err := bufio.NewReader(conn).ReadString('\n')
		if err != nil || request != "\"EventStream\"\n" {
			t.Errorf("request %q, %v", request, err)
			return
		}
		if _, err := io.WriteString(conn, lines); err != nil {
			t.Error(err)
			return
		}
		_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
		if _, err := io.Copy(io.Discard, conn); err != nil {
			t.Errorf("client kept the connection open: %v", err)
		}
	}()
	return socket, done
}

func TestSocketEventsParsesConfigLoaded(t *testing.T) {
	cases := []struct {
		name       string
		events     string
		timeout    time.Duration
		wantFailed bool
		wantErr    error
	}{
		{"failed", `{"WindowFocusChanged":{"id":3}}` + "\n" + `{"ConfigLoaded":{"failed":true}}` + "\n", time.Second, true, nil},
		{"loaded", `{"WindowFocusChanged":{"id":3}}` + "\n" + `{"ConfigLoaded":{"failed":false}}` + "\n", time.Second, false, nil},
		{"timeout", `{"WindowFocusChanged":{"id":3}}` + "\n", 50 * time.Millisecond, false, os.ErrDeadlineExceeded},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			socket, done := fakeNiri(t, initialState+tc.events)
			w, err := SocketEvents{Socket: socket}.Subscribe()
			if err != nil {
				t.Fatal(err)
			}
			failed, err := w.Wait(tc.timeout)
			if failed != tc.wantFailed || !errors.Is(err, tc.wantErr) {
				t.Errorf("Wait = %v, %v; want %v, %v", failed, err, tc.wantFailed, tc.wantErr)
			}
			<-done
			if err := w.Close(); err != nil {
				t.Errorf("Close after Wait: %v", err)
			}
		})
	}
}

func TestSocketEventsCloseWithoutWait(t *testing.T) {
	socket, done := fakeNiri(t, initialState)
	w, err := SocketEvents{Socket: socket}.Subscribe()
	if err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	<-done
}

type fakeEvents struct {
	t         *testing.T
	path      string
	failed    bool
	waitErr   error
	subErr    error
	subscribe int
	closed    bool
}

func (e *fakeEvents) Subscribe() (Waiter, error) {
	e.subscribe++
	if e.subErr != nil {
		return nil, e.subErr
	}
	if got, _ := os.ReadFile(e.path); string(got) != "old\n" {
		e.t.Errorf("subscribed after the write: %q", got)
	}
	return e, nil
}

func (e *fakeEvents) Wait(time.Duration) (bool, error) { return e.failed, e.waitErr }

func (e *fakeEvents) Close() error {
	e.closed = true
	return nil
}

func storeWithEvents(t *testing.T, ev *fakeEvents) *Store {
	t.Helper()
	s := newStore(t)
	mustApply(t, s, "old\n")
	ev.t, ev.path = t, s.path("niri.kdl")
	s.Events = ev
	return s
}

func TestApplyRollsBackWhenReloadFails(t *testing.T) {
	ev := &fakeEvents{failed: true}
	s := storeWithEvents(t, ev)
	_, hash, _ := s.Read("niri.kdl")

	v, err := s.Apply("niri.kdl", "new\n", hash)
	if !errors.Is(err, ErrReloadFailed) {
		t.Fatalf("want ErrReloadFailed, got %v", err)
	}
	if !ev.closed {
		t.Fatal("waiter not closed")
	}
	if got := readFragment(t, s); got != "old\n" {
		t.Fatalf("file %q", got)
	}
	h, _ := s.History("niri.kdl")
	if len(h) != 2 || h[0] != v || !v.Failed || h[1].Failed {
		t.Fatalf("history %v, returned %v", h, v)
	}
	if got := historyContent(t, s, v.N); got != "new\n" {
		t.Fatalf("failed attempt %q", got)
	}
}

// A broken stream or socket keeps the content: niri validated it already.
func TestApplyKeepsWhenReloadOK(t *testing.T) {
	cases := map[string]*fakeEvents{
		"loaded":         {},
		"stream closed":  {waitErr: errors.New("niri event stream closed")},
		"no niri socket": {subErr: errors.New("connect niri socket: refused")},
	}
	for name, ev := range cases {
		t.Run(name, func(t *testing.T) {
			s := storeWithEvents(t, ev)
			_, hash, _ := s.Read("niri.kdl")

			v, err := s.Apply("niri.kdl", "new\n", hash)
			if err != nil || v.Failed {
				t.Fatalf("got %v, %v", v, err)
			}
			if got := readFragment(t, s); got != "new\n" {
				t.Fatalf("file %q", got)
			}
			if ev.subscribe != 1 || ev.closed != (ev.subErr == nil) {
				t.Fatalf("subscribed %d, closed %v", ev.subscribe, ev.closed)
			}
		})
	}
}

// niri does not reload when the merged config is identical.
func TestApplyTimeoutKeeps(t *testing.T) {
	s := storeWithEvents(t, &fakeEvents{waitErr: fmt.Errorf("read: %w", os.ErrDeadlineExceeded)})
	_, hash, _ := s.Read("niri.kdl")
	if _, err := s.Apply("niri.kdl", "new\n", hash); err != nil {
		t.Fatal(err)
	}
	if got := readFragment(t, s); got != "new\n" {
		t.Fatalf("file %q", got)
	}
}

func TestApplyInvalidSkipsWatch(t *testing.T) {
	ev := &fakeEvents{}
	s := storeWithEvents(t, ev)
	_, hash, _ := s.Read("niri.kdl")
	if _, err := s.Apply("niri.kdl", "BAD\n", hash); err == nil {
		t.Fatal("want an error")
	}
	if ev.subscribe != 0 {
		t.Fatal("subscribed for a refused config")
	}
}
