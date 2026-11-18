pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Column {
    id: root

    default property alias content: body.data
    // Settings search expands the nearest ancestor that looks like this
    readonly property bool collapsible: true
    property bool expanded: false
    property bool userToggled: false
    readonly property bool populated: expanded || reveal.height > 0
    // Search scrolls to registered rows, so a target that is not registered yet may be a row in here
    readonly property bool searchPending: SettingsSearchService.targetSection !== "" && SettingsSearchService.registeredCards[SettingsSearchService.targetSection] === undefined
    readonly property bool contentWanted: populated || searchPending

    function toggle() {
        userToggled = true;
        expanded = !expanded;
    }

    width: parent?.width ?? 0
    spacing: 0

    Item {
        id: reveal

        visible: root.expanded || height > 0
        enabled: root.expanded
        width: parent.width
        height: root.expanded ? body.height + SettingsMetrics.cardGap : 0
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
            id: body
            width: parent.width
            spacing: SettingsMetrics.cardGap
        }
    }

    Rectangle {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        width: pillRow.implicitWidth + Theme.spacingL * 2
        height: Theme.buttonHeightS
        radius: Theme.fullRadius(width, height)
        color: SettingsMetrics.rowColor
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: pillLabel.text
        Accessible.onPressAction: root.toggle()

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.toggle();
                event.accepted = true;
                break;
            }
        }

        FocusRing {
            id: pillRing
        }

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: Theme.spacingS

            DIcon {
                name: "tune"
                size: Theme.iconSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                id: pillLabel
                text: I18n.tr("Advanced options", "settings button at the bottom of a page that reveals rarely used options")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            DIcon {
                name: "expand_more"
                size: Theme.iconSizeMedium
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                    NumberAnimation {
                        duration: Theme.expressiveDurations.expressiveFastSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                    }
                }
            }
        }

        StateLayer {
            stateColor: Theme.surfaceText
            cornerRadius: pill.radius
            focused: pillRing.visible
            onClicked: {
                pillRing.pointerFocused = true;
                pill.forceActiveFocus(Qt.MouseFocusReason);
                root.toggle();
            }
        }
    }
}
