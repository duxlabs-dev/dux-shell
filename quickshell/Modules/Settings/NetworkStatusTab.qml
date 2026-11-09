pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: networkStatusTab

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Component.onCompleted: {
        NetworkService.addRef();
    }

    Component.onDestruction: {
        NetworkService.removeRef();
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            id: root

            settingKey: "networkStatus"
            tags: ["status", "network", "connectivity", "internet"]

            width: parent.width

            SettingsRow {
                body: Column {
                    id: overviewSection

                    width: parent.width
                    spacing: Theme.spacingM

                    Grid {
                        columns: 2
                        columnSpacing: Theme.spacingL
                        rowSpacing: Theme.spacingS
                        width: parent.width

                        StyledText {
                            text: I18n.tr("Backend")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                        }
                        StyledText {
                            text: NetworkService.backend || I18n.tr("Unknown")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            font.weight: Theme.fontWeightMedium
                        }

                        StyledText {
                            text: I18n.tr("Status")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                        }
                        Row {
                            spacing: Theme.spacingS

                            Rectangle {
                                width: Theme.spacingS
                                height: Theme.spacingS
                                radius: Theme.fullRadius(width, height)
                                anchors.verticalCenter: parent.verticalCenter
                                color: {
                                    switch (NetworkService.networkStatus) {
                                    case "ethernet":
                                    case "wifi":
                                    case "cellular":
                                        return Theme.success;
                                    case "disconnected":
                                        return Theme.error;
                                    default:
                                        return Theme.warning;
                                    }
                                }
                            }

                            StyledText {
                                text: {
                                    switch (NetworkService.networkStatus) {
                                    case "ethernet":
                                        return I18n.tr("Ethernet");
                                    case "wifi":
                                        return I18n.tr("Wi-Fi", "wireless network, page and section title");
                                    case "cellular":
                                        return I18n.tr("Cellular");
                                    case "disconnected":
                                        return I18n.tr("Disconnected");
                                    default:
                                        return NetworkService.networkStatus || I18n.tr("Unknown");
                                    }
                                }
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                font.weight: Theme.fontWeightMedium
                            }
                        }

                        StyledText {
                            text: I18n.tr("Primary", "primary network connection label", true)
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            visible: NetworkService.primaryConnection.length > 0
                        }
                        StyledText {
                            text: NetworkService.primaryConnection || "-"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            visible: NetworkService.primaryConnection.length > 0
                        }

                        StyledText {
                            text: I18n.tr("Internet")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            visible: internetRow.visible
                        }
                        Row {
                            id: internetRow

                            spacing: Theme.spacingS
                            visible: NetworkService.connectivitySupported && NetworkService.connectivityCheckEnabled

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: NetworkService.connectivity !== "portal"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                color: NetworkService.connectivity === "limited" ? Theme.warning : Theme.surfaceText
                                text: {
                                    switch (NetworkService.connectivity) {
                                    case "full":
                                        return I18n.tr("Connected");
                                    case "limited":
                                        return I18n.tr("Limited connectivity", "connected to a network without internet access");
                                    case "none":
                                        return I18n.tr("Disconnected");
                                    default:
                                        return I18n.tr("Unknown");
                                    }
                                }
                            }
                            DButton {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: NetworkService.connectivity === "portal"
                                text: I18n.tr("Log in to network", "captive portal: open the login page")
                                iconName: "login"
                                onClicked: NetworkService.openCaptivePortal()
                            }
                            DActionButton {
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "refresh"
                                tooltipText: I18n.tr("Refresh")
                                buttonSize: Theme.buttonHeightXS
                                onClicked: NetworkService.checkConnectivity()
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: NetworkService.backend === "networkmanager" && [NetworkService.ethernetDevices, NetworkService.wifiDevices, NetworkService.cellularDevices].filter(d => (d?.length ?? 0) > 0).length > 1

                        StyledText {
                            text: I18n.tr("Preference", "noun, which network connection type is preferred")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Item {
                            width: parent.width - preferenceLabel.width - preferenceButtons.width - Theme.spacingM * 2
                            height: 1
                        }

                        DButtonGroup {
                            id: preferenceButtons
                            arrowKeysSelect: false

                            readonly property var preferenceValues: {
                                const values = ["auto"];
                                if ((NetworkService.ethernetDevices?.length ?? 0) > 0)
                                    values.push("ethernet");
                                if ((NetworkService.wifiDevices?.length ?? 0) > 0)
                                    values.push("wifi");
                                if ((NetworkService.cellularDevices?.length ?? 0) > 0)
                                    values.push("cellular");
                                const stored = NetworkService.userPreference;
                                if (stored && !values.includes(stored))
                                    values.push(stored);
                                return values;
                            }
                            readonly property var labelsByValue: ({
                                    "auto": I18n.tr("Auto"),
                                    "ethernet": I18n.tr("Ethernet"),
                                    "wifi": I18n.tr("Wi-Fi", "wireless network, page and section title"),
                                    "cellular": I18n.tr("Cellular")
                                })

                            model: preferenceValues.map(v => labelsByValue[v] || v)
                            currentIndex: Math.max(0, preferenceValues.indexOf(NetworkService.userPreference))
                            onSelectionChanged: (index, selected) => {
                                if (!selected)
                                    return;
                                NetworkService.setNetworkPreference(preferenceValues[index] || "auto");
                            }
                        }
                    }

                    StyledText {
                        id: preferenceLabel
                        visible: false
                        text: I18n.tr("Preference")
                    }
                }
            }

            SettingsToggleRow {
                settingKey: "networkConnectivityCheck"
                tags: ["connectivity", "captive portal", "portal", "internet", "login"]
                text: I18n.tr("Connectivity checking", "NetworkManager periodically checks internet access and captive portals")
                visible: NetworkService.connectivitySupported && NetworkService.connectivityCheckAvailable
                checked: NetworkService.connectivityCheckEnabled
                onToggled: checked => NetworkService.setConnectivityCheckEnabled(checked)
            }
        }
    }
}
