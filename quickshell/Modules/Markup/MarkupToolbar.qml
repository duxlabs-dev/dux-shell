pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets

Row {
    id: root

    required property AnnotationLayer target
    readonly property var toolIds: ["select", "pen", "highlighter", "arrow", "rect", "text", "eraser"]

    readonly property var allTools: ({
            "select": {
                icon: "highlight_alt",
                label: I18n.tr("Select", "screenshot draw tool, moves the selected region")
            },
            "pen": {
                icon: "stylus",
                label: I18n.tr("Pen", "screenshot markup tool, freehand drawing")
            },
            "highlighter": {
                icon: "ink_highlighter",
                label: I18n.tr("Highlighter", "screenshot markup tool, translucent marker")
            },
            "arrow": {
                icon: "arrow_outward",
                label: I18n.tr("Arrow", "screenshot markup tool, draws an arrow")
            },
            "rect": {
                icon: "crop_square",
                label: I18n.tr("Rectangle", "screenshot markup tool, draws an outlined box")
            },
            "text": {
                icon: "title",
                label: I18n.tr("Text", "screenshot markup tool, adds a text label")
            },
            "eraser": {
                icon: "ink_eraser",
                label: I18n.tr("Eraser", "screenshot markup tool, removes a whole annotation")
            }
        })
    readonly property var swatches: [Theme.primary, Theme.error, Theme.warning, Theme.info, Theme.secondary, Theme.surfaceContainerHighest, Theme.surfaceText, Theme.surface]
    readonly property var sizeLabels: [I18n.tr("Small", "screenshot markup stroke and text size"), I18n.tr("Medium", "screenshot markup stroke and text size"), I18n.tr("Large", "screenshot markup stroke and text size")]

    spacing: Theme.spacingXS

    component Separator: Rectangle {
        width: 1
        height: 20
        anchors.verticalCenter: parent?.verticalCenter
        color: Theme.outlineVariant
    }

    Repeater {
        model: root.toolIds

        delegate: DankActionButton {
            required property string modelData
            readonly property bool selected: root.target.tool === modelData

            iconName: root.allTools[modelData].icon
            iconSize: Theme.chipIconSize
            iconColor: selected ? Theme.onPrimaryContainer : Theme.surfaceText
            backgroundColor: selected ? Theme.primaryContainer : "transparent"
            tooltipText: root.allTools[modelData].label
            onClicked: {
                root.target.commitText();
                root.target.tool = modelData;
            }
        }
    }

    Separator {}

    Repeater {
        model: root.swatches

        delegate: Item {
            id: swatch

            required property color modelData
            readonly property bool selected: Qt.colorEqual(root.target.strokeColor, modelData)

            width: 24
            height: 24
            anchors.verticalCenter: parent?.verticalCenter

            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: width / 2
                color: "transparent"
                border.color: Theme.primary
                border.width: Theme.outlineWidthFocused
                visible: swatch.selected
            }

            DankColorSwatch {
                anchors.centerIn: parent
                width: 16
                height: 16
                swatchColor: swatch.modelData
            }

            StateLayer {
                anchors.fill: parent
                cornerRadius: width / 2
                onClicked: root.target.strokeColor = swatch.modelData
            }
        }
    }

    Separator {}

    DankActionButton {
        id: sizeButton

        readonly property var sizeCodes: ["S", "M", "L"]

        tooltipText: I18n.tr("Size", "screenshot markup size button tooltip, followed by the current size") + ": " + root.sizeLabels[root.target.sizeLevel]
        onClicked: root.target.sizeLevel = (root.target.sizeLevel + 1) % root.sizeLabels.length

        StyledText {
            anchors.centerIn: parent
            text: sizeButton.sizeCodes[root.target.sizeLevel]
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Bold
            color: Theme.surfaceText
        }
    }
}
