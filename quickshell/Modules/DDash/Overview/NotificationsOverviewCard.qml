import QtQuick
import qs.Common
import qs.Modules.DDash

Card {
    id: root
    property bool live: Window.window?.visible ?? false
    property var transientSurfaceTracker: null
    readonly property bool opensTab: false
    focusTarget: panel
    blocksTabNavigation: panel.blocksTabNavigation
    activeFocusOnTab: interactive

    function handleKeyEvent(event) {
        return panel.handleKeyEvent(event);
    }

    entryId: "notifications"
    Accessible.name: I18n.tr("Notifications")
    pad: Theme.spacingM

    NotificationsTab {
        id: panel
        anchors.fill: parent
        live: root.live
        interactive: root.interactive
        nested: true
        swipeBleed: root.pad
        transientSurfaceTracker: root.transientSurfaceTracker
    }
}
