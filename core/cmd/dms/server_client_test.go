package main

import (
	"bufio"
	"net"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
)

func fakeServer(t *testing.T, handle func(net.Conn)) {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", dir)
	t.Setenv("WAYLAND_DISPLAY", "")

	ln, err := net.Listen("unix", filepath.Join(dir, "danklinux.sock"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				handle(conn)
			}()
		}
	}()
}

func TestServerRequestTimesOutWithoutGreeting(t *testing.T) {
	old := serverHandshakeTimeout
	serverHandshakeTimeout = 100 * time.Millisecond
	t.Cleanup(func() { serverHandshakeTimeout = old })

	fakeServer(t, func(conn net.Conn) { time.Sleep(time.Second) })

	start := time.Now()
	if _, err := sendServerRequest(ipc.Request{Method: "test"}); err == nil {
		t.Fatal("sendServerRequest: expected an error from a silent server")
	}
	if err := sendServerRequestFireAndForget(ipc.Request{Method: "test"}); err == nil {
		t.Fatal("sendServerRequestFireAndForget: expected an error from a silent server")
	}
	if elapsed := time.Since(start); elapsed > 900*time.Millisecond {
		t.Fatalf("requests took %v, want them to give up after the handshake timeout", elapsed)
	}
}

func TestServerRequestWaitsForSlowReply(t *testing.T) {
	old := serverHandshakeTimeout
	serverHandshakeTimeout = 100 * time.Millisecond
	t.Cleanup(func() { serverHandshakeTimeout = old })

	fakeServer(t, func(conn net.Conn) {
		conn.Write([]byte("{}\n"))
		bufio.NewReader(conn).ReadBytes('\n')
		time.Sleep(300 * time.Millisecond)
		conn.Write([]byte(`{"id":1,"result":"ok"}` + "\n"))
	})

	resp, err := sendServerRequest(ipc.Request{ID: 1, Method: "test"})
	if err != nil {
		t.Fatalf("sendServerRequest: %v", err)
	}
	if resp.Result == nil || *resp.Result != "ok" {
		t.Fatalf("unexpected response: %+v", resp)
	}
}

func TestServerRequestReportsClosedConnection(t *testing.T) {
	fakeServer(t, func(conn net.Conn) {})

	_, err := sendServerRequest(ipc.Request{Method: "test"})
	if err == nil || strings.Contains(err.Error(), "%!") {
		t.Fatalf("want a readable error for a server that hangs up, got %v", err)
	}
}
