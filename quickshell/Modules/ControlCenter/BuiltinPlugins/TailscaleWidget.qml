import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    Ref {
        service: TailscaleService
    }

    ccWidgetIcon: "device_hub"
    ccWidgetPrimaryText: I18n.tr("Tailscale", "Tailscale mesh VPN widget title")
    ccWidgetSecondaryText: {
        if (!TailscaleService.available)
            return I18n.tr("Not available", "Tailscale service not available");
        if (!TailscaleService.connected)
            return I18n.tr("Disconnected", "Tailscale disconnected status");
        const count = TailscaleService.onlinePeerCount;
        return I18n.tr("%1 online", "Number of online Tailscale peers").arg(count);
    }
    ccWidgetIsActive: TailscaleService.connected

    onCcWidgetToggled: {
        if (!TailscaleService.available)
            return;
        if (TailscaleService.connected)
            TailscaleService.disconnectTailscale(null);
        else
            TailscaleService.connectTailscale(null);
    }

    onCcWidgetExpanded: {
        TailscaleService.refresh(null);
    }

    ccDetailContent: Component {
        Item {
            id: detailRoot

            property string searchQuery: ""
            property int filterIndex: 0
            property string expandedHostname: ""

            function formatLastSeen(iso) {
                const date = new Date(iso);
                const minutes = Math.floor((Date.now() - date.getTime()) / 60000);
                if (minutes < 60)
                    return I18n.tr("%1m ago", "Tailscale peer last seen time, %1 is a number of minutes").arg(Math.max(1, minutes));
                const hours = Math.floor(minutes / 60);
                if (hours < 24)
                    return I18n.tr("%1h ago", "Tailscale peer last seen time, %1 is a number of hours").arg(hours);
                return I18n.tr("%1d ago", "Tailscale peer last seen time, %1 is a number of days").arg(Math.floor(hours / 24));
            }

            readonly property string title: I18n.tr("Tailscale", "Tailscale mesh VPN widget title")
            readonly property string noneLabel: I18n.tr("None", "Tailscale exit node: none selected")
            readonly property var filteredPeers: {
                let base;
                switch (filterIndex) {
                case 0:
                    base = TailscaleService.myOnlinePeers;
                    break;
                case 1:
                    base = TailscaleService.onlinePeers;
                    break;
                case 2:
                    base = TailscaleService.allPeersList;
                    break;
                default:
                    base = [];
                }
                if (searchQuery.length > 0)
                    return TailscaleService.searchPeers(searchQuery, base);
                return base;
            }

            readonly property Item headerActions: DActionButton {
                buttonSize: Theme.iconButtonSize
                iconSize: Theme.iconSize
                iconName: "sync"
                iconColor: Theme.surfaceText
                Accessible.name: I18n.tr("Refresh", "Refresh Tailscale device status")
                onClicked: TailscaleService.refresh(null)
            }

            DFlickable {
                anchors.fill: parent
                contentHeight: detailColumn.height
                clip: true

                Column {
                    id: detailColumn
                    width: parent.width
                    spacing: CcMetrics.detailContentGap

                    CcEmptyState {
                        visible: !TailscaleService.available
                        iconName: "vpn_key_off"
                        title: I18n.tr("Tailscale not available", "Warning when Tailscale service is not running")
                    }

                    CcGroup {
                        visible: TailscaleService.available

                        CcToggleRow {
                            iconName: "device_hub"
                            iconColor: TailscaleService.connected ? Theme.primary : Theme.surfaceText
                            text: TailscaleService.connected ? I18n.tr("Connected", "Tailscale connection status: connected") : I18n.tr("Disconnected", "Tailscale connection status: disconnected")
                            description: TailscaleService.connected ? TailscaleService.tailnetName : ""
                            checked: TailscaleService.connected
                            onToggled: checked => {
                                if (checked)
                                    TailscaleService.connectTailscale(null);
                                else
                                    TailscaleService.disconnectTailscale(null);
                            }
                        }

                        CcListRow {
                            visible: TailscaleService.connected
                            iconName: "alt_route"
                            title: I18n.tr("Exit node", "Tailscale exit node selector label")

                            DDropdown {
                                anchors.verticalCenter: parent.verticalCenter
                                compactMode: true
                                dropdownWidth: CcMetrics.rowDropdownWidth
                                alignPopupRight: true
                                currentValue: TailscaleService.currentExitNode ? TailscaleService.currentExitNode.hostname : detailRoot.noneLabel
                                options: [detailRoot.noneLabel].concat(TailscaleService.exitNodeOptions.map(p => p.hostname))
                                onValueChanged: value => {
                                    if (value === detailRoot.noneLabel) {
                                        TailscaleService.clearExitNode(null);
                                        return;
                                    }
                                    const peer = TailscaleService.exitNodeOptions.find(p => p.hostname === value);
                                    if (peer)
                                        TailscaleService.setExitNode(peer.id, null);
                                }
                            }
                        }

                        CcToggleRow {
                            visible: TailscaleService.connected && TailscaleService.currentExitNode !== null
                            iconName: "lan"
                            text: I18n.tr("Allow LAN access", "Tailscale allow LAN access toggle")
                            description: I18n.tr("Reach local network devices while using an exit node", "Tailscale allow LAN access description")
                            checked: TailscaleService.exitNodeAllowLanAccess
                            onToggled: value => TailscaleService.setAllowLanAccess(value, null)
                        }
                    }

                    DSearchField {
                        width: parent.width
                        visible: TailscaleService.available
                        placeholderText: I18n.tr("Search devices...", "Tailscale device search placeholder")
                        text: detailRoot.searchQuery
                        onTextEdited: detailRoot.searchQuery = text
                    }

                    DFilterChips {
                        width: parent.width
                        visible: TailscaleService.available
                        currentIndex: detailRoot.filterIndex
                        showCounts: true
                        model: [
                            {
                                "label": I18n.tr("My Online", "Tailscale filter: my online devices"),
                                "count": TailscaleService.myOnlinePeers.length
                            },
                            {
                                "label": I18n.tr("Online", "Tailscale filter: all online devices"),
                                "count": TailscaleService.onlinePeers.length
                            },
                            {
                                "label": I18n.tr("All", "Tailscale filter: all devices"),
                                "count": TailscaleService.allPeersList.length
                            }
                        ]
                        onSelectionChanged: index => detailRoot.filterIndex = index
                    }

                    CcEmptyState {
                        visible: TailscaleService.available && detailRoot.filteredPeers.length === 0
                        iconName: "devices"
                        title: detailRoot.searchQuery.length > 0 ? I18n.tr("No matching devices", "No Tailscale devices match search") : I18n.tr("No peers found", "No Tailscale peers found")
                    }

                    CcGroup {
                        visible: TailscaleService.available && detailRoot.filteredPeers.length > 0

                        Repeater {
                            model: detailRoot.filteredPeers

                            CcListRow {
                                id: peerRow

                                required property var modelData

                                readonly property bool isSelf: modelData.hostname === (TailscaleService.selfNode ? TailscaleService.selfNode.hostname : "")
                                readonly property bool isExpanded: detailRoot.expandedHostname === modelData.hostname

                                active: isSelf
                                title: modelData.hostname || ""
                                subtitle: {
                                    const parts = [];
                                    if (modelData.tailscaleIp)
                                        parts.push(modelData.tailscaleIp);
                                    if (modelData.os)
                                        parts.push(modelData.os);
                                    if (modelData.online)
                                        parts.push(modelData.relay ? I18n.tr("relay: %1", "Tailscale relay server name").arg(modelData.relay) : I18n.tr("direct", "Tailscale direct connection"));
                                    else if (modelData.lastSeen)
                                        parts.push(I18n.tr("last seen %1", "Tailscale peer last seen time").arg(detailRoot.formatLastSeen(modelData.lastSeen)));
                                    return parts.join(" • ");
                                }
                                trailingBadge: isSelf ? I18n.tr("This device", "Label for the user's own device in Tailscale") : ""
                                trailingBadgeColor: Theme.primary
                                clickable: true
                                onClicked: detailRoot.expandedHostname = isExpanded ? "" : modelData.hostname

                                leading: CcStatusDot {
                                    color: peerRow.modelData.online ? Theme.success : Theme.surfaceVariantText
                                }

                                DActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    buttonSize: Theme.buttonHeightXS
                                    iconSize: Theme.iconSizeSmall
                                    iconName: "content_copy"
                                    iconColor: Theme.surfaceText
                                    Accessible.name: I18n.tr("Copy", "Copy to clipboard")
                                    onClicked: Quickshell.execDetached(["dms", "cl", "copy", peerRow.modelData.tailscaleIp])
                                }

                                body: Column {
                                    width: parent.width
                                    spacing: Theme.spacingXS
                                    visible: peerRow.isExpanded

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingXS
                                        visible: (peerRow.modelData.dnsName || "").length > 0

                                        StyledText {
                                            width: parent.width - copyDnsButton.width - parent.spacing
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: peerRow.modelData.dnsName || ""
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            elide: Text.ElideRight
                                        }

                                        DActionButton {
                                            id: copyDnsButton
                                            anchors.verticalCenter: parent.verticalCenter
                                            buttonSize: Theme.buttonHeightXS
                                            iconSize: Theme.iconSizeSmall
                                            iconName: "content_copy"
                                            Accessible.name: I18n.tr("Copy")
                                            iconColor: Theme.surfaceText
                                            onClicked: Quickshell.execDetached(["dms", "cl", "copy", peerRow.modelData.dnsName])
                                        }
                                    }

                                    StyledText {
                                        width: parent.width
                                        visible: (peerRow.modelData.tags || []).length > 0
                                        text: I18n.tr("Tags: %1", "Tailscale device tags").arg((peerRow.modelData.tags || []).join(", "))
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        width: parent.width
                                        visible: (peerRow.modelData.owner || "").length > 0
                                        text: I18n.tr("Owner: %1", "Tailscale device owner").arg(peerRow.modelData.owner || "")
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ccExpandedContent: Component {
        CcTileActions {
            actions: [
                {
                    text: I18n.tr("None", "Tailscale exit node: none selected"),
                    icon: "alt_route",
                    active: TailscaleService.currentExitNode === null,
                    enabled: TailscaleService.connected,
                    trigger: () => TailscaleService.clearExitNode(null)
                }
            ].concat(TailscaleService.exitNodeOptions.map(peer => ({
                        text: peer.hostname,
                        icon: "alt_route",
                        active: TailscaleService.currentExitNode?.id === peer.id,
                        enabled: TailscaleService.connected,
                        trigger: () => TailscaleService.setExitNode(peer.id, null)
                    })))
        }
    }
}
