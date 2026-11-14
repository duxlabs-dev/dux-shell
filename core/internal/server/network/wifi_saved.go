package network

import "sort"

type savedWiFiProfile struct {
	Autoconnect bool
	Hidden      bool
	Secured     bool
	Enterprise  bool
	Mode        string
}

// Saved WiFi state is keyed by SSID because the UI/API accepts SSID actions.
// Multiple backend profiles for the same SSID are intentionally collapsed here.
func mergeSavedProfilesIntoWiFiNetworks(networks []WiFiNetwork, profiles map[string]savedWiFiProfile, currentSSID string, wifiConnected bool) []WiFiNetwork {
	merged := make([]WiFiNetwork, len(networks))
	for i, network := range networks {
		profile, saved := profiles[network.SSID]
		network.Connected = wifiConnected && network.SSID == currentSSID
		network.Saved = saved
		if saved {
			network.Autoconnect = profile.Autoconnect
			network.Hidden = network.Hidden || profile.Hidden
			network.Secured = network.Secured || profile.Secured
			network.Enterprise = network.Enterprise || profile.Enterprise
			if network.Mode == "" {
				network.Mode = profile.Mode
			}
		} else {
			network.Autoconnect = false
		}
		merged[i] = network
	}
	return merged
}

func wiFiNetworksBySSID(networks []WiFiNetwork, visibleOnly bool) map[string]WiFiNetwork {
	visible := make(map[string]WiFiNetwork, len(networks))
	for _, network := range networks {
		if visibleOnly && network.OutOfRange {
			continue
		}
		visible[network.SSID] = network
	}
	return visible
}

// visibleWiFiNetworks keeps the strongest in-range entry per SSID across the
// primary list and every other radio; on a tie the primary entry wins.
func visibleWiFiNetworks(primary []WiFiNetwork, primaryDevice string, devices []WiFiDevice) map[string]WiFiNetwork {
	visible := wiFiNetworksBySSID(primary, true)
	for _, device := range devices {
		if device.Name == primaryDevice {
			continue
		}
		for _, network := range device.Networks {
			if network.OutOfRange {
				continue
			}
			if existing, ok := visible[network.SSID]; !ok || network.Signal > existing.Signal {
				visible[network.SSID] = network
			}
		}
	}
	return visible
}

func refreshSavedWiFiState(networks []WiFiNetwork, profiles map[string]savedWiFiProfile, currentSSID string, wifiConnected bool) ([]WiFiNetwork, []WiFiNetwork) {
	mergedNetworks := mergeSavedProfilesIntoWiFiNetworks(networks, profiles, currentSSID, wifiConnected)
	visibleNetworks := wiFiNetworksBySSID(mergedNetworks, true)
	savedNetworks := savedWiFiNetworksFromProfiles(profiles, visibleNetworks, currentSSID, wifiConnected)
	return mergedNetworks, savedNetworks
}

func savedWiFiNetworksFromProfiles(profiles map[string]savedWiFiProfile, visible map[string]WiFiNetwork, currentSSID string, wifiConnected bool) []WiFiNetwork {
	networks := make([]WiFiNetwork, 0, len(profiles))
	for ssid, profile := range profiles {
		if network, ok := visible[ssid]; ok {
			network.Saved = true
			network.Autoconnect = profile.Autoconnect
			network.Hidden = network.Hidden || profile.Hidden
			network.Secured = network.Secured || profile.Secured
			network.Enterprise = network.Enterprise || profile.Enterprise
			network.OutOfRange = false
			if network.Mode == "" {
				network.Mode = profile.Mode
			}
			networks = append(networks, network)
			continue
		}

		isConnected := wifiConnected && ssid == currentSSID
		networks = append(networks, WiFiNetwork{
			SSID:        ssid,
			Secured:     profile.Secured,
			Enterprise:  profile.Enterprise,
			Connected:   isConnected,
			Saved:       true,
			Autoconnect: profile.Autoconnect,
			Hidden:      profile.Hidden,
			OutOfRange:  !isConnected,
			Mode:        profile.Mode,
		})
	}

	sort.Slice(networks, func(i, j int) bool {
		if networks[i].Connected && !networks[j].Connected {
			return true
		}
		if !networks[i].Connected && networks[j].Connected {
			return false
		}
		if networks[i].OutOfRange != networks[j].OutOfRange {
			return !networks[i].OutOfRange
		}
		if networks[i].Signal != networks[j].Signal {
			return networks[i].Signal > networks[j].Signal
		}
		return networks[i].SSID < networks[j].SSID
	})

	return networks
}
