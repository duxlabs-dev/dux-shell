pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.Niri.Desk

// The live desktop, read-only, that a gesture moves: `fx` picks the effect and `t` runs it from 0 to 1.
Rectangle {
    id: root

    property string fx: ""
    property real t: 0
    // {"top-left": "overview", ...}: the corners that run something get a mark
    property var corners: ({})
    property alias pickedWorkspaceId: deskModel.pickedWorkspaceId
    readonly property alias outputWorkspaces: deskModel.outputWorkspaces
    readonly property alias shownWorkspaceId: deskModel.shownWorkspaceId

    // The focused column in this item's pixels; an empty workspace gets a middle column to act on.
    readonly property rect box: {
        const c = view.focusedColumn;
        if (!c)
            return Qt.rect(width * 0.36, height * 0.1, width * 0.34, height * 0.8);
        const g = (view.shown.gaps ?? 0) * view.ky;
        return Qt.rect((c.x - view.viewOffset) * view.kx, (view.barAtBottom ? 0 : view.barHeight) + g, c.width * view.kx, height - view.barHeight - g * 2);
    }
    // Move, resize and float carry the focused column alone (mockup `.col.f`), scene and bar still
    readonly property bool carryColumn: (fx === "move" || fx === "resize" || fx === "float") && view.focusedColumn !== null
    // One gap around the column: its shadow leaves with it and no neighbouring window is caught
    readonly property real padX: (view.shown.gaps ?? 0) * view.kx
    readonly property real padY: (view.shown.gaps ?? 0) * view.ky

    implicitHeight: view.implicitHeight
    radius: Theme.cornerRadius
    color: SettingsMetrics.controlColor
    clip: true

    NiriDeskModel {
        id: deskModel
    }

    component DeskCopy: NiriDeskView {
        width: root.width
        height: root.height
        deskState: deskModel.baseState
        columns: deskModel.columns
        floats: deskModel.floats
        outputWidth: deskModel.outputSize.width
        outputHeight: deskModel.outputSize.height
        screenName: deskModel.outputName
        workspaces: root.outputWorkspaces
        editable: false
        barAtBottom: deskModel.barAtBottom
    }

    Item {
        id: scene

        width: root.width
        height: root.height
        // The mockup slides the scene (ws, cols) or shrinks it (ov); move, resize and float act on the column below
        x: root.fx === "cols" ? -0.22 * width * root.t : 0
        y: root.fx === "ws" ? -height * root.t : 0
        scale: root.fx === "ov" ? 1 - 0.45 * root.t : 1

        DeskCopy {
            id: view
        }

        // Hides the column where it stood, so only the carried copy shows it
        Item {
            visible: root.carryColumn
            x: root.box.x - root.padX
            y: root.box.y - root.padY
            width: root.box.width + root.padX * 2
            height: root.box.height + root.padY * 2
            clip: true

            NiriWallpaper {
                x: -(root.box.x - root.padX)
                y: -(root.box.y - root.padY)
                width: root.width
                height: root.height
                screenName: view.screenName
            }
        }

        // The carried column: the mockup's `.col.f`, transform-origin left middle
        Item {
            id: carried

            visible: root.carryColumn
            x: root.box.x + (root.fx === "resize" ? 0 : 0.08 * root.box.width * root.t)
            // float composes scale(.8) translate(10%, 6%): 0.8 of the translation, 4.8% of the height
            y: root.box.y + (root.fx === "move" ? -0.08 * root.box.height * root.t : root.fx === "float" ? 0.048 * root.box.height * root.t : 0)
            width: root.box.width
            height: root.box.height

            transform: Scale {
                origin.x: 0
                origin.y: carried.height / 2
                xScale: root.fx === "resize" ? 1 + 0.2 * root.t : root.fx === "float" ? 1 - 0.2 * root.t : 1
                yScale: root.fx === "float" ? 1 - 0.2 * root.t : 1
            }

            Item {
                x: -root.padX
                y: -root.padY
                width: root.box.width + root.padX * 2
                height: root.box.height + root.padY * 2
                clip: true

                DeskCopy {
                    x: -(root.box.x - root.padX)
                    y: -(root.box.y - root.padY)
                }
            }
        }

        // The next workspace under this one (mockup ws2): flat grey window blocks slide in on a workspace swipe
        Item {
            id: nextWs

            y: scene.height
            width: scene.width
            height: scene.height

            readonly property real pad: width * 0.04
            readonly property real blockWidth: Math.min((width - pad * 3) / 2, width * 0.44)

            Repeater {
                model: 2

                Rectangle {
                    required property int index

                    x: nextWs.pad + index * (nextWs.blockWidth + nextWs.pad)
                    y: nextWs.pad
                    width: nextWs.blockWidth
                    height: nextWs.height - nextWs.pad * 2
                    radius: Theme.cornerRadiusS
                    color: Theme.isLightMode ? Theme.surface : Theme.surfaceContainerHigh
                }
            }
        }
    }

    // Below the bar, so a top corner glows where the pointer would hit it
    Item {
        y: view.barAtBottom ? 0 : view.barHeight
        width: root.width
        height: root.height - view.barHeight
        clip: true

        Repeater {
            model: Object.keys(root.corners).filter(c => root.corners[c] !== "none")

            Rectangle {
                required property string modelData

                x: (modelData.endsWith("left") ? 0 : parent.width) - width / 2
                y: (modelData.startsWith("top") ? 0 : parent.height) - height / 2
                width: parent.height * 0.5
                height: width
                radius: width / 2
                color: Theme.withAlpha(Theme.primary, 0.35)
            }
        }
    }
}
