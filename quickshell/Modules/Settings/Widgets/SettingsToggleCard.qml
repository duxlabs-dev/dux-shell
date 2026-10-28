pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property bool isSettingsRow: true

    property string tab: ""
    property var tags: []
    property string settingKey: ""

    property string title: ""
    property string description: ""
    property string iconName: ""
    property bool checked: false
    property bool userToggled: false

    default property alias content: expandedContent.data
    readonly property bool hasContent: expandedContent.height > 0
    readonly property bool standalone: !(parent?.isSettingsGroupHost ?? false)
    readonly property bool firstInGroup: standalone || parent.isEdge(root, true)
    readonly property bool lastInGroup: standalone || parent.isEdge(root, false)
    readonly property bool expanded: checked && hasContent

    signal toggled(bool checked)

    width: parent?.width ?? 0
    height: column.height

    Rectangle {
        anchors.fill: parent
        radius: Theme.groupedListOuterRadius
        color: SettingsMetrics.rowColor
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        visible: root.standalone
    }

    Column {
        id: column
        width: parent.width
        spacing: 0

        SettingsToggleRow {
            id: header
            width: parent.width
            topRadius: root.firstInGroup ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            bottomRadius: root.lastInGroup && !root.expanded ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            tab: root.tab
            tags: root.tags
            settingKey: root.settingKey
            text: root.title
            description: root.description
            iconName: root.iconName
            checked: root.checked
            enabled: root.enabled
            paintBackground: false
            onToggled: value => {
                root.userToggled = true;
                root.toggled(value);
            }
        }

        Item {
            width: parent.width
            visible: root.checked || height > 0
            height: root.checked && root.hasContent ? expandedContent.height : 0
            clip: true

            Behavior on height {
                enabled: root.userToggled && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                NumberAnimation {
                    duration: SettingsMetrics.transitionDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                    onRunningChanged: {
                        if (!running)
                            root.userToggled = false;
                    }
                }
            }

            Column {
                id: expandedContent

                readonly property bool isSettingsGroupHost: true

                function isEdge(item, first) {
                    if (first || !root.lastInGroup)
                        return false;
                    let last = null;
                    for (let i = 0; i < visibleChildren.length; i++) {
                        if (visibleChildren[i].isSettingsRow === true)
                            last = visibleChildren[i];
                    }
                    return last === item;
                }

                enabled: root.checked
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.iconName !== "" ? Theme.iconSize + Theme.spacingL : 0
                spacing: 0
            }
        }
    }
}
