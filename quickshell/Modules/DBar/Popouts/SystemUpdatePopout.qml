import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Modals
import qs.Modules.SystemUpdate
import qs.Services
import qs.Widgets

DPopout {
    id: systemUpdatePopout

    layerNamespace: "dms:system-update"
    property var parentWidget: null
    property var triggerScreen: null
    property bool _reopenAfterUpgrade: false
    readonly property bool polkitModalOpen: polkitAuthSurfaceModal.shouldBeVisible
    readonly property bool anyModalOpen: polkitModalOpen

    Ref {
        service: SystemUpdateService
    }

    Connections {
        target: PolkitService.agent
        enabled: PolkitService.polkitAvailable && systemUpdatePopout.shouldBeVisible

        function onAuthenticationRequestStarted() {
            polkitAuthSurfaceModal.open();
        }
    }

    PolkitAuthSurfaceModal {
        id: polkitAuthSurfaceModal
        parentPopout: systemUpdatePopout
    }

    backgroundInteractive: !anyModalOpen
    customKeyboardFocus: anyModalOpen ? WlrKeyboardFocus.None : null

    readonly property bool serviceIsUpgrading: SystemUpdateService.isUpgrading

    onServiceIsUpgradingChanged: {
        if (serviceIsUpgrading || !_reopenAfterUpgrade)
            return;
        _reopenAfterUpgrade = false;
        open();
    }

    popupWidth: 440
    popupHeight: 560
    triggerWidth: Theme.buttonHeightM
    positioning: ""
    screen: triggerScreen
    shouldBeVisible: false

    onBackgroundClicked: {
        if (anyModalOpen)
            return;
        close();
    }

    content: Component {
        SystemUpdatePanel {
            hostVisible: systemUpdatePopout.shouldBeVisible
            modalOpen: systemUpdatePopout.anyModalOpen
            onCloseRequested: systemUpdatePopout.close()
            onTerminalUpgradeStarted: systemUpdatePopout._reopenAfterUpgrade = SettingsData.updaterReopenAfterUpgrade
        }
    }
}
