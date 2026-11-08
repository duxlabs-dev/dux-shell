# NetworkManager API Documentation

## Overview

The network manager API provides methods for managing WiFi connections, monitoring network state, and handling credential prompts through NetworkManager or iwd (and systemd-networkd for ethernet only). Communication occurs over a message-based protocol (websocket, IPC, etc.) with event subscriptions for state updates.

## API Methods

### network.hotspot.configure

Create or update the DMS-managed hotspot profile. Hotspot support is capability-gated: clients should require API v28+, `hotspotSupported: true`, and `hotspotAvailable: true` from network state before showing hotspot controls.

For this implementation, only hotspot-capable backends such as NetworkManager should accept this action. Unsupported backends return an error such as `hotspot not supported by active network backend`.

Configuration changes are rejected while the DMS hotspot is active or activating; stop it before updating the profile. Each call replaces the whole profile and keeps its UUID.

**Request:**
```json
{
  "method": "network.hotspot.configure",
  "params": {
    "ssid": "Dank Hotspot",
    "password": "optional-password",
    "device": "wlan0",
    "band": "bg",
    "channel": 6,
    "address": "10.42.0.1/24",
    "security": "sae",
    "hidden": false,
    "autoconnect": false
  }
}
```

**Parameters:**
- `ssid` (string, required): Hotspot SSID to advertise.
- `password` (string, optional): Hotspot password. Omit for an open hotspot when the backend allows it.
- `device` (string, optional): Wi-Fi interface name to use, for example `wlan0`. When omitted, the backend picks an AP-capable radio at start time, preferring one that is already hosting the hotspot, then an idle radio, and only as a last resort a radio carrying an active connection (which NetworkManager will disconnect). Network state exposes `apCapable` on each `wifiDevices` entry so clients can predict this choice.
- `band` (string, optional): Requested NetworkManager band: `bg` for 2.4GHz or `a` for 5GHz.
- `channel` (integer, optional, API v41+): Wi-Fi channel, 1-14 for `bg` and 1-196 for `a`; a non-zero channel requires `band`. `0` or omitted lets NetworkManager choose. Non-integer or out-of-range values are rejected.
- `address` (string, optional, API v41+): Gateway address with prefix, for example `10.42.0.1/24`. Omit for NetworkManager's default.
- `security` (string, optional, API v41+): `wpa-psk` (WPA2) or `sae` (WPA3), both requiring `password`. Omitted or empty means open, or WPA2 when `password` is set.
- `hidden` (bool, optional, API v41+): Hide the SSID. Defaults to `false`.
- `autoconnect` (bool, optional, API v41+): Let NetworkManager start the hotspot on its own. Defaults to `false`.

**Response:**
```json
{
  "success": true,
  "message": "hotspot configured"
}
```

### network.hotspot.start

Start the previously configured DMS-managed hotspot profile. This action does not accept or require SSID/password parameters; call `network.hotspot.configure` first when changing hotspot settings.

A successful response only means the activation was requested; the outcome is reported asynchronously through network state updates. While activation is in flight, `hotspotActivating` is `true`; on success `hotspotEnabled` becomes `true`; on failure `hotspotActivating` returns to `false` and `hotspotLastError` carries one of `hotspot-ip-config-failed` (IP sharing setup failed, commonly a missing `dnsmasq`, which NetworkManager's shared IPv4 method requires), `hotspot-supplicant-failed` (the Wi-Fi driver could not start AP mode), `hotspot-wpa3-failed` (API v41+, the same failure on a WPA3 hotspot, commonly a driver or wpa_supplicant without SAE support in AP mode), or `hotspot-failed`. `hotspotLastError` is cleared on the next successful start.

**Request:**
```json
{
  "method": "network.hotspot.start"
}
```

**Response:**
```json
{
  "success": true,
  "message": "hotspot started"
}
```

### network.hotspot.stop

Stop the active DMS-managed hotspot connection. It must not stop arbitrary user-created hotspot profiles.

**Request:**
```json
{
  "method": "network.hotspot.stop"
}
```

**Response:**
```json
{
  "success": true,
  "message": "hotspot stopped"
}
```

### network.hotspot.getSecrets

Retrieve the stored password of the DMS-managed hotspot profile, for prefilling edit forms. Returns an empty string for an open hotspot. Network state exposes `hotspotSecured` so clients can tell an open hotspot apart from a secured one without fetching the secret.

**Request:**
```json
{
  "method": "network.hotspot.getSecrets"
}
```

**Response:**
```json
{
  "password": "the-stored-psk"
}
```

### network.connectivity.* (API v41+, NetworkManager only)

- `network.connectivity.check {}`: asks NetworkManager to re-probe now and returns `{"connectivity": "unknown|none|portal|limited|full"}`.
- `network.connectivity.setCheckEnabled {enabled}`: turns NetworkManager's connectivity checking on or off (`enabled` is required). Other backends return `connection editor not supported by active network backend`.

### network.ethernet.connect / network.ethernet.connect.config

`network.ethernet.connect` activates the device and lets NetworkManager pick the profile. `network.ethernet.connect.config {uuid}` activates a specific saved profile.

Both take an optional `device` (string): the interface name to use, for example `enp3s0`. Without it, `connect` uses the first available (not unavailable or unmanaged) Ethernet device, sorted by interface name, and `connect.config` lets NetworkManager pick the device.

### network.connection.*

Generic profile editor (API v41+, NetworkManager only). Clients should require `connectionEditorSupported: true` in network state. Other backends return `connection editor not supported by active network backend`. Validation is left to NetworkManager, whose error text is returned unchanged.

- `network.connection.list`: returns `[{uuid, id, type, device?, interfaceName?, active, activeState?, autoconnect, timestamp, unsaved, canModify, ssid?, controller?, portType?}]` (`controller` and `portType`, API v41+, are set for every port profile). `canModify` is false only when polkit denies changing the profile outright; `ssid` is set for Wi-Fi profiles. Externally managed profiles (docker0, tailscale0, ...) are omitted. `unsaved` means the profile lives in memory only.
- `network.connection.get {uuid, secrets?: bool}`: returns `{section: {key: value}}`. Secrets are included only when `secrets` is `true`.
- `network.connection.update {uuid, settings, persist?: bool, enterprise?: object}`: merges `settings` into the profile. A `null` key deletes it, a `null` section deletes the section. `persist` (default `false`) writes the profile to disk; otherwise it stays where it is stored.
- `network.connection.add {settings, persist?: bool, enterprise?: object}`: creates a profile and returns `{"uuid": "..."}`. `settings.connection.type` is required. `persist` defaults to `true`; `false` creates an in-memory profile.
- `enterprise` (API v41+, on `update` and `add`): the same object as `network.wifi.connect`. DMS builds the `802-1x` section from it; any `802-1x` key in `settings` is ignored. On update, omitted certificate paths keep the stored files.
- `network.connection.activate {uuid, device?}` (API v41+): activates a saved profile. NetworkManager picks the device when `device` is omitted.
- `network.connection.deactivate {uuid}` (API v41+): deactivates the profile. Succeeds if it isn't active.
- `network.connection.getEnterprise {uuid}` (API v41+): returns the profile's 802.1X settings in the `enterprise` shape, without passwords. Stored certificates come back with an empty path. Errors when the profile has no 802.1X settings.
- `network.connection.firewallZones` (API v41+): returns the firewalld zone names, or `[]` when firewalld isn't running.
- `network.connection.delete {uuid}`
- `network.connection.duplicate {uuid, name}`: copies a profile, including stored secrets, under a new UUID and the given name. Returns `{"uuid": "..."}`.
- `network.connection.export {uuid, file}` (API v41+): writes a WireGuard profile (wg-quick format) or a VPN profile (`nmcli connection export`) to the absolute path `file` with mode 0600. An existing regular file is replaced; a symlink or any other non-regular file at `file` is refused. Other profile types and NetworkManager's own errors are returned as text.
- `network.wireguard.keys {privateKey?}` (API v41+): without `privateKey`, returns a new `{privateKey, publicKey}` pair. With it, returns the same private key and its derived public key. Errors with `invalid WireGuard key` unless it is base64 of 32 bytes. Works on any backend.

```json
{
  "method": "network.connection.update",
  "params": {
    "uuid": "5f0e...",
    "settings": {
      "connection": { "autoconnect": false },
      "ipv6": null
    }
  }
}
```

### network.wifi.connect

Initiate a WiFi connection.

**Request:**
```json
{
  "method": "network.wifi.connect",
  "params": {
    "ssid": "NetworkName",
    "password": "optional-password",
    "interactive": true
  }
}
```

**Parameters:**
- `ssid` (string, required): Network SSID
- `password` (string, optional): Pre-shared key for WPA/WPA2/WPA3 networks
- `device` (string, optional): Wi-Fi interface to use
- `hidden` (boolean, optional): Network does not broadcast its SSID
- `interactive` (boolean, optional): Enable credential prompting if authentication fails or password is missing. Automatically set to `true` when connecting to secured networks without providing a password.
- `security` (string, optional): `none`, `owe`, `wpa-psk`, `sae` or `wpa-eap`. Needed for hidden networks and when saving without a visible access point.
- `enterprise` (object, optional): 802.1X settings, NetworkManager backend only. Unknown keys are rejected.
- `saveOnly` (boolean, optional): Create or update the saved profile without connecting. NetworkManager backend only; an existing profile for the SSID is updated in place.

The flat enterprise params (`username`, `eapMethod`, `phase2Auth`, `anonymousIdentity`, `domainSuffixMatch`, `caCertPath`, `clientCertPath`, `privateKeyPath`, `useSystemCACerts`) were removed in API 41 in favor of `enterprise`.

**`enterprise` object:**

| Key | Type | Description |
|-----|------|-------------|
| `eap` | string | `peap`, `ttls`, `tls` or `pwd` |
| `phase2` | string | Inner method. `peap`: `mschapv2`, `gtc`, `md5`. `ttls`: `pap`, `mschap`, `mschapv2`, `chap`, `eap-mschapv2` |
| `identity` | string | User name |
| `password` | string | Password |
| `askPassword` | boolean | Do not store the password; prompt at every connection |
| `anonymousIdentity` | string | Outer identity |
| `ca` | string | `file`, `system` or `none` |
| `caCertPath` | string | CA certificate file, when `ca` is `file` |
| `caCertPem` | string | CA certificate as PEM, as returned by `network.eapconfig.parse` |
| `serverDomain` | string | RADIUS server name(s), `;`-separated. Required when `ca` is `system` |
| `serverDomainSuffix` | boolean | Match the domain as a suffix instead of exactly |
| `clientCertPath`, `privateKeyPath` | string | Client certificate and key for `tls` |
| `privateKeyPassword` | string | Private key password |
| `peapVersion` | string | `""`, `"0"` or `"1"` |
| `authFlags` | integer | `phase1-auth-flags` bitmask |
| `opensslCiphers` | string | OpenSSL cipher string |

**Response:**
```json
{
  "success": true,
  "message": "connecting"
}
```

With `saveOnly` the message is `"saved"`.

**Behavior:**
- Returns immediately; connection happens asynchronously
- State updates delivered via `network` service subscription
- Credential prompts delivered via `network.credentials` service subscription

### network.eapconfig.parse

Parse an eduroam `.eap-config` file (for example from cat.eduroam.org) into a prefilled `enterprise` object. NetworkManager backend only.

**Request:**
```json
{
  "method": "network.eapconfig.parse",
  "params": {
    "file": "/home/user/Downloads/eduroam.eap-config"
  }
}
```

**Parameters:**
- `file` (string, required): Path to a regular file of at most 4 MiB

**Response:**
```json
{
  "providerName": "Example University",
  "ssids": ["eduroam"],
  "usernameSuffix": "example.edu",
  "usernameHint": true,
  "enterprise": { "eap": "ttls", "phase2": "pap", "ca": "file", "caCertPem": "-----BEGIN CERTIFICATE-----...", "serverDomain": "radius.example.edu" }
}
```

Errors (missing, oversized or malformed file) are returned as the error string.

### network.credentials.submit

Submit credentials in response to a prompt.

**Request:**
```json
{
  "method": "network.credentials.submit",
  "params": {
    "token": "correlation-token",
    "secrets": {
      "psk": "password"
    },
    "save": true
  }
}
```

**Parameters:**
- `token` (string, required): Token from credential prompt
- `secrets` (object, required): Key-value map of credential fields
- `save` (boolean, optional): Whether to persist credentials (default: false)

**Common secret fields:**
- `psk`: Pre-shared key for WPA2/WPA3 personal networks
- `identity`: Username for 802.1X enterprise networks
- `password`: Password for 802.1X enterprise networks

### network.credentials.cancel

Cancel a credential prompt.

**Request:**
```json
{
  "method": "network.credentials.cancel",
  "params": {
    "token": "correlation-token"
  }
}
```

### tailscale.* (API v41+)

Served by the Tailscale manager, not the network service. Writes need permission on tailscaled (root, the daemon's user or the operator); `tailscale.profiles` reports it as `canOperate`.

- `tailscale.setPrefs {acceptRoutes?, acceptDns?, shieldsUp?, runSsh?, hostname?, advertiseExitNode?, advertiseRoutes?}`: returns `{success, warning?}`. `warning` is set when advertising routes while IP forwarding is off.
- `tailscale.login`, `tailscale.logout`: take no params. The login URL arrives as `authUrl` in state.
- `tailscale.addProfile {server?}`: asks polkit to run `tailscale login --operator=<user> --login-server=<server>`, which creates a new account, then starts its login. `server` is an http or https URL; empty or omitted means tailscale.com. The login URL arrives as `authUrl` in state.
- `tailscale.profiles`: returns `{canOperate, grantAvailable, current, profiles: [{id, name, tailnet}]}`.
- `tailscale.switchProfile {id}`
- `tailscale.suggestExitNode`: returns `{id, name}`.
- `tailscale.grantOperator`: asks polkit to run `tailscale set --operator=<user>`, then returns the same result as `tailscale.profiles`.

State gains `prefs` (`{acceptRoutes, acceptDns, shieldsUp, runSsh, hostname, operatorUser, controlUrl, advertiseExitNode, advertiseRoutes}`) and `authUrl` (present while interactive login is pending).

## Event Subscriptions

### Subscribing to Events

Subscribe to receive network state updates and credential prompts:

```json
{
  "method": "subscribe",
  "params": {
    "services": ["network", "network.credentials"]
  }
}
```

Both services are required for full connection handling. Missing `network.credentials` means credential prompts won't be received.

### network Service Events

State updates are sent whenever network configuration changes:

```json
{
  "service": "network",
  "data": {
    "networkStatus": "wifi",
    "isConnecting": false,
    "connectingSSID": "",
    "wifiConnected": true,
    "wifiSSID": "MyNetwork",
    "wifiIP": "192.168.1.100",
    "lastError": ""
  }
}
```

**State fields:**
- `networkStatus`: Current connection type (`wifi`, `ethernet`, `disconnected`)
- `isConnecting`: Whether a connection attempt is in progress
- `connectingSSID`: SSID being connected to (empty when idle)
- `wifiConnected`: Whether associated with an access point
- `wifiSSID`: Currently connected network name
- `wifiIP`: Assigned IP address (empty until DHCP completes)
- `savedWifiNetworks` (API v26+): Saved WiFi profiles exposed at SSID granularity. If a backend has multiple profiles for the same SSID, DMS merges them into one SSID-level entry. Clients talking to older servers should derive saved visible networks from `wifiNetworks` entries where `saved` is true.
- `savedWifiNetworks[].outOfRange` (API v26+): Whether the saved profile is not currently visible in scan results. Fallback entries derived from `wifiNetworks` should be treated as visible (`outOfRange: false`).
- `ethernetDevices[].connectionUuid` (API v41+): UUID of the profile active on the device, if any. `profileUuids` lists the saved profiles that fit it (never `null`). Each `wiredConnections` entry carries the `device` it is active on.
- `hotspotSupported` (API v28+): Whether the active backend implements hotspot actions.
- `connectionEditorSupported` (API v41+): Whether the active backend implements the `network.connection.*` editor methods.
- `connectionProfilesRevision` (API v41+): Counter that increases when a profile is added, removed or changed, and when active connections change. Clients re-list profiles when it changes.
- `hotspotAvailable` (API v28+): Whether hotspot support is usable on this backend/device set. For NetworkManager this means at least one AP-capable managed Wi-Fi device exists, independent of Wi-Fi radio enabled state.
- `hotspotConfigured` (API v28+): Whether the DMS-managed hotspot profile exists.
- `hotspotEnabled` (API v28+): Whether the DMS-managed hotspot profile is currently active.
- `hotspotActivating` (API v28+): Whether hotspot activation is currently in progress.
- `hotspotSecured` (API v28+): Whether the configured hotspot uses password-based security.
- `hotspotSSID` (API v28+): Configured DMS hotspot SSID.
- `hotspotChannel` (API v41+): Configured hotspot channel (`0` = automatic).
- `hotspotAddress` (API v41+): Configured hotspot gateway address with prefix, empty for NetworkManager's default.
- `hotspotUuid` (API v41+): UUID of the DMS-managed hotspot profile.
- `hotspotSecurity` (API v41+): The hotspot's key management, `wpa-psk` or `sae`, empty when open.
- `hotspotHidden` (API v41+): Whether the hotspot hides its SSID.
- `hotspotAutoconnect` (API v41+): Whether NetworkManager may start the hotspot on its own.
- `connectivity` (API v41+): `unknown`, `none`, `portal`, `limited` or `full`.
- `connectivityCheckEnabled` (API v41+): Whether NetworkManager's connectivity checking is on.
- `connectivityCheckAvailable` (API v41+): Whether a check URI is configured so checking can be enabled.
- `connectivityCheckUri` (API v41+): The URI NetworkManager probes; open it to reach a captive portal.
- `hotspotDevice` (API v28+): Optional configured Wi-Fi device for the DMS hotspot.
- `hotspotBand` (API v28+): Optional configured hotspot band (`bg` or `a`).
- `hotspotLastError` (API v28+): Machine-readable error from the most recent failed hotspot activation. Cleared when the next start succeeds.
- `lastError`: Error message from last failed connection attempt

### network.credentials Service Events

Credential prompts are sent when authentication is required:

```json
{
  "service": "network.credentials",
  "data": {
    "token": "unique-prompt-id",
    "ssid": "NetworkName",
    "setting": "802-11-wireless-security",
    "fields": ["psk"],
    "hints": ["wpa3", "sae"],
    "reason": "Credentials required"
  }
}
```

**Prompt fields:**
- `token`: Unique identifier for this prompt (use in submit/cancel)
- `ssid`: Network requesting credentials
- `setting`: Authentication type (`802-11-wireless-security` for personal WiFi, `802-1x` for enterprise)
- `fields`: Array of required credential field names
- `hints`: Additional context about the network type
- `reason`: Human-readable explanation (e.g., "Previous password was incorrect")

## Connection Flow

### Typical Timeline

```
T+0ms     Call network.wifi.connect
T+10ms    Receive {"success": true, "message": "connecting"}
T+100ms   State update: isConnecting=true, connectingSSID="Network"
T+500ms   Credential prompt (if needed)
T+1000ms  Submit credentials
T+3000ms  State update: wifiConnected=true, wifiIP="192.168.x.x"
```

### State Machine

```
IDLE
  |
  | network.wifi.connect
  v
CONNECTING (isConnecting=true, connectingSSID set)
  |
  +-- Needs credentials
  |     |
  |     v
  |   PROMPTING (credential prompt event)
  |     |
  |     | network.credentials.submit
  |     v
  |   back to CONNECTING
  |
  +-- Success
  |     |
  |     v
  |   CONNECTED (wifiConnected=true, wifiIP set, isConnecting=false)
  |
  +-- Failure
        |
        v
      ERROR (isConnecting=false, !wifiConnected, lastError set)
```

## Connection Success Detection

A connection is successful when all of the following are true:

1. `wifiConnected` is `true`
2. `wifiIP` is set and non-empty
3. `wifiSSID` matches the target network
4. `isConnecting` is `false`

Do not rely on `wifiConnected` alone - the device may be associated with an access point but not have an IP address yet.

**Example:**
```javascript
function isConnectionComplete(state, targetSSID) {
    return state.wifiConnected &&
           state.wifiIP &&
           state.wifiIP !== "" &&
           state.wifiSSID === targetSSID &&
           !state.isConnecting;
}
```

## Error Handling

### Error Detection

Errors occur when a connection attempt stops without success:

```javascript
function checkForFailure(state, wasConnecting, targetSSID) {
    // Was connecting, now idle, but not connected
    if (wasConnecting &&
        !state.isConnecting &&
        state.connectingSSID === "" &&
        !state.wifiConnected) {
        return state.lastError || "Connection failed";
    }
    return null;
}
```

### Common Error Scenarios

#### Wrong Password

**Detection methods:**

1. Quick failure (< 3 seconds from start)
2. `lastError` contains "password", "auth", or "secrets"
3. Second credential prompt with `reason: "Previous password was incorrect"`

**Handling:**
```javascript
if (prompt.reason === "Previous password was incorrect") {
    // Show error, clear password field, re-focus input
}
```

#### Network Out of Range

**Detection:**
- `lastError` contains "not-found" or "connection-attempt-failed"

#### Connection Timeout

**Detection:**
- `isConnecting` remains true for > 30 seconds

**Implementation:**
```javascript
let timeout = setTimeout(() => {
    if (currentState.isConnecting) {
        handleTimeout();
    }
}, 30000);
```

#### DHCP Failure

**Detection:**
- `wifiConnected` is true
- `wifiIP` is empty after 15+ seconds

### Error Message Translation

Map technical errors to user-friendly messages:

| lastError value | Meaning | User message |
|----------------|---------|--------------|
| `secrets-required` | Password needed | "Please enter password" |
| `authentication-failed` | Wrong password | "Incorrect password" |
| `connection-removed` | Profile deleted | "Network configuration removed" |
| `connection-attempt-failed` | Generic failure | "Failed to connect" |
| `network-not-found` | Out of range | "Network not found" |
| `(timeout)` | Timeout | "Connection timed out" |

## Credential Handling

### Secret Agent Architecture

The credential system uses a broker pattern:

```
NetworkManager -> SecretAgent -> PromptBroker -> UI -> User
                                       ^
                                       |
                                  User Response
                                       |
NetworkManager <- SecretAgent <- PromptBroker <- UI
```

### Implementing a Broker

```go
type CustomBroker struct {
    ui       UIInterface
    pending  map[string]chan network.PromptReply
}

func (b *CustomBroker) Ask(ctx context.Context, req network.PromptRequest) (string, error) {
    token := generateToken()
    b.pending[token] = make(chan network.PromptReply, 1)

    // Send to UI
    b.ui.ShowCredentialPrompt(token, req)

    return token, nil
}

func (b *CustomBroker) Wait(ctx context.Context, token string) (network.PromptReply, error) {
    select {
    case <-ctx.Done():
        return network.PromptReply{}, errors.New("timeout")
    case reply := <-b.pending[token]:
        return reply, nil
    }
}

func (b *CustomBroker) Resolve(token string, reply network.PromptReply) error {
    if ch, ok := b.pending[token]; ok {
        ch <- reply
        close(ch)
        delete(b.pending, token)
    }
    return nil
}
```

### Credential Field Types

**Personal WiFi (802-11-wireless-security):**
- Fields: `["psk"]`
- UI: Single password input

**Enterprise WiFi (802-1x):**
- Fields: `["identity", "password"]`
- UI: Username and password inputs

### Building Secrets Object

```javascript
function buildSecrets(setting, fields, formData) {
    let secrets = {};

    if (setting === "802-11-wireless-security") {
        secrets.psk = formData.password;
    } else if (setting === "802-1x") {
        secrets.identity = formData.username;
        secrets.password = formData.password;
    }

    return secrets;
}
```

## Best Practices

### Track Target Network

Always store which network you're connecting to:

```javascript
let targetSSID = null;

function connect(ssid) {
    targetSSID = ssid;
    // send request
}

function onStateUpdate(state) {
    if (!targetSSID) return;

    if (state.wifiSSID === targetSSID && state.wifiConnected && state.wifiIP) {
        // Success for the network we care about
        targetSSID = null;
    }
}
```

### Implement Timeouts

Never wait indefinitely for a connection:

```javascript
const CONNECTION_TIMEOUT = 30000; // 30 seconds
const DHCP_TIMEOUT = 15000;       // 15 seconds

let timer = setTimeout(() => {
    if (stillConnecting) {
        handleTimeout();
    }
}, CONNECTION_TIMEOUT);
```

### Handle Credential Re-prompts

Wrong passwords trigger a second prompt:

```javascript
function onCredentialPrompt(prompt) {
    if (prompt.reason.includes("incorrect")) {
        // Show error, but keep dialog open
        showError("Wrong password");
        clearPasswordField();
    } else {
        // First time prompt
        showDialog(prompt);
    }
}
```

### Clean Up State

Reset tracking variables on success, failure, or cancellation:

```javascript
function cleanup() {
    clearTimeout(timer);
    targetSSID = null;
    closeDialogs();
}
```

### Subscribe to Both Services

Missing `network.credentials` means prompts won't arrive:

```javascript
// Correct
services: ["network", "network.credentials"]

// Wrong - will miss credential prompts
services: ["network"]
```

## Testing

### Connection Test Checklist

- [ ] Connect to open network
- [ ] Connect to WPA2 network with password provided
- [ ] Connect to WPA2 network without password (triggers prompt)
- [ ] Enter wrong password (verify error and re-prompt)
- [ ] Cancel credential prompt
- [ ] Connection timeout after 30 seconds
- [ ] DHCP timeout detection
- [ ] Network out of range
- [ ] Reconnect to already-configured network

### Verifying Secret Agent Setup

Check connection profile flags:
```bash
nmcli connection show "NetworkName" | grep flags
# Should show: 802-11-wireless-security.psk-flags: 1 (agent-owned)
```

Check agent registration in logs:
```
INFO: Registered with NetworkManager as secret agent
```

## Security

- Never log credential values (passwords, PSKs)
- Clear password fields when dialogs close
- Implement prompt timeouts (default: 2 minutes)
- Validate user input before submission
- Use secure channels for credential transmission

## Troubleshooting

### Credential prompt doesn't appear

**Check:**
- Subscribed to both `network` and `network.credentials`
- Connection has `interactive: true`
- Secret flags set to AGENT_OWNED (value: 1)
- Broker registered successfully

### Connection succeeds without prompting

**Cause:** NetworkManager found saved credentials

**Solution:** Delete existing connection first, or use different credentials

### State updates seem delayed

**Expected behavior:** State changes occur in rapid succession during connection

**Solution:** Debounce UI updates; only act on final state

### Multiple rapid credential prompts

**Cause:** Connection profile has incorrect flags or conflicting agents

**Solution:**
- Check only one agent is running
- Verify psk-flags value
- Check NetworkManager logs for agent conflicts

## Data Structures Reference

### PromptRequest
```go
type PromptRequest struct {
    SSID        string   `json:"ssid"`
    SettingName string   `json:"setting"`
    Fields      []string `json:"fields"`
    Hints       []string `json:"hints"`
    Reason      string   `json:"reason"`
}
```

### PromptReply
```go
type PromptReply struct {
    Secrets map[string]string `json:"secrets"`
    Save    bool              `json:"save"`
    Cancel  bool              `json:"cancel"`
}
```

### NetworkState
```go
type NetworkState struct {
    NetworkStatus  string `json:"networkStatus"`
    IsConnecting   bool   `json:"isConnecting"`
    ConnectingSSID string `json:"connectingSSID"`
    WifiConnected  bool   `json:"wifiConnected"`
    WifiSSID       string `json:"wifiSSID"`
    WifiIP         string `json:"wifiIP"`
    LastError      string `json:"lastError"`
}
```
