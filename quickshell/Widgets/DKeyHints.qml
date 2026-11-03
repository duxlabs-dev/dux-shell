import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../Common/KeyUtils.js" as KeyUtils

Item {
    id: root

    property var hints: []

    readonly property real widestHint: {
        let widest = 0;
        for (let i = 0; i < grid.children.length; i++)
            widest = Math.max(widest, grid.children[i].implicitWidth);
        return widest;
    }

    implicitHeight: grid.height
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Grid {
        id: grid

        anchors.horizontalCenter: parent.horizontalCenter
        columns: Math.max(1, Math.min(root.hints.length, Math.floor((root.width + columnSpacing) / (root.widestHint + columnSpacing))))
        columnSpacing: Theme.spacingL
        rowSpacing: Theme.spacingXS
        verticalItemAlignment: Grid.AlignVCenter

        Repeater {
            model: root.hints

            Row {
                id: hint

                required property var modelData

                spacing: Theme.spacingS

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXXS
                    LayoutMirroring.enabled: false
                    LayoutMirroring.childrenInherit: true

                    Repeater {
                        model: hint.modelData.keys

                        Row {
                            id: combo

                            required property string modelData
                            required property int index

                            spacing: Theme.spacingXXS

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: combo.index > 0
                                text: "/"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            Repeater {
                                model: KeyUtils.formatKeyTokens(combo.modelData)

                                DKeycap {
                                    required property string modelData

                                    text: modelData
                                }
                            }
                        }
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: hint.modelData.label
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
