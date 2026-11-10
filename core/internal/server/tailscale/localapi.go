package tailscale

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"

	"tailscale.com/ipn/ipnstate"
)

// Wire format mirrors tailscale.com/client/local v1.104.1: plain HTTP over the
// tailscaled unix socket, host fixed to local-tailscaled.sock.
const (
	localAPIHost      = "local-tailscaled.sock"
	defaultSocketPath = "/var/run/tailscale/tailscaled.sock"
)

// watchOpt bits are ipn.NotifyWatchOpt values, serialized to the network.
type watchOpt uint64

const (
	notifyInitialState watchOpt = 1 << 1
	notifyInitialPrefs watchOpt = 1 << 2
	notifyPeerChanges  watchOpt = 1 << 12
	notifyPeerPatches  watchOpt = 1 << 15
)

type prefs struct {
	ExitNodeAllowLANAccess bool
}

// maskedPrefs is the slice of ipn.MaskedPrefs this service edits. The *Set
// flags tell tailscaled which fields the PATCH carries.
type maskedPrefs struct {
	WantRunning               bool   `json:",omitempty"`
	WantRunningSet            bool   `json:",omitempty"`
	ExitNodeID                string `json:",omitempty"`
	ExitNodeIDSet             bool   `json:",omitempty"`
	ExitNodeIPSet             bool   `json:",omitempty"`
	ExitNodeAllowLANAccess    bool   `json:",omitempty"`
	ExitNodeAllowLANAccessSet bool   `json:",omitempty"`
}

type localClient struct {
	http *http.Client
}

func newLocalClient(socketPath string) *localClient {
	if socketPath == "" {
		socketPath = defaultSocketPath
	}
	dial := func(ctx context.Context, _, _ string) (net.Conn, error) {
		var d net.Dialer
		return d.DialContext(ctx, "unix", socketPath)
	}
	return &localClient{http: &http.Client{Transport: &http.Transport{DialContext: dial}}}
}

func (c *localClient) Status(ctx context.Context) (*ipnstate.Status, error) {
	var status ipnstate.Status
	if err := c.getJSON(ctx, "/localapi/v0/status", &status); err != nil {
		return nil, err
	}
	return &status, nil
}

func (c *localClient) GetPrefs(ctx context.Context) (*prefs, error) {
	var p prefs
	if err := c.getJSON(ctx, "/localapi/v0/prefs", &p); err != nil {
		return nil, err
	}
	return &p, nil
}

func (c *localClient) EditPrefs(ctx context.Context, mp *maskedPrefs) error {
	body, err := json.Marshal(mp)
	if err != nil {
		return err
	}
	res, err := c.do(ctx, http.MethodPatch, "/localapi/v0/prefs", body)
	if err != nil {
		return err
	}
	return res.Body.Close()
}

func (c *localClient) WatchIPNBus(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
	path := "/localapi/v0/watch-ipn-bus?mask=" + strconv.FormatUint(uint64(mask), 10)
	res, err := c.do(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	return &busWatcher{body: res.Body, dec: json.NewDecoder(res.Body)}, nil
}

func (c *localClient) getJSON(ctx context.Context, path string, v any) error {
	res, err := c.do(ctx, http.MethodGet, path, nil)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	return json.NewDecoder(res.Body).Decode(v)
}

func (c *localClient) do(ctx context.Context, method, path string, body []byte) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, method, "http://"+localAPIHost+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	res, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	if res.StatusCode == http.StatusOK {
		return res, nil
	}
	defer res.Body.Close()
	msg, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	return nil, fmt.Errorf("%s: %s", res.Status, errorMessage(msg))
}

func errorMessage(body []byte) string {
	var j struct{ Error string }
	if err := json.Unmarshal(body, &j); err == nil && j.Error != "" {
		return j.Error
	}
	return strings.TrimSpace(string(body))
}

// busWatcher streams IPN bus notifications. The payloads are discarded: the
// manager only uses arrivals as a hint to refetch status.
type busWatcher struct {
	body io.ReadCloser
	dec  *json.Decoder
}

func (w *busWatcher) Next() error {
	var discard struct{}
	return w.dec.Decode(&discard)
}

func (w *busWatcher) Close() error {
	return w.body.Close()
}
