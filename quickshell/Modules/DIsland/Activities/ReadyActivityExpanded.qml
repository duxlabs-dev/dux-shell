pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Notifications
import qs.Modules.DIsland.Kit
import "../../../Common/IslandActivityInput.js" as Input
import "../../../Common/IslandKit.js" as Kit

// A plugin's ready-made face, open, on the notification popup's grid; its first action is the primary one.
FocusScope {
    id: root

    required property var face

    signal triggered(string actionId)

    readonly property color accent: Kit.readyTone(root.face.accent, Theme)

    // Its text, in reading order, for the sheet a screen reader lands on.
    Accessible.role: Accessible.Grouping
    Accessible.name: root.face.name

    // The keyboard lands on the first action, its ring shown (Enter runs it, as on the sheet); with none, on the sheet.
    function focusFace() {
        const first = actions.itemAt(0);
        if (first)
            first.forceActiveFocus(Qt.TabFocusReason);
        else
            root.forceActiveFocus();
        return true;
    }

    // Escape is left to the island, which folds the sheet back to its pill.
    Keys.onReturnPressed: event => root.runPrimary(event)
    Keys.onEnterPressed: event => root.runPrimary(event)

    function runPrimary(event) {
        const id = Input.primaryAction(root.face);
        event.accepted = id !== "";
        if (id)
            root.triggered(id);
    }

    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: NotificationMetrics.cardPadding
        height: Math.max(ring.height, texts.implicitHeight)

        ReadyActivityRing {
            id: ring

            iconName: root.face.icon
            progress: root.face.progress
            accent: root.accent
        }

        Column {
            id: texts

            anchors.left: ring.right
            anchors.leftMargin: NotificationMetrics.iconSpacing
            anchors.right: parent.right
            // Centered on the ring; three title lines and two detail lines fit the sheet's default height.
            y: Math.max(0, (ring.height - implicitHeight) / 2)
            spacing: NotificationMetrics.contentSpacing / 2

            StyledText {
                width: parent.width
                text: root.face.title
                color: Theme.surfaceText
                font.pixelSize: NotificationMetrics.summarySize
                font.weight: Theme.fontWeightMedium
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                visible: text !== ""
                text: root.face.detail
                color: Theme.surfaceVariantText
                font.pixelSize: NotificationMetrics.bodySize
                // A detail is often a figure (a time left, a size): its digits keep their width, as on the folded face.
                font.features: {
                    "tnum": 1
                }
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    IslandButtonRow {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: NotificationMetrics.cardPadding
        height: implicitHeight
        visible: root.face.actions.length > 0

        Repeater {
            id: actions

            // Hidden so the row gives it no share; its buttons are the row's own children and stay shown.
            visible: false
            model: root.face.actions

            IslandButton {
                required property var modelData
                required property int index

                text: modelData.label
                // Shares follow each label's own width, so a long one is not cut beside a short one.
                weight: implicitWidth
                role: index === 0 ? "primary" : "plain"
                onClicked: root.triggered(modelData.id)
            }
        }
    }
}
