pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: networkEthernetTab

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

            property string expandedEthDevice: ""

            settingKey: "networkEthernet"
            tags: ["ethernet", "wired", "network", "adapters", "connection"]

            width: parent.width

            SettingsRow {
                body: Column {
                    id: ethernetSection

                    width: parent.width
                    spacing: Theme.spacingM

                    StyledText {
                        text: {
                            const devices = NetworkService.ethernetDevices;
                            const connected = devices.filter(d => d.connected).length;
                            if (devices.length === 0)
                                return I18n.tr("No adapters");
                            if (connected === 0)
                                return devices.length === 1 ? I18n.tr("%1 adapter, none connected", "singular, ethernet summary, %1 is 1").arg(devices.length) : I18n.tr("%1 adapters, none connected", "plural, ethernet summary, %1 is a count").arg(devices.length);
                            return I18n.tr("%1 connected", "network adapter summary, %1 is a count of connected adapters").arg(connected);
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        color: NetworkService.ethernetConnected ? Theme.primary : Theme.surfaceVariantText
                        width: parent.width
                        horizontalAlignment: Text.AlignLeft
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: NetworkService.ethernetDevices.length > 0

                        StyledText {
                            text: I18n.tr("Adapters", "noun plural, network adapter list heading")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                            width: parent.width
                            horizontalAlignment: Text.AlignLeft
                        }

                        Repeater {
                            model: NetworkService.ethernetDevices

                            delegate: Rectangle {
                                id: ethDeviceDelegate
                                required property var modelData
                                required property int index

                                readonly property bool isConnected: modelData.connected || false
                                readonly property bool isExpanded: root.expandedEthDevice === modelData.name

                                width: parent.width
                                height: isExpanded ? 56 + ethExpandedContent.height : 56
                                radius: Theme.cornerRadius
                                color: isConnected ? Theme.selectedContainer : SettingsMetrics.controlColor
                                border.width: Theme.layerOutlineWidth
                                border.color: Theme.outlineMedium
                                clip: true

                                Column {
                                    anchors.fill: parent
                                    spacing: 0

                                    Item {
                                        width: parent.width
                                        height: 56

                                        Row {
                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.right: ethDeviceActions.left
                                            anchors.rightMargin: Theme.spacingS
                                            spacing: Theme.spacingS

                                            DIcon {
                                                name: "lan"
                                                size: 20
                                                color: isConnected ? Theme.accentOnSelectedContainer : Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: Theme.spacingXXS
                                                width: parent.width - 20 - Theme.spacingS

                                                StyledText {
                                                    text: modelData.name || I18n.tr("Unknown")
                                                    font.pixelSize: Theme.fontSizeMedium
                                                    color: isConnected ? Theme.onSelectedContainer : Theme.surfaceText
                                                    font.weight: Theme.fontWeightMedium
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                    horizontalAlignment: Text.AlignLeft
                                                }

                                                Row {
                                                    anchors.left: parent.left
                                                    spacing: Theme.spacingXS

                                                    StyledText {
                                                        text: {
                                                            switch (modelData.state) {
                                                            case "activated":
                                                                return I18n.tr("Connected");
                                                            case "disconnected":
                                                                return I18n.tr("Disconnected");
                                                            case "unavailable":
                                                                return I18n.tr("Unavailable");
                                                            default:
                                                                return modelData.state || I18n.tr("Unknown");
                                                            }
                                                        }
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        color: isConnected ? Theme.onSelectedContainer : Theme.surfaceVariantText
                                                    }

                                                    StyledText {
                                                        text: "•"
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        color: Theme.surfaceVariantText
                                                        visible: (modelData.ip || "").length > 0
                                                    }

                                                    StyledText {
                                                        text: modelData.ip || ""
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        color: Theme.surfaceVariantText
                                                        visible: (modelData.ip || "").length > 0
                                                    }
                                                }
                                            }
                                        }

                                        Row {
                                            id: ethDeviceActions
                                            anchors.right: parent.right
                                            anchors.rightMargin: Theme.spacingS
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Theme.spacingXS

                                            DActionButton {
                                                buttonSize: Theme.buttonHeightXXS
                                                iconName: isExpanded ? "expand_less" : "expand_more"
                                                iconColor: Theme.surfaceText
                                                tooltipText: isExpanded ? I18n.tr("Collapse") : I18n.tr("Expand")
                                                visible: isConnected
                                                onClicked: {
                                                    if (isExpanded) {
                                                        root.expandedEthDevice = "";
                                                    } else {
                                                        root.expandedEthDevice = modelData.name;
                                                        NetworkService.fetchWiredNetworkInfo(NetworkService.ethernetConnectionUuid);
                                                    }
                                                }
                                            }

                                            DActionButton {
                                                buttonSize: Theme.buttonHeightXXS
                                                iconName: "link_off"
                                                iconColor: Theme.surfaceVariantText
                                                stateColor: Theme.error
                                                tooltipText: I18n.tr("Disconnect")
                                                visible: isConnected
                                                onClicked: NetworkService.disconnectEthernetDevice(modelData.name)
                                            }
                                        }
                                    }

                                    Column {
                                        id: ethExpandedContent
                                        width: parent.width
                                        visible: isExpanded

                                        Item {
                                            width: parent.width
                                            height: ethDetailsColumn.implicitHeight + Theme.spacingM * 2

                                            Column {
                                                id: ethDetailsColumn
                                                anchors.fill: parent
                                                anchors.margins: Theme.spacingM
                                                spacing: Theme.spacingS

                                                Flow {
                                                    width: parent.width
                                                    spacing: Theme.spacingXS

                                                    Repeater {
                                                        model: {
                                                            const fields = [];
                                                            const dev = modelData;
                                                            if (!dev)
                                                                return fields;

                                                            if (dev.ip)
                                                                fields.push({
                                                                    label: "IP",
                                                                    value: dev.ip
                                                                });
                                                            if (dev.speed && dev.speed > 0)
                                                                fields.push({
                                                                    label: I18n.tr("Speed", "noun, ethernet link speed detail label"),
                                                                    value: dev.speed + " Mbps"
                                                                });
                                                            if (dev.hwAddress)
                                                                fields.push({
                                                                    label: "MAC",
                                                                    value: dev.hwAddress
                                                                });
                                                            if (dev.driver)
                                                                fields.push({
                                                                    label: I18n.tr("Driver"),
                                                                    value: dev.driver
                                                                });
                                                            fields.push({
                                                                label: I18n.tr("State"),
                                                                value: dev.state || I18n.tr("Unknown")
                                                            });

                                                            return fields;
                                                        }

                                                        delegate: DDetailChip {
                                                            required property var modelData

                                                            label: modelData.label
                                                            value: modelData.value
                                                        }
                                                    }
                                                }

                                                Item {
                                                    width: parent.width
                                                    height: NetworkService.networkWiredInfoLoading ? 40 : 0
                                                    visible: NetworkService.networkWiredInfoLoading

                                                    DSpinner {
                                                        anchors.centerIn: parent
                                                        size: 20
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: NetworkService.wiredConnections.length > 0

                        StyledText {
                            text: I18n.tr("Saved configurations")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                            width: parent.width
                            horizontalAlignment: Text.AlignLeft
                        }

                        Repeater {
                            model: NetworkService.wiredConnections

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                width: parent.width
                                height: 48
                                radius: Theme.cornerRadius
                                color: modelData.isActive ? Theme.selectedContainer : wiredMouseArea.containsMouse ? Theme.primaryHoverLight : SettingsMetrics.controlColor
                                border.width: Theme.layerOutlineWidth
                                border.color: Theme.outlineMedium

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingS

                                    DIcon {
                                        name: "lan"
                                        size: 20
                                        color: modelData.isActive ? Theme.accentOnSelectedContainer : Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingXXS

                                        StyledText {
                                            text: modelData.id || I18n.tr("Unknown")
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: modelData.isActive ? Theme.onSelectedContainer : Theme.surfaceText
                                            font.weight: Theme.fontWeightMedium
                                        }

                                        StyledText {
                                            text: modelData.isActive ? I18n.tr("Active") : ""
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.onSelectedContainer
                                            visible: modelData.isActive
                                        }
                                    }
                                }

                                MouseArea {
                                    id: wiredMouseArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!modelData.isActive) {
                                            NetworkService.connectToSpecificWiredConfig(modelData.uuid);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
