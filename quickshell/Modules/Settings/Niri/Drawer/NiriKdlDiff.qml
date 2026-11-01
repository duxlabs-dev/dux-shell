pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    property var ops: []

    implicitHeight: Math.min(lines.implicitHeight, Theme.fontSizeMedium * 14) + Theme.spacingS * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainer
    border.color: Theme.outlineVariant
    border.width: Theme.outlineWidth
    clip: true

    DFlickable {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        contentHeight: lines.implicitHeight

        Column {
            id: lines
            width: parent.width

            Repeater {
                model: root.ops

                Rectangle {
                    id: line

                    required property var modelData
                    readonly property color tone: modelData.kind === "add" ? Theme.success : modelData.kind === "del" ? Theme.error : "transparent"

                    width: lines.width
                    implicitHeight: label.implicitHeight
                    color: modelData.kind === "same" ? "transparent" : Theme.withAlpha(tone, 0.2)

                    StyledText {
                        id: label
                        x: Theme.spacingS
                        width: parent.width - Theme.spacingS * 2
                        text: ({
                                "same": "  ",
                                "add": "+ ",
                                "del": "- "
                            })[line.modelData.kind] + line.modelData.text
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: line.modelData.kind === "same" ? Theme.surfaceVariantText : Theme.surfaceText
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }
}
