package netfetch

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const DefaultUserAgent = "DuxShell/1.0 (Linux)"

type Options struct {
	Headers        map[string]string
	UserAgent      string
	Timeout        time.Duration
	ConnectTimeout time.Duration
	IPv4Only       bool
	CheckRedirect  func(req *http.Request, via []*http.Request) error
	// 0 = unlimited; only BytesConditional honours it.
	MaxBytes int64
}

type StatusError struct {
	Code int
}

func (e *StatusError) Error() string {
	return fmt.Sprintf("HTTP %d", e.Code)
}

type transportKey struct {
	connect  time.Duration
	ipv4Only bool
}

var (
	transportMu sync.Mutex
	transports  = map[transportKey]*http.Transport{}
)

func (o Options) client() *http.Client {
	return &http.Client{Transport: transportFor(o), CheckRedirect: o.CheckRedirect}
}

// A hand-built transport has no IdleConnTimeout, so a per-request one leaks its idle connections.
func transportFor(o Options) *http.Transport {
	connect := o.ConnectTimeout
	if connect <= 0 {
		connect = 5 * time.Second
	}
	key := transportKey{connect: connect, ipv4Only: o.IPv4Only}

	transportMu.Lock()
	defer transportMu.Unlock()

	if transport, ok := transports[key]; ok {
		return transport
	}

	dialer := &net.Dialer{Timeout: connect}
	transport := &http.Transport{
		Proxy:               http.ProxyFromEnvironment,
		DialContext:         dialer.DialContext,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: 10 * time.Second,
	}
	if o.IPv4Only {
		transport.DialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
			return dialer.DialContext(ctx, "tcp4", addr)
		}
	}
	transports[key] = transport
	return transport
}

func (o Options) request(ctx context.Context, url string) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("invalid request: %w", err)
	}

	agent := o.UserAgent
	if agent == "" {
		agent = DefaultUserAgent
	}
	req.Header.Set("User-Agent", agent)

	for name, value := range o.Headers {
		req.Header.Set(name, value)
	}
	return req, nil
}

// Closing the body is what cancels the timeout context.
func Open(ctx context.Context, url string, opts Options) (io.ReadCloser, error) {
	if opts.Timeout <= 0 {
		return open(ctx, url, opts)
	}

	ctx, cancel := context.WithTimeout(ctx, opts.Timeout)
	body, err := open(ctx, url, opts)
	if err != nil {
		cancel()
		return nil, err
	}
	return &cancelOnClose{ReadCloser: body, cancel: cancel}, nil
}

type cancelOnClose struct {
	io.ReadCloser
	cancel context.CancelFunc
}

func (c *cancelOnClose) Close() error {
	err := c.ReadCloser.Close()
	c.cancel()
	return err
}

func open(ctx context.Context, url string, opts Options) (io.ReadCloser, error) {
	req, err := opts.request(ctx, url)
	if err != nil {
		return nil, err
	}

	resp, err := opts.client().Do(req)
	if err != nil {
		return nil, fmt.Errorf("download failed: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		resp.Body.Close()
		return nil, &StatusError{Code: resp.StatusCode}
	}
	return resp.Body, nil
}

func Bytes(ctx context.Context, url string, opts Options) ([]byte, error) {
	body, err := Open(ctx, url, opts)
	if err != nil {
		return nil, err
	}
	defer body.Close()
	return io.ReadAll(body)
}

func ToWriter(ctx context.Context, url string, opts Options, w io.Writer) error {
	body, err := Open(ctx, url, opts)
	if err != nil {
		return err
	}
	defer body.Close()

	_, err = io.Copy(w, body)
	return err
}

func ToFile(ctx context.Context, url string, opts Options, path string) error {
	if dir := filepath.Dir(path); dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("mkdir failed: %w", err)
		}
	}

	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("create failed: %w", err)
	}
	defer f.Close()

	if err := ToWriter(ctx, url, opts, f); err != nil {
		os.Remove(path)
		return err
	}
	return nil
}

type Conditional struct {
	Body        []byte
	ETag        string
	NotModified bool
}

func BytesConditional(ctx context.Context, url, etag string, opts Options) (Conditional, error) {
	if opts.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, opts.Timeout)
		defer cancel()
	}
	req, err := opts.request(ctx, url)
	if err != nil {
		return Conditional{}, err
	}
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}
	resp, err := opts.client().Do(req)
	if err != nil {
		return Conditional{}, fmt.Errorf("download failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotModified {
		return Conditional{ETag: etag, NotModified: true}, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return Conditional{}, &StatusError{Code: resp.StatusCode}
	}
	var r io.Reader = resp.Body
	if opts.MaxBytes > 0 {
		r = io.LimitReader(resp.Body, opts.MaxBytes+1)
	}
	body, err := io.ReadAll(r)
	if err != nil {
		return Conditional{}, err
	}
	if opts.MaxBytes > 0 && int64(len(body)) > opts.MaxBytes {
		return Conditional{}, fmt.Errorf("response exceeds %d bytes", opts.MaxBytes)
	}
	return Conditional{Body: body, ETag: resp.Header.Get("ETag")}, nil
}
