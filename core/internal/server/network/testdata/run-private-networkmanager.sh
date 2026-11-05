#!/usr/bin/env bash
# Runs synthetic VPN integration tests without touching the host bus or network.
set -euo pipefail
SCRIPT=$(realpath "$0")
if [[ ${1:-} != --inside ]]; then
    [[ $(id -u) != 0 ]] || { printf 'Run as an unprivileged user.\n' >&2; exit 1; }
    for tool in go unshare mount dbus-daemon NetworkManager nmcli ip python3 timeout; do
        command -v "$tool" >/dev/null
    done
    D=$(mktemp -d "${TMPDIR:-/tmp}/dms-private-nm.XXXXXXXX")
    # shellcheck disable=SC2329 # Invoked by the EXIT trap.
    cleanup() {
        status=$?
        if [[ $status == 0 ]]; then rm -rf "$D"; else printf 'Synthetic logs retained: %s\n' "$D" >&2; fi
    }
    trap cleanup EXIT
    cd "$(dirname "$SCRIPT")/../../../.."
    go test -race -c -o "$D/network.test" ./internal/server/network
    DMS_TEST_HOST_NET_NS=$(readlink /proc/self/ns/net)
    DMS_TEST_HOST_MNT_NS=$(readlink /proc/self/ns/mnt)
    export DMS_TEST_HOST_NET_NS DMS_TEST_HOST_MNT_NS
    timeout --kill-after=5s 180s unshare --user --map-root-user --mount --net --pid --fork --kill-child --mount-proc "$SCRIPT" --inside "$D"
    exit
fi
D=${2:?missing temporary directory}
read -r inside outside count < /proc/self/uid_map
[[ $inside == 0 && $outside != 0 && $count == 1 ]]
[[ $(readlink /proc/self/ns/net) != "${DMS_TEST_HOST_NET_NS:?}" ]]
[[ $(readlink /proc/self/ns/mnt) != "${DMS_TEST_HOST_MNT_NS:?}" ]]
mount --make-rprivate /
declare -A masked=()
for dir in /run /etc/NetworkManager /var/lib/NetworkManager; do
    mount -t tmpfs tmpfs "$dir"
    masked[$(realpath "$dir")]=1
done
for dir in /usr/lib/NetworkManager/VPN /usr/lib64/NetworkManager/VPN /usr/local/lib/NetworkManager/VPN /etc/NetworkManager/VPN; do
    target=$dir
    while [[ ! -d $target ]]; do target=$(dirname "$target"); done
    target=$(realpath "$target")
    # An absent registry needs a private ancestor before creating its directory.
    [[ $target != / && $target != /usr && $target != /etc ]] || { printf 'Cannot safely isolate %s\n' "$dir" >&2; exit 1; }
    if [[ ! ${masked[$target]:-} ]]; then
        mount -t tmpfs tmpfs "$target"
        masked[$target]=1
    fi
    mkdir -p "$dir"
done
mkdir -p /run/NetworkManager /run/empty /etc/NetworkManager/conf.d /etc/NetworkManager/system-connections
printf '%s\n' '[VPN Connection]' 'name=openconnect' 'service=org.freedesktop.NetworkManager.openconnect' 'program=/bin/false' 'supports-multiple-connections=false' > /usr/lib/NetworkManager/VPN/nm-openconnect-service.name
printf '%s\n' '[main]' 'plugins=keyfile' 'auth-polkit=false' 'dns=none' 'rc-manager=unmanaged' 'no-auto-default=*' '[connectivity]' 'enabled=false' > /etc/NetworkManager/NetworkManager.conf
printf '%s\n' '<busconfig><type>system</type><listen>unix:path=/run/test-system-bus</listen><auth>EXTERNAL</auth><policy context="default"><allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/></policy></busconfig>' > /run/private-bus.conf
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/test-system-bus
export DBUS_SESSION_BUS_ADDRESS=$DBUS_SYSTEM_BUS_ADDRESS
export DMS_TEST_NM_PRIVATE_BUS=$DBUS_SYSTEM_BUS_ADDRESS
unset DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE DISPLAY WAYLAND_DISPLAY
BUS='' NM=''
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
    [[ -z $NM ]] || kill "$NM" 2>/dev/null || true
    [[ -z $NM ]] || wait "$NM" 2>/dev/null || true
    [[ -z $BUS ]] || kill "$BUS" 2>/dev/null || true
    [[ -z $BUS ]] || wait "$BUS" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
dbus-daemon --config-file=/run/private-bus.conf --nofork --nopidfile > "$D/bus.log" 2>&1 & BUS=$!
for ((i=0; i<100; i++)); do [[ ! -S /run/test-system-bus ]] || break; sleep .05; done
[[ -S /run/test-system-bus ]]
NetworkManager --no-daemon --debug --config=/etc/NetworkManager/NetworkManager.conf --system-config-dir=/run/empty --log-level=DEBUG > "$D/nm.log" 2>&1 & NM=$!
ip link set lo up
set +e
"$D/network.test" -test.run '^TestOpenConnect.*Private' -test.v -test.timeout=150s > "$D/test.log" 2>&1
status=$?
set -e
# These files can contain only the namespaced, synthetic fixture's data.
while IFS= read -r line; do printf '%s\n' "$line"; done < "$D/test.log"
exit "$status"
