pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Row {
    id: root

    required property AnnotationLayer target
    readonly property var toolIds: ["select", "pen", "highlighter", "arrow", "rect", "redact", "text", "eraser"]

    readonly property var allTools: ({
            "select": {
                icon: "arrow_selector_tool",
                label: I18n.tr("Select", "screenshot draw tool, select and move annotations", true)
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
            "redact": {
                icon: "ad_off",
                label: I18n.tr("Redact", "screenshot markup tool, draws a solid box to hide sensitive info")
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

    spacing: Theme.spacingXS

    component Separator: DDivider {
        vertical: true
        height: Theme.chipIconSize
        anchors.verticalCenter: parent?.verticalCenter
    }

    Repeater {
        model: root.toolIds

        delegate: DActionButton {
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

            width: Theme.iconSize
            height: Theme.iconSize
            anchors.verticalCenter: parent?.verticalCenter

            DColorSwatch {
                anchors.centerIn: parent
                width: swatch.selected ? Theme.iconSize - Theme.spacingXS : Theme.iconSizeSmall
                height: width
                swatchColor: swatch.modelData
                ringColor: swatch.selected ? Theme.primary : Theme.outline
                ringWidth: swatch.selected ? Theme.outlineWidthFocused : Theme.outlineWidth
            }

            StateLayer {
                anchors.fill: parent
                cornerRadius: width / 2
                onClicked: root.target.strokeColor = swatch.modelData
            }
        }
    }

    Separator {}

    MarkupSizeSlider {
        target: root.target
    }

    Separator {}

    DActionButton {
        iconName: "undo"
        iconSize: Theme.chipIconSize
        iconColor: Theme.surfaceText
        enabled: root.target.canUndo
        tooltipText: I18n.tr("Undo", "screenshot markup, reverts the last edit")
        onClicked: root.target.undo()
    }

    DActionButton {
        iconName: "redo"
        iconSize: Theme.chipIconSize
        iconColor: Theme.surfaceText
        enabled: root.target.canRedo
        tooltipText: I18n.tr("Redo", "screenshot markup, reapplies the last undone edit")
        onClicked: root.target.redo()
    }
}
