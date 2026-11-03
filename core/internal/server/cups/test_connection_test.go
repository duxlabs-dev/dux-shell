package cups

import (
	"bytes"
	"encoding/json"
	"errors"
	"net"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/stretchr/testify/assert"
)

func TestValidateTestConnectionParams(t *testing.T) {
	tests := []struct {
		name     string
		host     string
		port     int
		protocol string
		wantErr  string
	}{
		{
			name:     "valid ipp",
			host:     "192.168.0.5",
			port:     631,
			protocol: "ipp",
			wantErr:  "",
		},
		{
			name:     "empty host",
			host:     "",
			port:     631,
			protocol: "ipp",
			wantErr:  "host is required",
		},
		{
			name:     "port too low",
			host:     "192.168.0.5",
			port:     0,
			protocol: "ipp",
			wantErr:  "port must be between 1 and 65535",
		},
		{
			name:     "invalid protocol",
			host:     "192.168.0.5",
			port:     631,
			protocol: "ftp",
			wantErr:  "protocol must be one of: ipp, ipps, lpd, socket",
		},
		{
			name:     "empty protocol treated as ipp",
			host:     "192.168.0.5",
			port:     631,
			protocol: "",
			wantErr:  "",
		},
		{
			name:     "host with slash",
			host:     "192.168.0.5/admin",
			port:     631,
			protocol: "ipp",
			wantErr:  "host contains invalid characters",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateTestConnectionParams(tt.host, tt.port, tt.protocol)
			if tt.wantErr == "" {
				assert.NoError(t, err)
			} else {
				assert.EqualError(t, err, tt.wantErr)
			}
		})
	}
}

func TestManager_TestRemotePrinter_Validation(t *testing.T) {
	m := NewTestManager(nil, nil)

	tests := []struct {
		name     string
		host     string
		port     int
		protocol string
		wantErr  string
	}{
		{
			name:     "empty host returns error",
			host:     "",
			port:     631,
			protocol: "ipp",
			wantErr:  "host is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := m.TestRemotePrinter(tt.host, tt.port, tt.protocol)
			assert.EqualError(t, err, tt.wantErr)
		})
	}
}

func TestManager_TestRemotePrinter_IPP(t *testing.T) {
	tests := []struct {
		name      string
		protocol  string
		probeRet  *RemotePrinterInfo
		probeErr  error
		wantTLS   bool
		wantReach bool
		wantModel string
	}{
		{
			name:     "successful ipp probe",
			protocol: "ipp",
			probeRet: &RemotePrinterInfo{
				Reachable: true,
				MakeModel: "HP OfficeJet 8010",
				Name:      "OfficeJet",
				State:     "idle",
				URI:       "ipp://192.168.0.5:631/ipp/print",
			},
			wantTLS:   false,
			wantReach: true,
			wantModel: "HP OfficeJet 8010",
		},
		{
			name:     "successful ipps probe",
			protocol: "ipps",
			probeRet: &RemotePrinterInfo{
				Reachable: true,
				MakeModel: "HP OfficeJet 8010",
				URI:       "ipps://192.168.0.5:631/ipp/print",
			},
			wantTLS:   true,
			wantReach: true,
			wantModel: "HP OfficeJet 8010",
		},
		{
			name:     "empty protocol defaults to ipp",
			protocol: "",
			probeRet: &RemotePrinterInfo{
				Reachable: true,
				MakeModel: "Test Printer",
			},
			wantTLS:   false,
			wantReach: true,
			wantModel: "Test Printer",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var capturedTLS bool
			m := NewTestManager(nil, nil)
			m.probeRemoteFn = func(host string, port int, useTLS bool) (*RemotePrinterInfo, error) {
				capturedTLS = useTLS
				return tt.probeRet, tt.probeErr
			}

			result, err := m.TestRemotePrinter("192.168.0.5", 631, tt.protocol)
			if tt.probeErr != nil {
				assert.Error(t, err)
				return
			}
			assert.NoError(t, err)
			assert.Equal(t, tt.wantReach, result.Reachable)
			assert.Equal(t, tt.wantModel, result.MakeModel)
			assert.Equal(t, tt.wantTLS, capturedTLS)
		})
	}
}

func TestManager_TestRemotePrinter_NonIPPProtocol(t *testing.T) {
	m := NewTestManager(nil, nil)
	probeCalled := false
	m.probeRemoteFn = func(host string, port int, useTLS bool) (*RemotePrinterInfo, error) {
		probeCalled = true
		return nil, nil
	}

	dialed := []string{}
	m.dialFn = func(network, addr string, timeout time.Duration) (net.Conn, error) {
		dialed = append(dialed, addr)
		return nil, errors.New("connection refused")
	}

	info, err := m.TestRemotePrinter("192.168.0.5", 9100, "socket")
	assert.NoError(t, err)
	assert.False(t, info.Reachable)
	assert.Contains(t, info.Error, "192.168.0.5:9100")
	assert.False(t, probeCalled, "probe function should not be called for socket protocol")

	info, err = m.TestRemotePrinter("192.168.0.5", 515, "lpd")
	assert.NoError(t, err)
	assert.False(t, info.Reachable)
	assert.False(t, probeCalled, "probe function should not be called for lpd protocol")
	assert.Equal(t, []string{"192.168.0.5:9100", "192.168.0.5:515"}, dialed)
}

func TestManager_TestRemotePrinter_NonIPPReachable(t *testing.T) {
	m := NewTestManager(nil, nil)
	server, client := net.Pipe()
	defer server.Close()
	m.dialFn = func(network, addr string, timeout time.Duration) (net.Conn, error) {
		return client, nil
	}

	info, err := m.TestRemotePrinter("192.168.0.5", 9100, "socket")
	assert.NoError(t, err)
	assert.True(t, info.Reachable)
	assert.Equal(t, "socket://192.168.0.5:9100", info.URI)
}

func TestHandleTestConnection_Success(t *testing.T) {
	m := NewTestManager(nil, nil)
	m.probeRemoteFn = func(host string, port int, useTLS bool) (*RemotePrinterInfo, error) {
		return &RemotePrinterInfo{
			Reachable: true,
			MakeModel: "HP OfficeJet 8010",
			Name:      "OfficeJet",
			State:     "idle",
			URI:       "ipp://192.168.0.5:631/ipp/print",
		}, nil
	}

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.testConnection",
		Params: map[string]any{
			"host": "192.168.0.5",
		},
	}

	handleTestConnection(conn, req, m)

	var resp ipc.Response[RemotePrinterInfo]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Reachable)
	assert.Equal(t, "HP OfficeJet 8010", resp.Result.MakeModel)
}

func TestHandleTestConnection_MissingHost(t *testing.T) {
	m := NewTestManager(nil, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.testConnection",
		Params: map[string]any{},
	}

	handleTestConnection(conn, req, m)

	var resp ipc.Response[any]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.Nil(t, resp.Result)
	assert.NotNil(t, resp.Error)
}

func TestHandleTestConnection_CustomPortAndProtocol(t *testing.T) {
	m := NewTestManager(nil, nil)
	m.probeRemoteFn = func(host string, port int, useTLS bool) (*RemotePrinterInfo, error) {
		assert.Equal(t, 9631, port)
		assert.True(t, useTLS)
		return &RemotePrinterInfo{Reachable: true, URI: "ipps://192.168.0.5:9631/ipp/print"}, nil
	}

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.testConnection",
		Params: map[string]any{
			"host":     "192.168.0.5",
			"port":     float64(9631),
			"protocol": "ipps",
		},
	}

	handleTestConnection(conn, req, m)

	var resp ipc.Response[RemotePrinterInfo]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Reachable)
}

func TestHandleRequest_TestConnection(t *testing.T) {
	m := NewTestManager(nil, nil)
	m.probeRemoteFn = func(host string, port int, useTLS bool) (*RemotePrinterInfo, error) {
		return &RemotePrinterInfo{Reachable: true}, nil
	}

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.testConnection",
		Params: map[string]any{"host": "192.168.0.5"},
	}

	HandleRequest(conn, req, m)

	var resp ipc.Response[RemotePrinterInfo]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Reachable)
}
