import QtQuick
import qs.Common
import qs.Services
import qs.Modules.ControlCenter.Widgets
import qs.Modules.ControlCenter.Details
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property bool vpnActivating: DMSNetworkService.vpnIsBusy || DMSNetworkService.activeState === "activating"
    readonly property bool vpnActivated: DMSNetworkService.connected && DMSNetworkService.activeState === "activated"

    ccWidgetIcon: "vpn_key"
    ccWidgetPrimaryText: I18n.tr("VPN", "virtual private network, widget and page title")
    ccWidgetSecondaryText: {
        if (vpnActivating)
            return I18n.tr("Connecting...");
        if (!vpnActivated)
            return I18n.tr("Disconnected");
        const names = DMSNetworkService.activeNames || [];
        if (names.length <= 1)
            return names[0] || I18n.tr("Connected");
        return names[0] + " +" + (names.length - 1);
    }
    ccWidgetIsActive: vpnActivated

    onCcWidgetToggled: DMSNetworkService.toggleVpn()

    ccDetailContent: Component {
        VpnDetailContent {}
    }
    ccExpandedContent: Component {
        CcTileActions {
            actions: DMSNetworkService.profiles.map(profile => ({
                        text: profile.name,
                        icon: "vpn_key",
                        toggle: true,
                        active: DMSNetworkService.vpnStateForUuid(profile.uuid) === "activated",
                        enabled: !DMSNetworkService.isVpnConnectingUuid(profile.uuid),
                        trigger: () => DMSNetworkService.toggle(profile.uuid)
                    }))
        }
    }
}
