import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Rectangle {
    id: root

    property string iconName: ""
    property string title: ""
    property string hint: ""
    property string accent: ""
    property bool active: false
    property bool highlighted: false

    signal clicked(bool keyboard)

    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: hint
    Accessible.onPressAction: clicked(true)

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.clicked(true);
            event.accepted = true;
            break;
        }
    }

    readonly property var accentPair: Theme.accent(accent)
    readonly property color badgeColor: SettingsMetrics.navIconBadges ? accentPair?.container ?? Theme.withAlpha(Theme.primary, Theme.tonalTintAlpha) : "transparent"
    readonly property color glyphColor: {
        if (SettingsMetrics.navIconBadges)
            return accentPair?.onContainer ?? Theme.primary;
        return active ? Theme.onSelectedContainer : Theme.primary;
    }
    property bool isFirstInGroup: true
    property bool isLastInGroup: true
    property real topRadius: (active && Theme.shapeMorph) || isFirstInGroup ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
    property real bottomRadius: (active && Theme.shapeMorph) || isLastInGroup ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius

    Behavior on topRadius {
        enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    Behavior on bottomRadius {
        enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    width: parent?.width ?? 0
    height: Math.max(SettingsMetrics.navItemMinHeight, textColumn.implicitHeight + Theme.spacingS * 2)
    topLeftRadius: topRadius
    topRightRadius: topRadius
    bottomLeftRadius: bottomRadius
    bottomRightRadius: bottomRadius
    color: active ? SettingsMetrics.selectedRowColor : SettingsMetrics.sidebarRowColor
    border.width: SettingsMetrics.groupEdgeWidth
    border.color: Theme.outlineMedium

    Rectangle {
        x: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        height: Theme.dividerWidth
        visible: SettingsMetrics.continuousGroups && !root.isFirstInGroup && !root.active
        color: SettingsMetrics.groupDividerColor
    }

    Behavior on color {
        enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
        ColorAnimation {
            duration: SettingsMetrics.fadeDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    Rectangle {
        anchors.fill: parent
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
        color: Theme.surfaceText
        opacity: mouseArea.pressed ? Theme.stateLayerPressed : focusRing.visible ? Theme.stateLayerFocus : (mouseArea.containsMouse || root.highlighted ? Theme.stateLayerHover : 0)

        Behavior on opacity {
            enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
            NumberAnimation {
                duration: SettingsMetrics.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }

    DRipple {
        id: ripple
        rippleColor: Theme.surfaceText
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
    }

    Rectangle {
        id: iconCircle
        width: SettingsMetrics.navIconSize
        height: SettingsMetrics.navIconSize
        radius: Theme.fullRadius(width, height)
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingL
        anchors.verticalCenter: parent.verticalCenter
        color: root.badgeColor

        Behavior on color {
            enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
            ColorAnimation {
                duration: SettingsMetrics.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        DIcon {
            anchors.centerIn: parent
            name: root.iconName
            size: Theme.iconSizeMedium
            color: root.glyphColor
            filled: root.active
        }
    }

    Column {
        id: textColumn
        anchors.left: iconCircle.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingL
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXXS

        StyledText {
            width: parent.width
            text: root.title
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: root.active ? Theme.onSelectedContainer : Theme.surfaceText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignLeft
        }

        StyledText {
            width: parent.width
            text: root.hint
            font.pixelSize: Theme.fontSizeSmall
            color: root.active ? Theme.onSelectedContainer : Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            visible: root.hint !== ""
            horizontalAlignment: Text.AlignLeft
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            focusRing.pointerFocused = true;
            root.forceActiveFocus(Qt.MouseFocusReason);
            ripple.trigger(mouse.x, mouse.y);
        }
        onClicked: root.clicked(false)
    }

    FocusRing {
        id: focusRing
        anchors.margins: Theme.focusRingWidth / 2
        topLeftRadius: Math.max(0, root.topRadius - Theme.focusRingWidth / 2)
        topRightRadius: topLeftRadius
        bottomLeftRadius: Math.max(0, root.bottomRadius - Theme.focusRingWidth / 2)
        bottomRightRadius: bottomLeftRadius
    }
}
