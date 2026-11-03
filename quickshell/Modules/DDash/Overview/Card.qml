import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.DDash

DCard {
    id: root

    property Item focusTarget: clickable ? root : null
    property bool blocksTabNavigation: false

    activeFocusOnTab: interactive && focusTarget !== null
    showFocusRing: false
    restRadius: DashMetrics.cardRadius

    function handleKeyEvent(event) {
        return false;
    }

    Keys.onPressed: event => {
        event.accepted = false;
        if (!interactive)
            return;
        if (handleKeyEvent(event)) {
            event.accepted = true;
            return;
        }
        if (!acceptsInput)
            return;
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.clicked();
            event.accepted = true;
            break;
        }
    }

    property string entryId: ""

    readonly property var options: DashRegistry.resolvedOptions(entryId)
}
