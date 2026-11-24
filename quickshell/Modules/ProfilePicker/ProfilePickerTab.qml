pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.DDash

FocusScope {
    id: root

    property string entryId: "profiles"
    property bool active: false
    property bool editMode: false
    property var targetScreen: null
    property var islandController: null
    readonly property Item focusTarget: content

    implicitWidth: DashMetrics.contentWidthFor(SettingsData.showWeekNumber, DashMetrics.panelColumnsFor(entryId))
    implicitHeight: content.implicitHeight

    onActiveChanged: {
        if (active)
            content.reset();
    }
    Component.onCompleted: ConfigProfileService.ensureDefault()

    function handleKeyEvent(event) {
        return !editMode && content.handleKey(event);
    }

    ProfilePickerContent {
        id: content

        anchors.fill: parent
        focus: true
        enabled: !root.editMode
        view: "dash"
        targetScreen: root.targetScreen
        availableWidth: root.width
        onCloseRequested: root.islandController ? root.islandController.requestCollapse() : PopoutService.closeDankDash()
    }
}
