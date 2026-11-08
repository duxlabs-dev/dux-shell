package network

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestLinkInfo_Classify(t *testing.T) {
	// When networkd reports a Type via Describe, classification is exact.
	cases := []struct {
		name      string
		ifname    string
		linkType  string
		wantWired bool
		wantWifi  bool
	}{
		{"ether type", "dock", "ether", true, false},
		{"wlan type", "wifi", "wlan", false, true},
		{"none type (tun overlay)", "nebula.homelab", "none", false, false},
		// Virtual interfaces report Type=ether but must never be mistaken for
		// the wired uplink — stale podman/veth links would otherwise poison
		// ethernet detection.
		{"veth ether excluded", "veth1234", "ether", false, false},
		// The IP lives on the aggregate while the member NIC is "enslaved" (#3463).
		{"bridge type", "br0", "bridge", true, false},
		{"bond type", "bond0", "bond", true, false},
		{"bridge with only virtual members excluded", "lxcbr0", "bridge", false, false},
		{"bridge without members excluded", "waydroid0", "bridge", false, false},
		// Fallback path: linkType unavailable, name-prefix heuristic applies.
		{"fallback enp wired", "enp141s0", "", true, false},
		{"fallback wlan wireless", "wlan0", "", false, true},
		{"wlan with pre-udev ether type", "wlan4", "ether", false, true},
	}
	members := map[string][]string{
		"br0":       {"enp42s0", "vnet0"},
		"lxcbr0":    {"vethAbCd12"},
		"waydroid0": nil,
	}
	orig := bridgeMembers
	bridgeMembers = func(b string) []string { return members[b] }
	t.Cleanup(func() { bridgeMembers = orig })

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			l := &linkInfo{name: tc.ifname, linkType: tc.linkType}
			assert.Equal(t, tc.wantWired, l.isWired(), "isWired")
			assert.Equal(t, tc.wantWifi, l.isWireless(), "isWireless")
		})
	}
}

func TestParseDescribeType(t *testing.T) {
	// parseDescribeType is the seam between networkd's Describe RPC and the
	// classifier. On any failure path it must return "" so callers fall back
	// to name-prefix heuristics rather than misclassifying the link.
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"ether", `{"Type":"ether","Name":"enp141s0"}`, "ether"},
		{"missing Type field", `{"Name":"wlan0","Kind":""}`, ""},
		{"malformed json", `{"Type":"ether"`, ""},
		{"non-string Type", `{"Type":42}`, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.want, parseDescribeType(tc.in))
		})
	}
}

func TestSyncLinks_PrunesRemovedLinks(t *testing.T) {
	// Stale container interfaces (torn-down podman bridges, veth pairs) must
	// not linger in the link map after they disappear from ListLinks — kept as
	// routable, they stole the wired-uplink slot from the real ethernet NIC.
	backend, _ := NewSystemdNetworkdBackend()
	backend.links = map[string]*linkInfo{
		"eno1":    {ifindex: 2, name: "eno1", path: "/org/freedesktop/network1/link/_32", linkType: "ether", opState: "routable"},
		"podman3": {ifindex: 9, name: "podman3", path: "/org/freedesktop/network1/link/_39", linkType: "ether", opState: "routable"},
		"veth0":   {ifindex: 10, name: "veth0", path: "/org/freedesktop/network1/link/_310", linkType: "ether", opState: "routable"},
	}

	backend.syncLinks([]enumeratedLink{
		{ifindex: 2, name: "eno1", path: "/org/freedesktop/network1/link/_32"},
	})

	assert.Len(t, backend.links, 1)
	assert.Contains(t, backend.links, "eno1")
	assert.NotContains(t, backend.links, "podman3")
	assert.NotContains(t, backend.links, "veth0")
}

func TestSyncLinks_RefreshesSurvivingLink(t *testing.T) {
	// A link that survives keeps its cached Type — Describe is only queried for
	// newly seen links — while picking up a refreshed ifindex.
	backend, _ := NewSystemdNetworkdBackend()
	backend.links = map[string]*linkInfo{
		"eno1": {ifindex: 2, name: "eno1", path: "/org/freedesktop/network1/link/_32", linkType: "ether"},
	}

	backend.syncLinks([]enumeratedLink{
		{ifindex: 7, name: "eno1", path: "/org/freedesktop/network1/link/_32"},
	})

	assert.Len(t, backend.links, 1)
	assert.Equal(t, int32(7), backend.links["eno1"].ifindex)
	assert.Equal(t, "ether", backend.links["eno1"].linkType)
}

func TestLooksVirtual(t *testing.T) {
	virtual := []string{"lo", "docker0", "veth123", "virbr0", "br-abc", "vnet0", "tun0", "tap0", "vboxnet0", "vmnet1", "kube-ipvs0", "cni0", "flannel.1", "cali-abc", "podman0", "podman3"}
	for _, n := range virtual {
		assert.True(t, looksVirtual(n), "%s should look virtual", n)
	}
	real := []string{"enp141s0", "eno1", "wlan0", "wlp3s0", "wifi", "dock", "nebula.homelab", "wg0", "br0", "bond0", "team0", "vlan10"}
	for _, n := range real {
		assert.False(t, looksVirtual(n), "%s should not look virtual", n)
	}
}
