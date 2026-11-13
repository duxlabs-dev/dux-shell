import QtQuick
import qs.Common
import qs.Services

IconOSD {
    id: root

    osdKind: "touchpad"
    iconName: NiriService.touchpadEnabled ? "touchpad_mouse" : "touchpad_mouse_off"
    iconColor: NiriService.touchpadEnabled ? Theme.primary : Theme.outline

    Connections {
        target: NiriService

        function onTouchpadToggled() {
            if (!SettingsData.osdTouchpadEnabled)
                return;
            root.show();
        }
    }
}
