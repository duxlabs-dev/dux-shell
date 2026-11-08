package tailscale

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
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

// tailscaled's ipn.State value for a running backend.
const ipnStateRunning = 6

var errAccessDenied = errors.New("access denied")

type prefs struct {
	ExitNodeAllowLANAccess bool
	RouteAll               bool
	CorpDNS                bool
	ShieldsUp              bool
	RunSSH                 bool
	Hostname               string
	AdvertiseRoutes        []netip.Prefix
}

// maskedPrefs is the slice of ipn.MaskedPrefs this service edits. The *Set
// flags tell tailscaled which fields the PATCH carries.
type maskedPrefs struct {
	WantRunning               bool           `json:",omitempty"`
	WantRunningSet            bool           `json:",omitempty"`
	ExitNodeID                string         `json:",omitempty"`
	ExitNodeIDSet             bool           `json:",omitempty"`
	ExitNodeIPSet             bool           `json:",omitempty"`
	ExitNodeAllowLANAccess    bool           `json:",omitempty"`
	ExitNodeAllowLANAccessSet bool           `json:",omitempty"`
	RouteAll                  bool           `json:",omitempty"`
	RouteAllSet               bool           `json:",omitempty"`
	CorpDNS                   bool           `json:",omitempty"`
	CorpDNSSet                bool           `json:",omitempty"`
	ShieldsUp                 bool           `json:",omitempty"`
	ShieldsUpSet              bool           `json:",omitempty"`
	RunSSH                    bool           `json:",omitempty"`
	RunSSHSet                 bool           `json:",omitempty"`
	Hostname                  string         `json:",omitempty"`
	HostnameSet               bool           `json:",omitempty"`
	AdvertiseRoutes           []netip.Prefix `json:",omitempty"`
	AdvertiseRoutesSet        bool           `json:",omitempty"`
}

// loginProfile is the slice of ipn.LoginProfile this service reads.
type loginProfile struct {
	ID             string
	Name           string
	NetworkProfile networkProfile
}

type networkProfile struct {
	DomainName  string
	DisplayName string
}

// busNotify is the slice of ipn.Notify the manager reacts to.
type busNotify struct {
	BrowseToURL   *string
	LoginFinished *struct{}
	State         *int
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
	return c.send(ctx, http.MethodPatch, "/localapi/v0/prefs", body)
}

func (c *localClient) StartLoginInteractive(ctx context.Context) error {
	return c.send(ctx, http.MethodPost, "/localapi/v0/login-interactive", nil)
}

func (c *localClient) Logout(ctx context.Context) error {
	return c.send(ctx, http.MethodPost, "/localapi/v0/logout", nil)
}

func (c *localClient) ProfileStatus(ctx context.Context) (current loginProfile, all []loginProfile, err error) {
	if err = c.getJSON(ctx, "/localapi/v0/profiles/current", &current); err != nil {
		return
	}
	err = c.getJSON(ctx, "/localapi/v0/profiles/", &all)
	return
}

func (c *localClient) SwitchProfile(ctx context.Context, id string) error {
	return c.send(ctx, http.MethodPost, "/localapi/v0/profiles/"+url.PathEscape(id), nil)
}

func (c *localClient) SwitchToEmptyProfile(ctx context.Context) error {
	return c.send(ctx, http.MethodPut, "/localapi/v0/profiles/", nil)
}

func (c *localClient) SuggestExitNode(ctx context.Context) (ExitNodeSuggestion, error) {
	var s ExitNodeSuggestion
	err := c.getJSON(ctx, "/localapi/v0/suggest-exit-node", &s)
	return s, err
}

// CheckIPForwarding returns tailscaled's forwarding warning as an error.
func (c *localClient) CheckIPForwarding(ctx context.Context) error {
	var res struct{ Warning string }
	if err := c.getJSON(ctx, "/localapi/v0/check-ip-forwarding", &res); err != nil {
		return err
	}
	if res.Warning != "" {
		return errors.New(res.Warning)
	}
	return nil
}

func (c *localClient) WatchIPNBus(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
	path := "/localapi/v0/watch-ipn-bus?mask=" + strconv.FormatUint(uint64(mask), 10)
	res, err := c.do(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	return &busWatcher{body: res.Body, dec: json.NewDecoder(res.Body)}, nil
}

func (c *localClient) send(ctx context.Context, method, path string, body []byte) error {
	res, err := c.do(ctx, method, path, body)
	if err != nil {
		return err
	}
	return res.Body.Close()
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
	if res.StatusCode >= 200 && res.StatusCode < 300 {
		return res, nil
	}
	defer res.Body.Close()
	msg, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	if res.StatusCode == http.StatusForbidden {
		return nil, fmt.Errorf("%w: %s", errAccessDenied, errorMessage(msg))
	}
	return nil, fmt.Errorf("%s: %s", res.Status, errorMessage(msg))
}

func errorMessage(body []byte) string {
	var j struct{ Error string }
	if err := json.Unmarshal(body, &j); err == nil && j.Error != "" {
		return j.Error
	}
	return strings.TrimSpace(string(body))
}

// busWatcher streams IPN bus notifications. Arrivals are a hint to refetch
// status; only the login fields of each payload are kept.
type busWatcher struct {
	body io.ReadCloser
	dec  *json.Decoder
}

func (w *busWatcher) Next() (busNotify, error) {
	var n busNotify
	err := w.dec.Decode(&n)
	return n, err
}

func (w *busWatcher) Close() error {
	return w.body.Close()
}
