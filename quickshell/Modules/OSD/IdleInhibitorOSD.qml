import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

DOSD {
    id: root

    osdKind: "idleInhibitor"

    osdWidth: Theme.osdHeight
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    Connections {
        target: SessionService
        function onInhibitorChanged() {
            if (SettingsData.osdIdleInhibitorEnabled) {
                root.show();
            }
        }
    }

    content: Item {
        OsdIcon {
            tonal: false
            anchors.centerIn: parent
            iconName: "local_cafe"
            iconColor: SessionService.idleInhibited ? Theme.primary : Theme.outline
            filled: SessionService.idleInhibited
        }
    }
}
