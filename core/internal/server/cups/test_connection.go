package cups

import (
	"errors"
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/pkg/ipp"
)

var validProtocols = map[string]bool{
	"ipp":    true,
	"ipps":   true,
	"lpd":    true,
	"socket": true,
}

func validateTestConnectionParams(host string, port int, protocol string) error {
	if host == "" {
		return errors.New("host is required")
	}
	if strings.ContainsAny(host, " \t\n\r/\\") {
		return errors.New("host contains invalid characters")
	}
	if port < 1 || port > 65535 {
		return errors.New("port must be between 1 and 65535")
	}
	if protocol != "" && !validProtocols[protocol] {
		return errors.New("protocol must be one of: ipp, ipps, lpd, socket")
	}
	return nil
}

const probeTimeout = 10 * time.Second

func probeRemotePrinter(host string, port int, useTLS bool) (*RemotePrinterInfo, error) {
	addr := net.JoinHostPort(host, fmt.Sprintf("%d", port))

	// Fast fail: TCP reachability check
	conn, err := net.DialTimeout("tcp", addr, probeTimeout)
	if err != nil {
		return &RemotePrinterInfo{
			Reachable: false,
			Error:     fmt.Sprintf("cannot reach %s: %s", addr, err.Error()),
		}, nil
	}
	conn.Close()

	// Create a temporary IPP client pointing at the remote host.
	// The TCP dial above provides fast-fail for unreachable hosts.
	// The IPP adapter's ResponseHeaderTimeout (90s) bounds stalling servers.
	client := ipp.NewIPPClient(host, port, "", "", useTLS)

	// Try /ipp/print first (modern driverless printers), then / (legacy)
	info, err := probeIPPEndpoint(client, host, port, useTLS, "/ipp/print")
	if err != nil {
		// If we got an auth error, the printer exists but requires credentials.
		// Report it as reachable with the URI that triggered the auth challenge.
		if isAuthError(err) {
			proto := "ipp"
			if useTLS {
				proto = "ipps"
			}
			return &RemotePrinterInfo{
				Reachable: true,
				URI:       fmt.Sprintf("%s://%s:%d/ipp/print", proto, host, port),
				Info:      "authentication required",
			}, nil
		}
		info, err = probeIPPEndpoint(client, host, port, useTLS, "/")
	}
	if err != nil {
		if isAuthError(err) {
			proto := "ipp"
			if useTLS {
				proto = "ipps"
			}
			return &RemotePrinterInfo{
				Reachable: true,
				URI:       fmt.Sprintf("%s://%s:%d/", proto, host, port),
				Info:      "authentication required",
			}, nil
		}
		// TCP reachable but not an IPP printer
		return &RemotePrinterInfo{
			Reachable: true,
			Error:     fmt.Sprintf("host is reachable but does not appear to be an IPP printer: %s", err.Error()),
		}, nil
	}

	return info, nil
}

func probeIPPEndpoint(client *ipp.IPPClient, host string, port int, useTLS bool, resourcePath string) (*RemotePrinterInfo, error) {
	proto := "ipp"
	if useTLS {
		proto = "ipps"
	}
	printerURI := fmt.Sprintf("%s://%s:%d%s", proto, host, port, resourcePath)

	httpProto := "http"
	if useTLS {
		httpProto = "https"
	}
	httpURL := fmt.Sprintf("%s://%s:%d%s", httpProto, host, port, resourcePath)

	req := ipp.NewRequest(ipp.OperationGetPrinterAttributes, 1)
	req.OperationAttributes[ipp.AttributePrinterURI] = printerURI
	req.OperationAttributes[ipp.AttributeRequestedAttributes] = []string{
		ipp.AttributePrinterName,
		ipp.AttributePrinterMakeAndModel,
		ipp.AttributePrinterState,
		ipp.AttributePrinterInfo,
		ipp.AttributePrinterUriSupported,
	}

	resp, err := client.SendRequest(httpURL, req, nil)
	if err != nil {
		return nil, err
	}

	if len(resp.PrinterAttributes) == 0 {
		return nil, errors.New("no printer attributes returned")
	}

	attrs := resp.PrinterAttributes[0]

	return &RemotePrinterInfo{
		Reachable: true,
		MakeModel: getStringAttr(attrs, ipp.AttributePrinterMakeAndModel),
		Name:      getStringAttr(attrs, ipp.AttributePrinterName),
		Info:      getStringAttr(attrs, ipp.AttributePrinterInfo),
		State:     parsePrinterState(attrs),
		URI:       printerURI,
	}, nil
}

// TestRemotePrinter validates inputs and probes a remote printer via IPP.
// For lpd/socket protocols, only TCP reachability is tested.
func (m *Manager) TestRemotePrinter(host string, port int, protocol string) (*RemotePrinterInfo, error) {
	if protocol == "" {
		protocol = "ipp"
	}

	if err := validateTestConnectionParams(host, port, protocol); err != nil {
		return nil, err
	}

	// For non-IPP protocols, only check TCP reachability
	if protocol == "lpd" || protocol == "socket" {
		addr := net.JoinHostPort(host, fmt.Sprintf("%d", port))
		dial := m.dialFn
		if dial == nil {
			dial = net.DialTimeout
		}
		conn, err := dial("tcp", addr, probeTimeout)
		if err != nil {
			return &RemotePrinterInfo{
				Reachable: false,
				Error:     fmt.Sprintf("cannot reach %s: %s", addr, err.Error()),
			}, nil
		}
		conn.Close()
		return &RemotePrinterInfo{
			Reachable: true,
			URI:       fmt.Sprintf("%s://%s:%d", protocol, host, port),
		}, nil
	}

	useTLS := protocol == "ipps"

	probeFn := m.probeRemoteFn
	if probeFn == nil {
		probeFn = probeRemotePrinter
	}

	return probeFn(host, port, useTLS)
}
