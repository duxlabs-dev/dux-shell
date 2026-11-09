.pragma library

const INTERFACE_KINDS = [
    [/^tailscale\d*$/, "tailscale"],
    // Docker names its bridges after the first 12 hex digits of the network id.
    [/^br-[0-9a-f]{12}$/, "dockerBridge"],
    [/^docker\d+$/, "docker"],
    [/^virbr\d+$/, "virtualMachines"],
    [/^wg\d*$/, "wireguard"],
    [/^(tun|tap)\d+$/, "vpn"],
    [/^wl/, "wifi"],
    [/^(en|eth)/, "ethernet"],
    [/^(wwan|wwp)/, "cellular"]
];

function interfaceKind(name) {
    const match = INTERFACE_KINDS.find(([pattern]) => pattern.test(name || ""));
    return match ? match[1] : "";
}
