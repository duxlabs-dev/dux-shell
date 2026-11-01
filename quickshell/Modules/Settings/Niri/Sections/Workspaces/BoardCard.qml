pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import qs.Modules.Settings.Widgets
import "../../../../../Common/niri/sections/workspaces.js" as Ws

Column {
    id: root

    readonly property var named: NiriPageService.get("workspaces.named") ?? []
    readonly property var lanes: Ws.lanes(NiriService.allWorkspaces, NiriService.windows, NiriService.focusedWorkspaceId)
    readonly property var screenGroups: Ws.screens(lanes)
    // Count, not the array: delegates survive window events so a drag or a rename in progress is kept.
    readonly property int screenCount: screenGroups.length
    readonly property var outputNames: Object.keys(NiriService.outputs).sort()
    readonly property real laneMinWidth: Theme.iconButtonSize * 4

    function act(action) {
        return NiriService.send({
            "Action": action
        });
    }

    function moveWindows(ids, workspaceId) {
        for (const id of ids) {
            act({
                "MoveWindowToWorkspace": {
                    "window_id": id,
                    "reference": {
                        "Id": workspaceId
                    },
                    "focus": false
                }
            });
        }
    }

    function closeWindows(ids) {
        for (const id of ids) {
            act({
                "CloseWindow": {
                    "id": id
                }
            });
        }
    }

    function isOwned(name) {
        return named.some(ws => ws.name === name);
    }

    // Live first, so the reload that follows finds the workspace under its new name.
    function renameLane(lane, text) {
        if (text.trim() === lane.name)
            return true;
        const next = Ws.rename(named, lane.name, text);
        if (!next) {
            if (text.trim() && text.trim() !== lane.name)
                ToastService.showError(I18n.tr("A workspace with this name exists"));
            return false;
        }
        act({
            "SetWorkspaceName": {
                "name": text.trim(),
                "workspace": {
                    "Id": lane.id
                }
            }
        });
        NiriPageService.set("workspaces.named", next);
        return true;
    }

    function addNamed(text) {
        const next = Ws.add(named, text);
        if (!next) {
            if (text.trim())
                ToastService.showError(I18n.tr("A workspace with this name exists"));
            return false;
        }
        NiriPageService.set("workspaces.named", next);
        return true;
    }

    function moveNamedUp(index) {
        const name = named[index].name;
        const above = lanes.find(l => l.name === named[index - 1].name);
        const self = lanes.find(l => l.name === name);
        if (above && self && above.output === self.output) {
            act({
                "MoveWorkspaceToIndex": {
                    "index": above.idx,
                    "reference": {
                        "Name": name
                    }
                }
            });
        }
        NiriPageService.set("workspaces.named", Ws.moveUp(named, index));
    }

    function setNamedOutput(name, output) {
        if (output && lanes.some(l => l.name === name)) {
            act({
                "MoveWorkspaceToMonitor": {
                    "output": output,
                    "reference": {
                        "Name": name
                    }
                }
            });
        }
        NiriPageService.set("workspaces.named", Ws.setOutput(named, name, output));
    }

    function removeNamed(name) {
        NiriPageService.set("workspaces.named", Ws.remove(named, name));
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingM

    NiriCard {
        id: liveCard

        property bool showNamed: false

        icon: "space_dashboard"
        title: I18n.tr("Live workspaces", "niri page card")
        aside: I18n.tr("Drag windows")

        StyledText {
            width: parent.width
            visible: root.lanes.length > 0
            wrapMode: Text.WordWrap
            text: I18n.tr("Drop a window on another lane to move it. Focus a chip and press Alt+Left / Alt+Right.", "niri page workspaces hint")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        StyledText {
            width: parent.width
            visible: root.lanes.length === 0
            text: I18n.tr("No workspace from niri yet.")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        Repeater {
            model: root.screenCount

            // One band per output: lanes stop mixing screens.
            Rectangle {
                id: screenBand

                required property int index
                readonly property var group: root.screenGroups[screenBand.index] ?? {
                    "output": "",
                    "lanes": []
                }
                readonly property string outputName: group.output || I18n.tr("Any screen")
                // eDP is the panel: the only output we can tell apart without a monitor database.
                readonly property string outputIcon: outputName.startsWith("eDP") ? "laptop" : "desktop_windows"

                width: parent.width
                implicitHeight: bandContent.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadiusM
                color: Theme.surfaceContainer

                Column {
                    id: bandContent

                    x: Theme.spacingS
                    y: Theme.spacingS
                    width: parent.width - Theme.spacingS * 2
                    spacing: Theme.spacingS

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        DIcon {
                            id: screenIcon
                            anchors.verticalCenter: parent.verticalCenter
                            name: screenBand.outputIcon
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            id: outputNameText
                            anchors.verticalCenter: parent.verticalCenter
                            text: screenBand.outputName
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightBold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            id: laneCountText
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - screenIcon.width - outputNameText.width - Theme.spacingS * 2
                            horizontalAlignment: Text.AlignRight
                            text: screenBand.group.lanes.length === 1 ? I18n.tr("1 lane", "niri page workspaces, screen band count") : I18n.tr("%1 lanes", "niri page workspaces, screen band count").arg(screenBand.group.lanes.length)
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    Grid {
                        id: laneGrid

                        property int laneOffset: {
                            let before = 0;
                            for (let g = 0; g < screenBand.index && g < root.screenGroups.length; g++)
                                before += root.screenGroups[g].lanes.length;
                            return before;
                        }

                        readonly property int cols: Math.max(1, Math.floor((width + spacing) / (root.laneMinWidth + spacing)))
                        readonly property real laneWidth: (width - spacing * (cols - 1)) / cols

                        width: parent.width
                        columns: cols
                        spacing: Theme.spacingS

                        Repeater {
                            model: screenBand.group.lanes.length

                            BoardLane {
                                id: laneItem

                                required property int index

                                board: root
                                laneIndex: laneGrid.laneOffset + laneItem.index
                                lane: screenBand.group.lanes[laneItem.index] ?? null
                                width: laneGrid.laneWidth
                                z: laneItem.dragging ? 1 : 0
                            }
                        }
                    }
                }
            }
        }

        // Standard fold: icon + label + chevron, like the other folded cards.
        Rectangle {
            id: orderFold

            objectName: "orderFold"
            width: parent.width
            implicitHeight: Theme.listItemHeight
            radius: Theme.cornerRadiusS
            color: "transparent"
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: orderText.text
            Accessible.onPressAction: liveCard.showNamed = !liveCard.showNamed
            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Space)
                    return;
                liveCard.showNamed = !liveCard.showNamed;
                event.accepted = true;
            }

            Rectangle {
                width: parent.width
                height: Theme.outlineWidth
                radius: width / 2
                color: Theme.outlineVariant
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Theme.surfaceText
                opacity: foldMouse.pressed ? Theme.stateLayerPressed : foldMouse.containsMouse ? Theme.stateLayerHover : 0
            }

            Row {
                x: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "format_list_numbered"
                    size: Theme.iconSizeMedium
                    color: Theme.surfaceText
                }

                StyledText {
                    id: orderText
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Order and screens")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightBold
                    color: Theme.surfaceText
                }
            }

            DIcon {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                name: liveCard.showNamed ? "expand_less" : "expand_more"
                size: Theme.iconSize
                color: Theme.surfaceText
            }

            MouseArea {
                id: foldMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: liveCard.showNamed = !liveCard.showNamed
            }

            FocusRing {
                anchors.margins: Theme.focusRingWidth / 2
                radius: orderFold.radius
            }
        }

        BoardNamed {
            visible: liveCard.showNamed
            board: root
        }
    }

    CloseCard {}

    BoardBulk {
        board: root
    }
}