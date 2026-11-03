pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: networkCellularTab

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Component.onCompleted: NetworkService.addRef()
    Component.onDestruction: NetworkService.removeRef()

    SettingsPage {
        id: mainColumn

        SettingsCard {
            id: root

            settingKey: "networkCellular"
            tags: ["cellular", "mobile", "modem", "wwan", "lte", "gsm", "cdma", "network"]
            width: parent.width

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledText {
                            text: {
                                if (!NetworkService.cellularHardwareEnabled)
                                    return I18n.tr("Unavailable");
                                if (NetworkService.cellularToggling)
                                    return NetworkService.cellularEnabled ? I18n.tr("Disabling cellular...") : I18n.tr("Enabling cellular...");
                                if (!NetworkService.cellularEnabled)
                                    return I18n.tr("Disabled");
                                const devices = NetworkService.cellularDevices || [];
                                const connected = devices.filter(d => d.connected).length;
                                if (devices.length === 0)
                                    return I18n.tr("No devices found");
                                if (connected === 0)
                                    return I18n.tr("Disconnected");
                                return I18n.tr("%1 connected").arg(connected);
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: NetworkService.cellularConnected ? Theme.primary : Theme.surfaceVariantText
                            width: parent.width - cellularControls.width - Theme.spacingM
                            horizontalAlignment: Text.AlignLeft
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Row {
                            id: cellularControls
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DToggle {
                                checked: NetworkService.cellularEnabled
                                enabled: NetworkService.cellularHardwareEnabled && !NetworkService.cellularToggling
                                onToggled: NetworkService.toggleCellularRadio()
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: NetworkService.cellularEnabled && (NetworkService.cellularDevices?.length ?? 0) > 0

                        StyledText {
                            text: I18n.tr("Adapters")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                            width: parent.width
                            horizontalAlignment: Text.AlignLeft
                        }

                        Repeater {
                            model: NetworkService.cellularDevices || []

                            delegate: Rectangle {
                                id: modemDelegate
                                required property var modelData

                                readonly property bool isConnected: modelData.connected || false

                                width: parent.width
                                height: 56
                                radius: Theme.cornerRadius
                                color: isConnected ? Theme.selectedContainer : modemMouseArea.containsMouse ? Theme.primaryHoverLight : SettingsMetrics.controlColor
                                border.width: Theme.layerOutlineWidth
                                border.color: Theme.outlineMedium

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.right: modemActions.left
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingS

                                    DIcon {
                                        name: "network_cell"
                                        size: 20
                                        color: modemDelegate.isConnected ? Theme.accentOnSelectedContainer : Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingXXS
                                        width: parent.width - 20 - Theme.spacingS

                                        StyledText {
                                            text: modelData.name || I18n.tr("Unknown")
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: modemDelegate.isConnected ? Theme.onSelectedContainer : Theme.surfaceText
                                            font.weight: Theme.fontWeightMedium
                                            elide: Text.ElideRight
                                            width: parent.width
                                            horizontalAlignment: Text.AlignLeft
                                        }

                                        StyledText {
                                            text: {
                                                const state = modelData.state || I18n.tr("Unknown");
                                                const ip = modelData.ip || "";
                                                return ip.length > 0 ? state + " • " + ip : state;
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            elide: Text.ElideRight
                                            width: parent.width
                                            horizontalAlignment: Text.AlignLeft
                                        }
                                    }
                                }

                                Row {
                                    id: modemActions
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS

                                    DActionButton {
                                        buttonSize: Theme.buttonHeightXXS
                                        iconName: modemDelegate.isConnected ? "link_off" : "link"
                                        iconColor: Theme.surfaceVariantText
                                        stateColor: modemDelegate.isConnected ? Theme.error : Theme.primary
                                        tooltipText: modemDelegate.isConnected ? I18n.tr("Disconnect") : I18n.tr("Connect")
                                        onClicked: {
                                            if (modemDelegate.isConnected)
                                                NetworkService.disconnectCellularDevice(modelData.name);
                                            else
                                                NetworkService.connectCellular();
                                        }
                                    }
                                }

                                MouseArea {
                                    id: modemMouseArea
                                    anchors.fill: parent
                                    anchors.rightMargin: modemActions.width + Theme.spacingM
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modemDelegate.isConnected)
                                            NetworkService.disconnectCellularDevice(modelData.name);
                                        else
                                            NetworkService.connectCellular();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Saved configurations")
            iconName: "sim_card"
            settingKey: "networkCellularProfiles"
            tags: ["cellular", "mobile", "profile", "apn", "sim"]
            width: parent.width
            visible: NetworkService.cellularEnabled && (NetworkService.cellularConnections?.length ?? 0) > 0

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: NetworkService.cellularConnections || []

                        delegate: Rectangle {
                            id: profileDelegate
                            required property var modelData

                            readonly property bool isActive: modelData.isActive || false

                            width: parent.width
                            height: 56
                            radius: Theme.cornerRadius
                            color: isActive ? Theme.selectedContainer : profileMouseArea.containsMouse ? Theme.primaryHoverLight : SettingsMetrics.controlColor
                            border.color: Theme.outlineMedium
                            border.width: Theme.layerOutlineWidth

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.right: profileAction.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

                                DIcon {
                                    name: "sim_card"
                                    size: 20
                                    color: profileDelegate.isActive ? Theme.accentOnSelectedContainer : Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 20 - Theme.spacingS
                                    spacing: Theme.spacingXXS

                                    StyledText {
                                        text: modelData.id || I18n.tr("Unknown")
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: profileDelegate.isActive ? Theme.onSelectedContainer : Theme.surfaceText
                                        font.weight: Theme.fontWeightMedium
                                        elide: Text.ElideRight
                                        width: parent.width
                                        horizontalAlignment: Text.AlignLeft
                                    }

                                    StyledText {
                                        text: profileDelegate.isActive ? I18n.tr("Connected") : (modelData.type || I18n.tr("Available"))
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        width: parent.width
                                        horizontalAlignment: Text.AlignLeft
                                    }
                                }
                            }

                            DActionButton {
                                id: profileAction
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: profileDelegate.isActive ? "link_off" : "link"
                                tooltipText: profileDelegate.isActive ? I18n.tr("Disconnect") : I18n.tr("Connect")
                                iconSize: Theme.iconSizeSmall
                                iconColor: profileDelegate.isActive ? Theme.error : Theme.primary
                                onClicked: {
                                    if (profileDelegate.isActive)
                                        NetworkService.toggleNetworkConnection("cellular");
                                    else
                                        NetworkService.connectToSpecificCellularConfig(modelData.uuid);
                                }
                            }

                            MouseArea {
                                id: profileMouseArea
                                anchors.fill: parent
                                anchors.rightMargin: profileAction.width + Theme.spacingS
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!profileDelegate.isActive)
                                        NetworkService.connectToSpecificCellularConfig(modelData.uuid);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
