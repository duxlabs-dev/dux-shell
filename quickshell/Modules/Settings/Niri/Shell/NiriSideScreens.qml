pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Desk
import "../../../../Common/niri/sections/workspaces.js" as Ws

// Side pane of Workspaces: each screen with its workspaces and live windows.
Column {
    id: root

    // Window thumbnails drawn per workspace row; the count label says the rest
    readonly property int thumbsMax: 3
    readonly property real minRowHeight: Theme.iconButtonSize
    readonly property var lanes: Ws.lanes(NiriService.allWorkspaces, NiriService.windows)
    readonly property var activeIds: NiriService.allWorkspaces.filter(w => w.is_active).map(w => w.id)
    readonly property var screens: [...new Set(lanes.map(l => l.output))].map(output => ({
                output: output,
                rows: lanes.filter(l => l.output === output).map(l => ({
                            label: l.name || String(l.idx),
                            count: l.windows.length,
                            on: activeIds.includes(l.id)
                        }))
            }))
    readonly property var values: [].concat(...screens.map(s => s.rows.map(r => r.label + " · " + r.count)))

    width: parent?.width ?? 0
    spacing: Theme.spacingM

    NiriSideHead {
        icon: "space_dashboard"
        title: I18n.tr("Workspaces per screen", "niri page side pane")
    }

    ClippingRectangle {
        id: frame

        readonly property real baseHeight: width * 9 / 16

        width: parent.width
        // Grows past 16:9 when a screen has more workspaces than fit at the minimum row height
        height: Math.max(baseHeight, screensRow.implicitHeight + Theme.spacingL * 2)
        radius: Theme.cornerRadiusM
        color: "transparent"

        NiriWallpaper {
            anchors.fill: parent
        }

        Rectangle {
            anchors.centerIn: parent
            visible: root.screens.length === 0
            width: Math.min(emptyText.implicitWidth, frame.width - Theme.spacingL * 2) + Theme.spacingM * 2
            height: emptyText.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadiusS
            color: Theme.surfaceContainerHighest

            StyledText {
                id: emptyText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, frame.width - Theme.spacingL * 2)
                text: I18n.tr("niri reports no workspace yet", "niri page side pane, empty state")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
        }

        Row {
            id: screensRow

            x: Theme.spacingL
            y: Theme.spacingL
            width: parent.width - Theme.spacingL * 2
            spacing: Theme.spacingL

            Repeater {
                model: root.screens

                Column {
                    id: screenColumn

                    required property var modelData
                    readonly property int rowCount: Math.max(1, modelData.rows.length)

                    width: (screensRow.width - screensRow.spacing * (root.screens.length - 1)) / Math.max(1, root.screens.length)
                    spacing: Theme.spacingS

                    Rectangle {
                        id: outputChip
                        width: Math.min(outputText.implicitWidth + Theme.spacingS * 2, screenColumn.width)
                        height: outputText.implicitHeight + Theme.spacingXXS * 2
                        radius: height / 2
                        color: Theme.surfaceContainerHighest

                        StyledText {
                            id: outputText
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, screenColumn.width - Theme.spacingS * 2)
                            text: screenColumn.modelData.output
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                    }

                    Repeater {
                        model: screenColumn.modelData.rows

                        Rectangle {
                            id: wsRow

                            required property var modelData

                            width: screenColumn.width
                            height: Math.max(root.minRowHeight, (frame.baseHeight - Theme.spacingL * 2 - outputChip.height) / screenColumn.rowCount - screenColumn.spacing)
                            radius: Theme.cornerRadiusS
                            color: Theme.withAlpha(Theme.surface, Theme.scrimAlpha)
                            border.width: modelData.on ? Theme.outlineWidthFocused : Theme.outlineWidth
                            border.color: modelData.on ? Theme.primary : Theme.outlineVariant

                            Row {
                                x: Theme.spacingS
                                y: Theme.spacingS
                                height: Math.max(0, parent.height - labelChip.height - Theme.spacingS * 2 - Theme.spacingXXS)
                                spacing: Theme.spacingXS

                                Repeater {
                                    model: Math.min(root.thumbsMax, wsRow.modelData.count)

                                    Rectangle {
                                        width: (wsRow.width - Theme.spacingS * 2 - Theme.spacingXS * (root.thumbsMax - 1)) / root.thumbsMax
                                        height: parent.height
                                        radius: Theme.cornerRadiusXS
                                        color: Theme.surfaceContainerHighest
                                    }
                                }
                            }

                            Rectangle {
                                id: labelChip
                                x: Theme.spacingXS
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Theme.spacingXS
                                width: Math.min(label.implicitWidth, wsRow.width - Theme.spacingS * 2) + Theme.spacingXS * 2
                                height: label.implicitHeight
                                radius: height / 2
                                color: Theme.surfaceContainerHighest

                                StyledText {
                                    id: label
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, wsRow.width - Theme.spacingS * 2)
                                    text: wsRow.modelData.label + " · " + wsRow.modelData.count
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Flow {
        width: parent.width
        spacing: Theme.spacingXS

        Repeater {
            model: root.values

            Rectangle {
                id: chip

                required property string modelData

                width: Math.min(chipText.implicitWidth, root.width - Theme.spacingS * 2) + Theme.spacingS * 2
                height: chipText.implicitHeight + Theme.spacingXS * 2
                radius: Theme.cornerRadiusS
                color: "transparent"
                border.width: Theme.outlineWidth
                border.color: Theme.outlineVariant

                StyledText {
                    id: chipText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, root.width - Theme.spacingS * 2)
                    text: chip.modelData
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }
            }
        }
    }
}
