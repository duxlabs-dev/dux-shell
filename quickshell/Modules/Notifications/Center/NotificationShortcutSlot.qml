pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Notifications
import "../NotificationShortcuts.js" as Shortcuts

DIconButton {
    id: root

    required property string settingKey
    required property string shortcut
    property bool live: false
    property bool squeezed: false
    property bool historyActive: false
    property bool hintsActive: false
    property color restColor: Theme.cardSurface

    readonly property bool empty: shortcut === ""
    readonly property real targetScale: {
        if (!Theme.shapeMorph)
            return 1;
        if (pressed)
            return 1 + Theme.buttonGroupExpandRatio;
        return squeezed ? 1 - Theme.buttonGroupExpandRatio : 1;
    }
    readonly property var pressSpring: Theme.springPreset("fast", Theme.expressiveDurations.expressiveFastSpatial)

    signal editRequested

    buttonSize: Theme.iconButtonSize
    width: buttonSize * widthSpring.value
    iconSize: Theme.iconSizeMedium
    variant: empty ? "standard" : "tonal"
    checkable: shortcut === "dnd" || shortcut === "history" || shortcut === "hints"
    checked: {
        switch (shortcut) {
        case "dnd":
            return SessionData.doNotDisturb;
        case "history":
            return historyActive;
        case "hints":
            return hintsActive;
        }
        return false;
    }
    containerColor: checked ? Theme.primary : restColor
    contentColor: checked ? Theme.onPrimary : Theme.onSurfaceVariant
    iconName: Shortcuts.icon(shortcut)
    tooltipText: {
        switch (shortcut) {
        case "dnd":
            return I18n.tr("Do not disturb");
        case "history":
            return historyActive ? I18n.tr("Current", "notification center tab") : I18n.tr("History", "notification center tab");
        case "hints":
            return I18n.tr("Keyboard shortcuts");
        case "settings":
            return I18n.tr("Settings");
        }
        return I18n.tr("Add shortcut");
    }
    tooltipSide: "top"

    onPressAndHold: editRequested()
    Keys.onMenuPressed: editRequested()
    onTargetScaleChanged: widthSpring.retarget(targetScale)

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.editRequested()
    }

    Loader {
        anchors.fill: parent
        active: root.empty
        sourceComponent: Shape {
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.enabled ? Theme.outline : Theme.onSurface_12
                strokeWidth: Theme.outlineWidth
                strokeStyle: ShapePath.DashLine
                dashPattern: NotificationMetrics.shortcutDashPattern
                fillColor: "transparent"

                PathRectangle {
                    x: Theme.outlineWidth / 2
                    y: Theme.outlineWidth / 2
                    width: root.width - Theme.outlineWidth
                    height: root.height - Theme.outlineWidth
                    radius: Math.max(0, root.radius - Theme.outlineWidth / 2)
                }
            }
        }
    }

    SpringMotion {
        id: widthSpring
        enabled: root.live && root.visible && !Theme.springMotionDisabled
        stiffness: root.pressSpring.stiffness
        damping: root.pressSpring.damping
        Component.onCompleted: snapTo(root.targetScale)
    }
}
