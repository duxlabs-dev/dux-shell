pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Print-screen capture: freezes every output, select a region on one, annotate it in place.
Scope {
    id: root

    // {path, file, clipboard, notify} from `dms screenshot draw`.
    property var options: ({})
    property var owner: null
    property bool exporting: false

    signal dismissed

    function start(opts) {
        options = opts;
        PopoutManager.screenshotActive = true;
    }

    function dismiss() {
        PopoutManager.screenshotActive = false;
        dismissed();
    }

    function claim(win) {
        if (owner === win)
            return;
        owner?.layer.reset();
        owner = win;
    }

    // mode: "confirm" follows the CLI options, "copy" is clipboard only, "save" is file only.
    function finish(mode) {
        if (exporting || !owner?.layer.crop)
            return;
        const toFile = mode === "save" || (mode === "confirm" && options.file);
        const toClipboard = mode === "copy" || (mode === "confirm" && options.clipboard);
        if (!toFile && !toClipboard)
            return;
        const path = toFile ? options.path : Quickshell.env("XDG_RUNTIME_DIR") + "/dms-markup-copy.png";
        exporting = true;
        owner.exportTo(path, ok => {
            exporting = false;
            if (!ok) {
                ToastService.showError(I18n.tr("Failed to save screenshot", "error toast, screenshot markup"), path);
                return;
            }
            if (toClipboard)
                Quickshell.execDetached(["sh", "-c", "exec \"$0\" cl copy -t image/png < \"$1\"", Proc.dmsBin, path]);
            if (options.notify)
                notify(toFile ? path : "", toClipboard);
            dismiss();
        });
    }

    function notify(path, copied) {
        const lines = [];
        if (path)
            lines.push(path.split("/").pop());
        if (copied)
            lines.push(I18n.tr("Copied to clipboard", "toast or notification body after copying a screenshot"));
        const params = {
            summary: I18n.tr("Screenshot captured", "notification title after taking a screenshot"),
            body: lines.join("\n")
        };
        DMSService.sendRequest("notify.send", params);
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win

            required property var modelData
            readonly property alias layer: layer
            readonly property bool isOwner: root.owner === win
            readonly property var selection: pendingSelection ?? (isOwner ? layer.crop : null)
            readonly property bool ready: shot.hasContent
            property var pendingSelection: null

            function exportTo(path, done) {
                layer.commitText();
                const sel = layer.crop;
                // grabToImage scales targetSize by the output scale, so a logical size yields physical pixels.
                cropBox.grabToImage(result => done(result.saveToFile(path)), Qt.size(sel.width, sel.height));
            }

            screen: modelData
            color: "transparent"

            WlrLayershell.namespace: "dms:screenshot-markup"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Shortcut {
                sequences: ["Return", "Enter"]
                enabled: !layer.editingText
                onActivated: root.finish("confirm")
            }
            Shortcut {
                sequences: ["Escape"]
                enabled: !layer.editingText
                onActivated: root.dismiss()
            }
            Shortcut {
                sequences: [StandardKey.Copy]
                enabled: !layer.editingText
                onActivated: root.finish("copy")
            }
            Shortcut {
                sequences: [StandardKey.Save]
                onActivated: root.finish("save")
            }
            Shortcut {
                sequences: [StandardKey.Undo]
                onActivated: root.owner?.layer.undo()
            }
            Shortcut {
                sequences: [StandardKey.Redo, "Ctrl+Y"]
                onActivated: root.owner?.layer.redo()
            }

            Item {
                id: cropBox

                readonly property bool cropping: root.exporting && win.isOwner

                x: cropping ? layer.crop.x : 0
                y: cropping ? layer.crop.y : 0
                width: cropping ? layer.crop.width : parent.width
                height: cropping ? layer.crop.height : parent.height
                clip: cropping

                Item {
                    id: content

                    x: -cropBox.x
                    y: -cropBox.y
                    width: win.width
                    height: win.height

                    ScreencopyView {
                        id: shot

                        anchors.fill: parent
                        captureSource: win.screen
                        live: false
                    }

                    MouseArea {
                        id: selector

                        property point start
                        property var startSelection: null
                        property bool moving: false

                        anchors.fill: parent
                        enabled: win.ready
                        cursorShape: {
                            if (layer.tool === "select" && layer.crop !== null)
                                return moving || pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor;
                            return moving ? Qt.ClosedHandCursor : Qt.CrossCursor;
                        }

                        onPressed: mouse => {
                            root.claim(win);
                            layer.commitText();
                            start = Qt.point(mouse.x, mouse.y);
                            startSelection = layer.crop;
                            moving = layer.tool === "select" && layer.contains(layer.crop, start);
                            win.pendingSelection = moving ? layer.crop : Qt.rect(start.x, start.y, 0, 0);
                        }

                        onPositionChanged: mouse => {
                            if (!moving) {
                                win.pendingSelection = layer.normalizedRect(start, Qt.point(mouse.x, mouse.y));
                                return;
                            }
                            const s = startSelection;
                            const x = Math.max(0, Math.min(win.width - s.width, s.x + mouse.x - start.x));
                            const y = Math.max(0, Math.min(win.height - s.height, s.y + mouse.y - start.y));
                            win.pendingSelection = Qt.rect(x, y, s.width, s.height);
                        }

                        onReleased: {
                            const sel = win.pendingSelection;
                            win.pendingSelection = null;
                            moving = false;
                            const s = startSelection;
                            const unchanged = s && sel && sel.x === s.x && sel.y === s.y && sel.width === s.width && sel.height === s.height;
                            if (sel && sel.width >= 4 && sel.height >= 4 && !unchanged)
                                layer.commit(layer.shapes, sel);
                        }
                    }

                    AnnotationLayer {
                        id: layer

                        anchors.fill: parent
                        enabled: win.isOwner && layer.crop !== null && win.pendingSelection === null && layer.tool !== "select"
                        drawArea: layer.crop
                        tool: "pen"
                    }
                }
            }

            CropOverlay {
                anchors.fill: parent
                visible: win.ready && !root.exporting
                rect: win.selection
            }

            Repeater {
                // Fractions of the selection: corners and edge midpoints.
                model: [Qt.point(0, 0), Qt.point(0.5, 0), Qt.point(1, 0), Qt.point(0, 0.5), Qt.point(1, 0.5), Qt.point(0, 1), Qt.point(0.5, 1), Qt.point(1, 1)]

                delegate: Rectangle {
                    id: handle

                    required property point modelData
                    readonly property var sel: win.selection

                    visible: sel !== null && win.isOwner && !root.exporting
                    x: (sel?.x ?? 0) + (sel?.width ?? 0) * modelData.x - width / 2
                    y: (sel?.y ?? 0) + (sel?.height ?? 0) * modelData.y - height / 2
                    width: Theme.spacingM
                    height: Theme.spacingM
                    radius: width / 2
                    color: Theme.primary
                    border.color: Theme.onPrimary
                    border.width: Theme.outlineWidthFocused

                    MouseArea {
                        property var startSelection: null

                        anchors.fill: parent
                        anchors.margins: -Theme.spacingS
                        cursorShape: {
                            const p = handle.modelData;
                            if (p.x === 0.5)
                                return Qt.SizeVerCursor;
                            if (p.y === 0.5)
                                return Qt.SizeHorCursor;
                            return (p.x === p.y) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor;
                        }

                        onPressed: {
                            layer.commitText();
                            startSelection = layer.crop;
                        }

                        onPositionChanged: mouse => {
                            const s = startSelection;
                            const p = mapToItem(content, mouse.x, mouse.y);
                            const f = handle.modelData;
                            const left = f.x === 0 ? p.x : s.x;
                            const right = f.x === 1 ? p.x : s.x + s.width;
                            const top = f.y === 0 ? p.y : s.y;
                            const bottom = f.y === 1 ? p.y : s.y + s.height;
                            win.pendingSelection = layer.normalizedRect(Qt.point(left, top), Qt.point(right, bottom));
                        }

                        onReleased: {
                            const sel = win.pendingSelection;
                            win.pendingSelection = null;
                            if (sel && sel.width >= 4 && sel.height >= 4)
                                layer.commit(layer.shapes, sel);
                        }
                    }
                }
            }

            Rectangle {
                id: toolbar

                readonly property var sel: layer.crop
                readonly property real gap: Theme.spacingS
                readonly property bool fitsBelow: sel !== null && sel.y + sel.height + gap + height <= win.height
                readonly property real totalWidth: width + gap + closeButtonCard.width

                visible: win.isOwner && sel !== null && win.pendingSelection === null && !root.exporting
                width: toolbarRow.implicitWidth + Theme.spacingS * 2
                height: toolbarRow.implicitHeight + Theme.spacingS * 2
                x: Math.max(gap, Math.min(win.width - totalWidth - gap, (sel?.x ?? 0) + (sel?.width ?? 0) / 2 - totalWidth / 2))
                y: {
                    if (!sel)
                        return 0;
                    if (fitsBelow)
                        return sel.y + sel.height + gap;
                    if (sel.y - gap - height >= 0)
                        return sel.y - gap - height;
                    return sel.y + sel.height - gap - height;
                }
                radius: Theme.cornerRadius
                color: Theme.surfaceContainer

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => mouse.accepted = true
                }

                Row {
                    id: toolbarRow

                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    MarkupToolbar {
                        target: layer
                    }

                    Rectangle {
                        width: 1
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.outlineVariant
                    }

                    DankActionButton {
                        iconName: "undo"
                        iconSize: Theme.chipIconSize
                        iconColor: Theme.surfaceText
                        enabled: layer.canUndo
                        tooltipText: I18n.tr("Undo", "screenshot markup, reverts the last edit")
                        onClicked: layer.undo()
                    }

                    DankActionButton {
                        iconName: "redo"
                        iconSize: Theme.chipIconSize
                        iconColor: Theme.surfaceText
                        enabled: layer.canRedo
                        tooltipText: I18n.tr("Redo", "screenshot markup, reapplies the last undone edit")
                        onClicked: layer.redo()
                    }

                    DankActionButton {
                        iconName: "content_copy"
                        iconSize: Theme.chipIconSize
                        iconColor: Theme.surfaceText
                        tooltipText: I18n.tr("Copy", "screenshot markup, copies the annotated image to the clipboard")
                        onClicked: root.finish("copy")
                    }

                    DankActionButton {
                        iconName: "save"
                        iconSize: Theme.chipIconSize
                        iconColor: Theme.surfaceText
                        tooltipText: I18n.tr("Save", "screenshot markup, saves the annotated image to a file")
                        onClicked: root.finish("save")
                    }

                    DankActionButton {
                        iconName: "check"
                        iconSize: Theme.chipIconSize
                        iconColor: Theme.primary
                        tooltipText: I18n.tr("Finish", "screenshot draw, captures the selection")
                        onClicked: root.finish("confirm")
                    }
                }
            }

            Rectangle {
                id: closeButtonCard

                visible: toolbar.visible
                width: toolbar.height
                height: toolbar.height
                x: toolbar.x + toolbar.width + toolbar.gap
                y: toolbar.y
                radius: Theme.cornerRadius
                color: Theme.surfaceContainer

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => mouse.accepted = true
                }

                DankActionButton {
                    anchors.centerIn: parent
                    iconName: "close"
                    iconSize: Theme.chipIconSize
                    iconColor: Theme.error
                    tooltipText: I18n.tr("Cancel", "screenshot draw, closes without capturing")
                    onClicked: root.dismiss()
                }
            }
        }
    }
}
