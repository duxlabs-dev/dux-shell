package tailscale

import (
	"sort"
	"strings"
	"time"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/tailcfg"
)

// convertStatus converts an ipnstate.Status into our TailscaleState IPC type.
func convertStatus(status *ipnstate.Status) *TailscaleState {
	connected := status.BackendState == "Running"

	state := &TailscaleState{
		Connected:    connected,
		BackendState: status.BackendState,
		Version:      status.Version,
	}

	if status.CurrentTailnet != nil {
		state.TailnetName = status.CurrentTailnet.Name
		state.MagicDNSSuffix = status.CurrentTailnet.MagicDNSSuffix
	}

	if !connected {
		return state
	}

	users := status.User

	if status.Self != nil {
		state.Self = convertPeerStatus(status.Self, users)
		state.Self.Online = true
	}

	if len(status.Peer) > 0 {
		peers := make([]Peer, 0, len(status.Peer))
		for _, ps := range status.Peer {
			peers = append(peers, convertPeerStatus(ps, users))
		}
		sort.Slice(peers, func(i, j int) bool {
			if peers[i].Online != peers[j].Online {
				return peers[i].Online
			}
			return strings.ToLower(peers[i].Hostname) < strings.ToLower(peers[j].Hostname)
		})
		state.Peers = peers
	}

	return state
}

// convertPeerStatus converts an ipnstate.PeerStatus into our Peer IPC type.
func convertPeerStatus(ps *ipnstate.PeerStatus, users map[tailcfg.UserID]tailcfg.UserProfile) Peer {
	dnsName := strings.TrimSuffix(ps.DNSName, ".")

	// DNSName first label is unique per node; OS HostName is not.
	hostname := ps.HostName
	if dnsName != "" {
		parts := strings.SplitN(dnsName, ".", 2)
		if len(parts) > 0 && parts[0] != "" {
			hostname = parts[0]
		}
	}

	peer := Peer{
		ID:             string(ps.ID),
		Hostname:       hostname,
		DNSName:        dnsName,
		OS:             ps.OS,
		Online:         ps.Online,
		Active:         ps.Active,
		ExitNode:       ps.ExitNode,
		ExitNodeOption: ps.ExitNodeOption,
		Relay:          ps.Relay,
		RxBytes:        ps.RxBytes,
		TxBytes:        ps.TxBytes,
	}

	for _, ip := range ps.TailscaleIPs {
		if ip.Is4() {
			if peer.TailscaleIP == "" {
				peer.TailscaleIP = ip.String()
			}
		} else {
			if peer.TailscaleIPv6 == "" {
				peer.TailscaleIPv6 = ip.String()
			}
		}
	}

	if ps.Tags != nil {
		peer.Tags = ps.Tags.AsSlice()
	}

	if ps.UserID > 0 {
		if user, ok := users[ps.UserID]; ok {
			peer.Owner = user.LoginName
		}
	}

	if !ps.LastSeen.IsZero() {
		peer.LastSeen = ps.LastSeen.UTC().Format(time.RFC3339)
	}

	return peer
}
