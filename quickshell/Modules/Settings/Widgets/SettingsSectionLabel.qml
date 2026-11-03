import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    property string text: ""
    property alias actions: actionsRow.data
    property bool collapsible: false
    property bool expanded: true
    property real topGap: SettingsMetrics.sectionLabelTopGap
    property real bottomGap: SettingsMetrics.sectionLabelBottomGap

    activeFocusOnTab: collapsible && enabled
    Accessible.role: collapsible ? Accessible.Button : Accessible.StaticText
    Accessible.name: text
    Accessible.onPressAction: {
        if (collapsible && enabled)
            toggleRequested();
    }

    Keys.onPressed: event => {
        if (!collapsible || !enabled)
            return;
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            toggleRequested();
            event.accepted = true;
            break;
        }
    }

    FocusRing {
        id: labelRing
        anchors.fill: headerHit
        radius: headerHit.radius + Theme.focusRingOffset
        visible: parentFocused && !pointerFocused && root.collapsible
    }

    signal toggleRequested

    width: parent?.width ?? 0
    height: Math.max(label.implicitHeight, actionsRow.implicitHeight, collapsible ? caret.height : 0) + topGap + bottomGap

    StyledText {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.right: actionsRow.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: (root.topGap - root.bottomGap) / 2
        text: root.text
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        color: Theme.primary
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignLeft
    }

    Row {
        id: actionsRow
        anchors.right: root.collapsible ? caret.left : parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: label.verticalCenter
        spacing: Theme.spacingXS
    }

    DIcon {
        id: caret
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: label.verticalCenter
        name: "expand_more"
        size: Theme.iconSize
        color: Theme.surfaceVariantText
        visible: root.collapsible
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

    Rectangle {
        id: headerHit
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: root.topGap - Theme.spacingXS
        anchors.bottomMargin: root.bottomGap - Theme.spacingXS
        radius: Theme.cornerRadiusS
        color: "transparent"
        visible: root.collapsible
        z: -1

        StateLayer {
            stateColor: Theme.primary
            cornerRadius: parent.radius
            focused: labelRing.visible
            onClicked: {
                labelRing.pointerFocused = true;
                root.forceActiveFocus(Qt.MouseFocusReason);
                root.toggleRequested();
            }
        }
    }
}
