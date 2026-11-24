package main

import (
	"bufio"
	"encoding/json"
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

func TestCopyFileContentsSendsAbsolutePath(t *testing.T) {
	got := make(chan string, 1)
	fakeServer(t, func(conn net.Conn) {
		conn.Write([]byte("{}\n"))
		line, _ := bufio.NewReader(conn).ReadBytes('\n')
		var req ipc.Request
		_ = json.Unmarshal(line, &req)
		got <- req.Params["filePath"].(string)
		conn.Write([]byte(`{"id":1,"result":{"success":true}}` + "\n"))
	})

	dir := t.TempDir()
	t.Chdir(dir)
	if err := copyFileContentsToClipboard("shot.png", "image/png"); err != nil {
		t.Fatalf("copyFileContentsToClipboard: %v", err)
	}
	if path := <-got; path != filepath.Join(dir, "shot.png") {
		t.Fatalf("server got %q, want the absolute path", path)
	}
}

// A server that accepts the copy but never answers must not hang the CLI;
// it gives up so the caller can serve the selection itself.
func TestServerCopyGivesUpOnSilentServer(t *testing.T) {
	old := serverCopyReplyTimeout
	serverCopyReplyTimeout = 100 * time.Millisecond
	t.Cleanup(func() { serverCopyReplyTimeout = old })

	fakeServer(t, func(conn net.Conn) {
		conn.Write([]byte("{}\n"))
		bufio.NewReader(conn).ReadBytes('\n')
		time.Sleep(2 * time.Second)
	})

	start := time.Now()
	if serverCopyFileContents("/tmp/shot.png", "image/png") {
		t.Fatal("want the copy refused when the server never answers")
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("took %v, want it to give up after the reply timeout", elapsed)
	}
}
