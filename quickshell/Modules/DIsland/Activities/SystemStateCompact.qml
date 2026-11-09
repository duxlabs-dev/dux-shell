pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

DestinationCompact {
    id: root

    required property var systemModel

    readonly property bool linksControlCenter: root.systemModel.controlCenterSection !== ""

    activityId: root.systemModel.kind
    iconName: root.systemModel.iconName
    label: root.systemModel.title
    value: root.systemModel.displayValue

    IslandSlotHoverArea {
        anchors.fill: parent
        controller: root.controller
        cursorShape: root.linksControlCenter ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.linksControlCenter) {
                root.controller.requestControlCenter(root.systemModel.controlCenterSection, false);
                return;
            }
            root.controller.requestCollapse();
        }
    }
}
