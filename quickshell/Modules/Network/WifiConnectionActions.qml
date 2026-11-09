pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import qs.Services

Singleton {
    id: root

    readonly property int signalBucket: 25

    // Signal is compared in steps of signalBucket so small changes between scans don't reorder rows.
    function sortNetworks(networks, currentSsid, pinnedList, rank) {
        const sorted = [...(networks || [])];
        sorted.sort((a, b) => {
            const aPinnedIndex = pinnedList.indexOf(a.ssid);
            const bPinnedIndex = pinnedList.indexOf(b.ssid);
            if (aPinnedIndex !== -1 || bPinnedIndex !== -1) {
                if (aPinnedIndex === -1)
                    return 1;
                if (bPinnedIndex === -1)
                    return -1;
                return aPinnedIndex - bPinnedIndex;
            }
            if (a.ssid === currentSsid)
                return -1;
            if (b.ssid === currentSsid)
                return 1;
            const aRank = rank(a);
            const bRank = rank(b);
            if (aRank !== bRank)
                return aRank - bRank;
            const aBucket = Math.floor((a.signal || 0) / root.signalBucket);
            const bBucket = Math.floor((b.signal || 0) / root.signalBucket);
            if (aBucket !== bBucket)
                return bBucket - aBucket;
            return (a.ssid || "").localeCompare(b.ssid || "");
        });
        return sorted;
    }

    function connectToNetwork(network, options) {
        if (!network)
            return;

        const actionOptions = options || {};
        const ssid = network.ssid || "";
        if (!ssid)
            return;

        const connected = actionOptions.connected ?? network.connected ?? (ssid === NetworkService.currentWifiSSID);
        if (connected) {
            if (actionOptions.disconnectWhenConnected ?? false)
                NetworkService.disconnectWifi();
            return;
        }

        if (shouldPromptForCredentials(network)) {
            if (typeof actionOptions.promptCredentials === "function")
                actionOptions.promptCredentials(ssid);
            else
                PopoutService.showWifiPasswordModal(ssid);
            return;
        }

        NetworkService.connectToWifi(ssid);
    }

    function connectToNetworkFromDetails(ssid, secured, saved, enterprise, connected, options) {
        connectToNetwork({
            ssid: ssid,
            secured: secured,
            saved: saved,
            enterprise: enterprise,
            connected: connected
        }, options);
    }

    function shouldPromptForCredentials(network) {
        return (network.secured ?? false) && !(network.saved ?? false);
    }
}
