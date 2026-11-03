import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

DOSD {
    id: root

    osdKind: "touchpad"

    osdWidth: Theme.osdHeight
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    Connections {
        target: NiriService

        function onTouchpadToggled() {
            if (!SettingsData.osdTouchpadEnabled)
                return;
            root.show();
        }
    }

    content: Item {
        OsdIcon {
            tonal: false
            anchors.centerIn: parent
            iconName: NiriService.touchpadEnabled ? "touchpad_mouse" : "touchpad_mouse_off"
            iconColor: NiriService.touchpadEnabled ? Theme.primary : Theme.outline
        }
    }
}
