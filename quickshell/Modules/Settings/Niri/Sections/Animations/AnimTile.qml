import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

// Gallery tile: plays its animation on hover or focus, a click selects it for fine tuning.
Rectangle {
    id: root

    property string name: ""
    property string title: ""
    property var anim: null
    property string effect: "open"
    property real slowdown: 1
    property bool animationsOn: true
    property bool selected: false
    property bool expert: false

    signal picked

    implicitHeight: column.implicitHeight + Theme.spacingS * 2
    radius: Theme.cornerRadiusM
    color: "transparent"
    border.width: selected ? Theme.outlineWidthFocused : Theme.outlineWidth
    border.color: selected ? Theme.primary : hover.hovered || activeFocus ? Theme.outline : Theme.outlineVariant
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("%1. Plays on hover, click to pick it", "niri page animation gallery tile; %1 is the animation name").arg(title)

    onActiveFocusChanged: {
        if (activeFocus)
            stage.play();
    }
    Keys.onSpacePressed: root.picked()
    Keys.onReturnPressed: root.picked()

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (hovered)
                stage.play();
        }
    }

    TapHandler {
        onTapped: root.picked()
    }

    Column {
        id: column

        x: Theme.spacingS
        y: Theme.spacingS
        width: parent.width - Theme.spacingS * 2
        spacing: Theme.spacingXS

        AnimStage {
            id: stage
            width: parent.width
            height: Theme.iconButtonSize * 1.6
            anim: root.anim
            effect: root.effect
            slowdown: root.slowdown
            animationsOn: root.animationsOn
        }

        StyledText {
            width: parent.width
            text: root.title
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            visible: root.expert
            text: root.name
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }
}
