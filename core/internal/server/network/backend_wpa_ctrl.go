package network

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	wpaCtrlRequestTimeout = 5 * time.Second
	wpaCtrlReadBufferSize = 65536
)

// Client side of the wpa_ctrl protocol: a unix datagram socket bound to a
// local path, connected to wpa_supplicant's per-interface socket. See
// https://w1.fi/wpa_supplicant/devel/ctrl_iface_page.html
type wpaCtrlConn struct {
	sockPath string
	localDir string
	mu       sync.Mutex
	conn     *net.UnixConn
	seq      int
}

func newWpaCtrlConn(sockPath string) (*wpaCtrlConn, error) {
	localDir, err := os.MkdirTemp(utils.RuntimeDir(), "dms-wpa-")
	if err != nil {
		return nil, fmt.Errorf("create wpa_ctrl socket dir: %w", err)
	}

	c := &wpaCtrlConn{sockPath: sockPath, localDir: localDir}
	if err := c.dialLocked(); err != nil {
		os.RemoveAll(localDir)
		return nil, err
	}

	return c, nil
}

func (c *wpaCtrlConn) dialLocked() error {
	c.seq++
	localPath := filepath.Join(c.localDir, fmt.Sprintf("ctrl_%d", c.seq))
	os.Remove(localPath)

	conn, err := net.DialUnix("unixgram",
		&net.UnixAddr{Name: localPath, Net: "unixgram"},
		&net.UnixAddr{Name: c.sockPath, Net: "unixgram"})
	if err != nil {
		return fmt.Errorf("dial %s: %w", c.sockPath, err)
	}

	if c.conn != nil {
		c.conn.Close()
	}
	c.conn = conn
	return nil
}

func (c *wpaCtrlConn) reconnectLocked() error {
	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
	}
	return c.dialLocked()
}

func (c *wpaCtrlConn) reconnect() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.reconnectLocked()
}

// request sends a command and waits for its reply, retrying once on a fresh
// socket so a wpa_supplicant restart between requests is transparent.
func (c *wpaCtrlConn) request(cmd string) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	reply, err := c.roundTripLocked(cmd)
	if err == nil {
		return reply, nil
	}

	if rerr := c.reconnectLocked(); rerr != nil {
		return "", err
	}
	return c.roundTripLocked(cmd)
}

func (c *wpaCtrlConn) roundTripLocked(cmd string) (string, error) {
	if c.conn == nil {
		if err := c.dialLocked(); err != nil {
			return "", err
		}
	}

	_ = c.conn.SetDeadline(time.Now().Add(wpaCtrlRequestTimeout))
	if _, err := c.conn.Write([]byte(cmd)); err != nil {
		return "", fmt.Errorf("write %q: %w", cmd, err)
	}

	buf := make([]byte, wpaCtrlReadBufferSize)
	for {
		n, err := c.conn.Read(buf)
		if err != nil {
			return "", fmt.Errorf("read reply for %q: %w", cmd, err)
		}
		// Unsolicited event datagrams carry a "<priority>" prefix, command
		// replies never do (ctrl_iface_page.html, "Control interface data").
		if n > 0 && buf[0] == '<' {
			continue
		}
		return strings.TrimRight(string(buf[:n]), "\n"), nil
	}
}

func (c *wpaCtrlConn) send(cmd string) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn == nil {
		if err := c.dialLocked(); err != nil {
			return err
		}
	}

	_ = c.conn.SetWriteDeadline(time.Now().Add(wpaCtrlRequestTimeout))
	if _, err := c.conn.Write([]byte(cmd)); err != nil {
		return fmt.Errorf("write %q: %w", cmd, err)
	}
	return nil
}

func (c *wpaCtrlConn) readDatagram(timeout time.Duration) (string, error) {
	c.mu.Lock()
	conn := c.conn
	c.mu.Unlock()

	if conn == nil {
		return "", fmt.Errorf("wpa_ctrl socket closed")
	}

	_ = conn.SetReadDeadline(time.Now().Add(timeout))
	buf := make([]byte, wpaCtrlReadBufferSize)
	n, err := conn.Read(buf)
	if err != nil {
		return "", err
	}
	return strings.TrimRight(string(buf[:n]), "\n"), nil
}

func (c *wpaCtrlConn) attach() error {
	reply, err := c.request("ATTACH")
	if err != nil {
		return err
	}
	if reply != "OK" {
		return fmt.Errorf("ATTACH failed: %s", reply)
	}
	return nil
}

func (c *wpaCtrlConn) close() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
	}
	os.RemoveAll(c.localDir)
}

func isWpaCtrlTimeout(err error) bool {
	netErr, ok := err.(net.Error)
	return ok && netErr.Timeout()
}
