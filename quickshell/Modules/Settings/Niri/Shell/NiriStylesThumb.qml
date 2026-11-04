pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

// A style drawn as three columns; hovering or focusing it previews its values on the mini desktop.
Rectangle {
    id: root

    property var values: ({})
    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property bool selected: false
    property bool adding: false

    signal activated

    readonly property real drawScale: 0.25
    readonly property real gaps: (values["look.gaps"] ?? 16) * drawScale
    readonly property bool centered: values["columns.centerFocused"] === "always"
    readonly property bool previewing: !adding && (hover.hovered || activeFocus)

    implicitHeight: content.implicitHeight + Theme.spacingS * 2
    radius: Theme.cornerRadiusM
    color: Theme.surface
    border.width: selected ? Theme.outlineWidth * 2 : Theme.outlineWidth
    border.color: selected ? Theme.primary : hover.hovered ? Theme.outline : Theme.outlineVariant
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: subtitle
    Accessible.onPressAction: activated()
    Keys.onReturnPressed: activated()
    Keys.onSpacePressed: activated()

    onPreviewingChanged: SettingsUiState.niriPreviewState = previewing ? values : null

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.activated()
    }

    FocusRing {}

    Column {
        id: content

        x: Theme.spacingS
        y: Theme.spacingS
        width: parent.width - Theme.spacingS * 2
        spacing: Theme.spacingXS

        Rectangle {
            id: mini

            readonly property real colWidth: 0.4 * (width - root.gaps) - root.gaps
            readonly property real focusX: root.gaps + 2 * (colWidth + root.gaps)
            // niri's "never" scrolls just enough to show the focused (last) column
            readonly property real offset: root.centered ? focusX + colWidth / 2 - width / 2 : Math.max(0, focusX + colWidth + root.gaps - width)

            width: parent.width
            height: Theme.buttonHeightM + Theme.buttonHeightXXS
            radius: Theme.cornerRadiusS
            color: root.adding ? Theme.surfaceContainerHigh : Theme.surfaceContainerHighest
            clip: true

            DIcon {
                anchors.centerIn: parent
                visible: root.adding
                name: "add"
                size: Theme.iconSizeLarge
                color: Theme.surfaceVariantText
            }

            Repeater {
                model: root.adding ? 0 : 3

                Rectangle {
                    required property int index
                    readonly property bool focused: index === 2

                    x: root.gaps + index * (mini.colWidth + root.gaps) - mini.offset
                    y: root.gaps + Theme.spacingXXS
                    width: mini.colWidth
                    height: mini.height - y * 2
                    radius: (root.values["look.radius"] ?? 0) * root.drawScale
                    color: Theme.surfaceContainerLow
                    border.width: focused && root.values["look.ringOn"] !== false ? Math.max(1, (root.values["look.ringWidth"] ?? 4) * root.drawScale) : root.values["look.borderOn"] ? 1 : 0
                    border.color: focused && root.values["look.ringOn"] !== false ? Theme.primary : Theme.outline
                }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.icon !== ""
                name: root.icon
                size: Theme.iconSizeSmall
                color: Theme.primary
            }

            StyledText {
                width: parent.width - (root.icon ? Theme.iconSizeSmall + Theme.spacingXS : 0)
                text: root.title
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }
        }

        StyledText {
            width: parent.width
            text: root.subtitle
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }
}
