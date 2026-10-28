import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.DCommon.Widgets
import qs.Widgets

Rectangle {
    id: root

    property bool pinned: false
    property bool iconOnly: true

    signal toggled

    readonly property color contentColor: enabled ? (pinned ? Theme.onSecondaryContainer : Theme.onSurfaceVariant) : Theme.onSurface_38
    readonly property real restRadius: Math.min(pinned && Theme.shapeMorph ? Theme.cornerRadiusXL : Theme.cornerRadiusM, height / 2)

    height: Theme.buttonHeightXS
    width: iconOnly ? height : content.implicitWidth + Theme.spacingM * 2
    radius: layer.pressed && Theme.shapeMorph ? Math.min(Theme.cornerRadiusS, height / 2) : restRadius
    color: pinned ? Theme.secondaryContainer : "transparent"
    border.width: pinned ? 0 : Theme.outlineWidth
    border.color: Theme.outlineVariant
    activeFocusOnTab: enabled
    Accessible.role: Accessible.CheckBox
    Accessible.name: pinned ? I18n.tr("Pinned") : I18n.tr("Pin", "verb, keep an item pinned in place")

    Keys.onPressed: event => {
        if (!root.enabled)
            return;
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.toggled();
            event.accepted = true;
            break;
        }
    }

    Behavior on radius {
        enabled: CcMetrics.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    Behavior on color {
        enabled: CcMetrics.animationsEnabled
        ColorAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    FocusRing {}

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.spacingS

        DIcon {
            name: "push_pin"
            size: Theme.chipIconSize
            color: root.contentColor
            filled: root.pinned
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: root.pinned ? I18n.tr("Pinned") : I18n.tr("Pin", "verb, keep an item pinned in place")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
            visible: !root.iconOnly
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StateLayer {
        id: layer
        disabled: !root.enabled
        stateColor: root.contentColor
        cornerRadius: root.radius
        onClicked: root.toggled()
    }
}
