import QtQuick
import qs.Services

IconOSD {
    id: root

    osdKind: "idleInhibitor"
    iconName: "local_cafe"
    iconColor: SessionService.idleInhibited ? Theme.primary : Theme.outline
    filled: SessionService.idleInhibited

    Connections {
        target: SessionService
        function onInhibitorChanged() {
            root.show();
        }
    }
}
