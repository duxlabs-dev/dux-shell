import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const context = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/ConnectionEditor.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), context);
const plain = value => value === undefined ? undefined : JSON.parse(JSON.stringify(value));
const ce = new Proxy(context, { get: (t, name) => typeof t[name] === "function" ? (...args) => plain(t[name](...args)) : plain(t[name]) });

const base = () => ({
    connection: { id: "Home", type: "802-3-ethernet" }, ipv6: { method: "auto" },
    ipv4: { method: "manual", "address-data": [{ address: "192.0.2.10", prefix: 24 }], "dns-data": ["1.1.1.1", "9.9.9.9"] }
});

test("settingsDiff sends only what changed, null for removals, whole new sections", () => {
    const rows = [
        ["key removed", s => delete s.ipv4["dns-data"], { ipv4: { "dns-data": null } }],
        ["section removed", s => delete s.ipv6, { ipv6: null }],
        ["section added", s => { s["802-1x"] = { eap: ["peap"], identity: "u" }; }, { "802-1x": { eap: ["peap"], identity: "u" } }],
        ["list changed as a whole", s => { s.ipv4["dns-data"] = ["9.9.9.9", "1.1.1.1"]; }, { ipv4: { "dns-data": ["9.9.9.9", "1.1.1.1"] } }],
        ["key order is not a change", s => { s.ipv4["address-data"] = [{ prefix: 24, address: "192.0.2.10" }]; }, null]
    ];
    for (const [name, mutate, want] of rows) {
        const draft = base();
        mutate(draft), assert.deepEqual(ce.settingsDiff(base(), draft), want, name);
    }
});

test("address and route text parse per family and keep extra attributes", () => {
    assert.deepEqual(ce.addressDataFromText("192.0.2.10/25\n10.0.0.2/8", 4, [{ address: "192.0.2.10", prefix: 24, label: "eth0:1" }]),
        [{ address: "192.0.2.10", prefix: 25, label: "eth0:1" }, { address: "10.0.0.2", prefix: 8 }]);
    assert.deepEqual([["192.0.2.10/33", 4], ["fe80::1", 4], ["1::2::3/64", 6]].map(([t, fam]) => ce.addressDataFromText(t, fam, [])), [null, null, null]);
    const data = [{ dest: "10.0.0.0", prefix: 8, "next-hop": "192.0.2.1", metric: 50, onlink: true }];
    const rows = ce.routeRows(data);
    assert.deepEqual(ce.routeDataFromRows(rows, 4), data);
    Object.assign(rows[0], { metric: "", nextHop: " " });
    assert.deepEqual(ce.routeDataFromRows(rows, 4), [{ dest: "10.0.0.0", prefix: 8, onlink: true }]);
});

test("changing the IP method drops rejected keys and brings stored ones back", () => {
    const stored = { method: "manual", "address-data": [{ address: "192.0.2.10", prefix: 24 }], gateway: "192.0.2.1", "dns-data": ["1.1.1.1"], "dns-search": ["lan"], "route-metric": 50 };
    const linkLocal = ce.applyIpMethod(stored, 4, "link-local", stored);
    assert.deepEqual(linkLocal, { method: "link-local", "route-metric": 50 });
    assert.deepEqual(ce.applyIpMethod(linkLocal, 4, "manual", stored), stored);
    assert.deepEqual(ce.applyIpMethod(stored, 4, "shared", stored), { method: "shared", "address-data": stored["address-data"], gateway: "192.0.2.1", "route-metric": 50 });
    assert.deepEqual(ce.applyIpMethod({ method: "manual", gateway: "192.0.2.1" }, 4, "auto", undefined), { method: "auto" });
});

test("security mode transitions: Enterprise restore, WEP and SAE cleanup", () => {
    const eap = { connection: { id: "x" }, "802-11-wireless": { ssid: "x" }, "802-1x": { eap: ["peap"], identity: "u" }, "802-11-wireless-security": { "key-mgmt": "wpa-eap" } };
    const sec = (s, mode, psk, orig) => ce.applySecurityMode(s, mode, psk, orig);
    const sae = sec(eap, "sae", "correct horse");
    assert.deepEqual(sae["802-11-wireless-security"], { "key-mgmt": "sae", psk: "correct horse", "psk-flags": 0, pmf: 3 });
    assert.equal(ce.settingsDiff(eap, sae)["802-1x"], null);
    assert.equal("pmf" in sec(sae, "owe")["802-11-wireless-security"], false);
    assert.deepEqual([sec(eap, "none")["802-11-wireless-security"], sec(eap, "none")["802-1x"]], [undefined, undefined]);
    assert.equal(ce.settingsDiff(eap, sec(sec(eap, "wpa-psk", "x"), "wpa-eap", undefined, eap)), null);
    assert.equal("802-1x" in sec({ "802-11-wireless-security": { "key-mgmt": "wpa-psk" } }, "wpa-eap"), false);
    const wep = { "802-11-wireless-security": { "key-mgmt": "none", "wep-key0": "abcde", "wep-key-type": 1, "auth-alg": "shared" } };
    assert.deepEqual(sec(wep, "wpa-psk", "password1")["802-11-wireless-security"], { "key-mgmt": "wpa-psk", psk: "password1", "psk-flags": 0 });
});

const [KEY_A, KEY_B] = ["yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=", "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="];

test("WireGuard peers round-trip through rows and keep unknown keys", () => {
    const peers = [{ "public-key": KEY_A, endpoint: "vpn.example.com:51820", "allowed-ips": ["0.0.0.0/0", "::/0"], "preshared-key": KEY_B, "preshared-key-flags": 0, "persistent-keepalive": 25, foo: "bar" },
        { "public-key": KEY_B, "allowed-ips": ["10.0.0.0/24"] }];
    assert.deepEqual(ce.wgPeersFromRows(ce.wgPeerRows(peers)), peers);
    const cleared = ce.wgPeerRows(peers);
    Object.assign(cleared[0], { presharedKey: "", keepalive: "0" });
    const { "preshared-key": _k, "preshared-key-flags": _f, "persistent-keepalive": _p, ...noPsk } = peers[0];
    assert.deepEqual(ce.wgPeersFromRows(cleared)[0], noPsk);
    assert.deepEqual(ce.wgPeersFromRows(cleared, peers)[0], { ...noPsk, "preshared-key": null });
    for (const [field, value] of [["publicKey", "not-a-key"], ["allowedIps", "10.0.0.0/33"], ["endpoint", "host"]])
        assert.equal(ce.wgPeersFromRows(ce.wgPeerRows(peers).map((r, i) => i ? { ...r, [field]: value } : r)), null, field);
});

test("kvFromRows keeps owned base entries and rejects bad keys", () => {
    const base = { remote: "a", foo: "1" };
    const kv = (...pairs) => pairs.map(([key, value]) => ({ key, value }));
    assert.deepEqual(ce.kvFromRows(kv(["foo", "2"], ["bar", "3"]), base, ["remote"]), { remote: "a", foo: "2", bar: "3" });
    for (const rows of [kv(["foo", "2"], ["foo", "3"]), kv([" ", "2"]), kv(["remote", "b"])])
        assert.equal(ce.kvFromRows(rows, base, ["remote"]), null);
});

test("removing a stored secret sends a null entry, omission keeps", () => {
    const original = { password: "pw", foo: "1" };
    assert.deepEqual(ce.secretsWith(original, "password", "", original), { password: null, foo: "1" });
    assert.deepEqual(ce.secretsWith(original, "password", "new", original), { password: "new", foo: "1" });
    assert.deepEqual(ce.kvFromRows([{ key: "foo", value: "2" }], {}, [], original), { foo: "2", password: null });
});

test("APN edits move auto-config with them", () => {
    assert.deepEqual(ce.applyApn({ "auto-config": true }, " internet ", undefined), { apn: "internet", "auto-config": false });
    assert.deepEqual(ce.applyApn({ apn: "x", "auto-config": false }, "", { "auto-config": false }), { "auto-config": false });
});

test("registry rows and new-profile autoconnect per type", () => {
    const rows = [
        ["vlan", "other", "lan", true, false, ["general", "vlan", "ipv4", "ipv6"]],
        ["bridge", "other", "device_hub", true, false, ["general", "bridge", "ports", "ipv4", "ipv6"]],
        ["pppoe", "other", "router", true, false, ["general", "pppoe", "ethernet", "ppp", "ipv4", "ipv6"]],
        ["gsm", "cellular", "signal_cellular_alt", true, false, ["general", "mobile", "ppp", "ipv4", "ipv6"]],
        ["cdma", "cellular", "signal_cellular_alt", false, true, ["general", "mobile", "ppp", "ipv4", "ipv6"]],
        ["bluetooth", "other", "bluetooth", false, true, ["general", "bluetooth", "ipv4", "ipv6"]]
    ];
    for (const [type, group, icon, addable, autoconnect, sections] of rows) {
        const info = ce.typeInfo(type);
        assert.deepEqual([info.group, info.icon, info.addable], [group, icon, addable], type);
        assert.equal(ce.groupOf(type), group, type);
        assert.deepEqual(ce.sectionsFor(type, { ipv4: {}, ipv6: {} }), sections, type);
        assert.equal(ce.newConnectionSettings(type, { name: "x" }).connection.autoconnect, autoconnect, type);
    }
    for (const type of ["wireguard", "vpn", "vpn:org.freedesktop.NetworkManager.openvpn"])
        assert.equal(ce.newConnectionSettings(type, { name: "x" }).connection.autoconnect, false, type);
    for (const type of ["802-3-ethernet", "802-11-wireless"])
        assert.equal(ce.newConnectionSettings(type, { name: "x" }).connection.autoconnect, true, type);
});

test("only types with a registry row are supported, ports only while their controller is", () => {
    for (const [type, portType, supported] of [
        ["802-3-ethernet", "", true],
        ["team", "", false],
        ["802-3-ethernet", "team", false],
        ["gsm", "", true]
    ])
        assert.equal(ce.isSupported(type, portType), supported, type + "/" + portType);
});

test("ports are detected by either key pair and lose their IP sections", () => {
    assert.deepEqual(ce.portOf({ connection: { master: "u", "slave-type": "bond" } }), { controller: "u", type: "bond" });
    assert.deepEqual(ce.portOf({ connection: { controller: "u", "port-type": "bridge" } }), { controller: "u", type: "bridge" });
    assert.equal(ce.portOf({ connection: { id: "x" } }), null);
    assert.equal(ce.portOf({ connection: { controller: "" } }), null);
    assert.equal(ce.portOf(null), null);

    const port = { connection: { master: "u", "slave-type": "bridge" }, ipv4: {}, ipv6: {} };
    assert.deepEqual(ce.sectionsFor("802-3-ethernet", port), ["general", "ethernet", "security", "port"]);
    assert.deepEqual(ce.sectionsFor("bluetooth", { bluetooth: { type: "dun" }, gsm: {}, ipv4: {} }), ["general", "bluetooth", "mobile", "ppp", "ipv4"]);
    assert.deepEqual(ce.sectionsFor("bluetooth", { bluetooth: { type: "panu" }, ipv4: {}, ipv6: {} }), ["general", "bluetooth", "ipv4", "ipv6"]);
    assert.deepEqual(ce.sectionsFor("bridge", {}), ["general", "bridge", "ports", "ipv4", "ipv6"]);
    assert.deepEqual(ce.sectionsFor("vlan", {}), ["general", "vlan", "ipv4", "ipv6"]);
    assert.deepEqual(ce.sectionsFor("pppoe", {}), ["general", "pppoe", "ethernet", "ppp", "ipv4", "ipv6"]);
    assert.deepEqual(ce.sectionsFor("cdma", {}), ["general", "mobile", "ppp", "ipv4", "ipv6"]);
});

test("new ports and controllers", () => {
    assert.deepEqual(ce.newPortSettings({ uuid: "U", ifname: "dmsbr0", type: "bridge" }, "enp5s0", false), {
        connection: { id: "dmsbr0-port-enp5s0", type: "802-3-ethernet", "interface-name": "enp5s0", master: "U", "slave-type": "bridge", autoconnect: false },
        "802-3-ethernet": {},
        "bridge-port": {}
    });
    assert.equal(ce.newPortSettings({ uuid: "U", ifname: "", id: "Bond", type: "bond" }, "enp5s0", true).connection.id, "Bond-port-enp5s0");
    assert.equal("bridge-port" in ce.newPortSettings({ uuid: "U", ifname: "bond0", type: "bond" }, "enp5s0", true), false);

    const bridge = ce.newConnectionSettings("bridge", { name: "br" });
    assert.deepEqual([bridge.connection["interface-name"], bridge.connection["autoconnect-slaves"], bridge.bridge], ["br0", 1, {}]);
    assert.deepEqual(ce.newConnectionSettings("vlan", { name: "v", parent: "enp5s0" }).vlan, { parent: "enp5s0" });
    assert.deepEqual(ce.newConnectionSettings("vlan", { name: "v" }).vlan, { parent: "" });
    const pppoe = ce.newConnectionSettings("pppoe", { name: "dsl" });
    assert.deepEqual([pppoe.pppoe, pppoe["802-3-ethernet"], pppoe.ppp, pppoe.connection.autoconnect], [{}, {}, {}, false]);
    const gsm = ce.newConnectionSettings("gsm", { name: "m" });
    assert.deepEqual([gsm.gsm, gsm.connection.autoconnect, gsm.ipv4.method], [{ "auto-config": true }, false, "auto"]);
});

test("PPP echo and VLAN names", () => {
    const on = ce.applyPppEcho({ mtu: 1400 }, true);
    assert.deepEqual(on, { mtu: 1400, "lcp-echo-interval": 30, "lcp-echo-failure": 5 });
    assert.equal(ce.pppEcho(on), true);
    assert.deepEqual(ce.applyPppEcho(on, false), { mtu: 1400 });
    assert.equal(ce.pppEcho({ "lcp-echo-interval": 0 }), false);

    assert.equal(ce.defaultVlanIfname("enp5s0", 100), "enp5s0.100");
    assert.equal(ce.defaultVlanIfname("enp5s0", 0), "enp5s0.0");
    assert.equal(ce.defaultVlanIfname("enp5s0f1np1", 4094), "");
    assert.equal(ce.defaultVlanIfname("", 100), "");
    assert.equal(ce.defaultVlanIfname("enp5s0", ""), "");
    assert.equal(ce.defaultVlanIfname("eth0", 4094), "eth0.4094");
    assert.equal(ce.defaultVlanIfname("eth0", 4095), "");
    assert.equal(ce.defaultVlanIfname("eth0", "12a"), "");
});

const enterpriseState = over => ({
    eap: "peap", phase2: "mschapv2", identity: "user", password: "secret", savePassword: true, anonymousIdentity: "", ca: "system", caCertPath: "", caCertPem: "", serverDomain: "radius.example.org",
    serverDomainSuffix: false, clientCertPath: "", privateKeyPath: "", privateKeyPassword: "", peapVersion: "", authFlags: 0, opensslCiphers: "", usernameSuffix: "", ...over
});

test("enterpriseConfig maps form state to EnterpriseConfig", () => {
    assert.equal(ce.enterpriseConfig(enterpriseState({ identity: "stine", usernameSuffix: "uni-hamburg.de" })).identity, "stine@uni-hamburg.de");
    const ask = ce.enterpriseConfig(enterpriseState({ savePassword: false }));
    assert.deepEqual([ask.askPassword, "password" in ask], [true, false]);
    assert.equal(ce.enterpriseConfig(enterpriseState({ authFlags: ce.withFlags(0x8, 0x10, true) })).authFlags, 0x18);
    const pwd = ce.enterpriseConfig(enterpriseState({ eap: "pwd", ca: "file", caCertPath: "/ca.pem", authFlags: 0x8, opensslCiphers: "DEFAULT@SECLEVEL=0" }));
    assert.equal(pwd.ca, "none");
    assert.deepEqual(["phase2", "serverDomain", "authFlags", "opensslCiphers"].filter(k => k in pwd), []);
});

test("enterpriseConfigValid matrix", () => {
    const suffix = { usernameSuffix: "uni-hamburg.de", usernameSuffixRequired: true };
    const cases = [
        ["system CA without server", { serverDomain: "" }, {}, false],
        ["stored CA", { ca: "file" }, { storedFiles: { ca: true } }, true],
        ["TLS without client certificate", { eap: "tls", privateKeyPassword: "k" }, {}, false],
        ["required suffix, wrong domain", { identity: "stine@other.de", usernameSuffix: "uni-hamburg.de" }, suffix, false],
        ["required suffix, appended", { identity: "stine", usernameSuffix: "uni-hamburg.de" }, suffix, true],
        ["PWD ignores CA and server", { eap: "pwd", serverDomain: "" }, {}, true]
    ];
    for (const [name, over, opts, expected] of cases)
        assert.equal(ce.enterpriseConfigValid(ce.enterpriseConfig(enterpriseState(over)), opts), expected, name);
});
