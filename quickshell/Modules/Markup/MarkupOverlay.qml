pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets

// Print-screen capture: freezes every output, select a region on one, annotate it in place.
Scope {
    id: root

    // {cursor, finish} from `dms screenshot draw`; finish holds the output flags for `dms screenshot finish`.
    property var options: ({})
    property var owner: null
    property bool exporting: false
    // Only the grab itself crops the view, so the frozen frame stays whole while dms writes the result.
    property bool grabbing: false

    signal dismissed

    function start(opts) {
        options = opts;
        PopoutManager.screenshotActive = true;
    }

    function dismiss() {
        owner?.layer.reset();
        owner = null;
        options = ({});
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
        // Uncompressed: Qt's PNG encoder blocks the UI for most of a second on a 4K region.
        const scratch = Quickshell.env("XDG_RUNTIME_DIR") + "/dms-markup-" + Quickshell.processId + ".ppm";
        const done = (ok, details) => {
            exporting = false;
            if (!ok)
                return ToastService.showError(I18n.tr("Failed to save screenshot", "error toast, screenshot markup"), details);
            dismiss();
        };
        exporting = true;
        grabbing = true;
        owner.grab(result => {
            grabbing = false;
            if (!result?.saveToFile(scratch))
                return done(false, scratch);
            // No timeout: dms waits out a stalled clipboard service before serving the copy itself.
            Proc.runCommand(null, [Proc.dmsBin, "screenshot", "finish", mode, scratch].concat(options.finish), (output, exitCode) => done(exitCode === 0), 0, Proc.noTimeout, root);
        });
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

            function grab(done) {
                layer.commitText();
                // An unfinished drag and the selection box would end up in the image.
                layer.commitMove();
                layer.selectedIndex = -1;
                const sel = layer.crop;
                // grabToImage scales targetSize by the output scale, so a logical size yields physical pixels.
                if (!cropBox.grabToImage(done, Qt.size(sel.width, sel.height)))
                    done(null);
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
                // Live during export too: a dms that fails to start never reports back.
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

                readonly property bool cropping: root.grabbing && win.isOwner

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
                        paintCursor: root.options.cursor ?? false
                    }

                    MouseArea {
                        id: selector

                        property point start

                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.BackButton | Qt.ForwardButton
                        enabled: win.ready && layer.crop === null
                        cursorShape: Qt.CrossCursor

                        onPressed: mouse => {
                            if (mouse.button === Qt.BackButton) {
                                root.owner?.layer.undo();
                                mouse.accepted = true;
                                return;
                            }
                            if (mouse.button === Qt.ForwardButton) {
                                root.owner?.layer.redo();
                                mouse.accepted = true;
                                return;
                            }
                            root.claim(win);
                            layer.commitText();
                            start = Qt.point(mouse.x, mouse.y);
                            win.pendingSelection = Qt.rect(start.x, start.y, 0, 0);
                        }

                        onPositionChanged: mouse => {
                            if (!(mouse.buttons & Qt.LeftButton))
                                return;
                            win.pendingSelection = layer.normalizedRect(start, Qt.point(mouse.x, mouse.y));
                        }

                        onReleased: mouse => {
                            if (mouse.button !== Qt.LeftButton)
                                return;
                            const sel = win.pendingSelection;
                            win.pendingSelection = null;
                            if (sel && sel.width >= 4 && sel.height >= 4)
                                layer.commit(layer.shapes, sel);
                        }
                    }

                    AnnotationLayer {
                        id: layer

                        anchors.fill: parent
                        enabled: win.isOwner && layer.crop !== null && win.pendingSelection === null
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
                    readonly property bool isHorizEdge: modelData.x === 0.5
                    readonly property bool isVertEdge: modelData.y === 0.5
                    readonly property bool isEdge: isHorizEdge || isVertEdge

                    visible: sel !== null && win.isOwner && !root.exporting
                        && (!isHorizEdge || sel.width >= 48)
                        && (!isVertEdge || sel.height >= 48)
                    x: (sel?.x ?? 0) + (sel?.width ?? 0) * modelData.x - width / 2
                    y: (sel?.y ?? 0) + (sel?.height ?? 0) * modelData.y - height / 2
                    width: isHorizEdge ? Theme.spacingL : (isVertEdge ? 6 : Theme.spacingM)
                    height: isVertEdge ? Theme.spacingL : (isHorizEdge ? 6 : Theme.spacingM)
                    radius: Math.min(width, height) / 2
                    color: Theme.primary
                    border.color: Theme.onPrimary
                    border.width: Theme.outlineWidthFocused
                    scale: handleMouse.pressed ? 1.25 : (handleMouse.containsMouse ? 1.15 : 1)

                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    MouseArea {
                        id: handleMouse

                        property var startSelection: null

                        anchors.fill: parent
                        anchors.margins: -Theme.spacingS
                        hoverEnabled: true
                        cursorShape: {
                            const p = handle.modelData;
                            if (p.x === 0.5)
                                return Qt.SizeVerCursor;
                            if (p.y === 0.5)
                                return Qt.SizeHorCursor;
                            return (p.x === p.y) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor;
                        }

                        onPressed: mouse => {
                            mouse.accepted = true;
                            layer.commitText();
                            startSelection = layer.crop;
                        }

                        onPositionChanged: mouse => {
                            if (!pressed || !startSelection)
                                return;
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
                            startSelection = null;
                            if (sel && sel.width >= 4 && sel.height >= 4)
                                layer.commit(layer.shapes, sel);
                        }

                        onCanceled: {
                            win.pendingSelection = null;
                            startSelection = null;
                        }
                    }
                }
            }

            Rectangle {
                id: regionDragHandle

                readonly property var sel: win.selection
                readonly property real gap: Theme.spacingM
                readonly property bool fitsAbove: sel !== null && sel.y - height - gap >= 0
                readonly property bool fitsBelow: sel !== null && sel.y + sel.height + height + gap <= win.height
                readonly property bool toolbarIsBelow: sel !== null && sel.y + sel.height + Theme.spacingS + toolbar.height <= win.height

                visible: sel !== null && win.isOwner && !root.exporting
                x: Math.max(Theme.spacingS, Math.min(win.width - width - Theme.spacingS, (sel?.x ?? 0) + (sel?.width ?? 0) / 2 - width / 2))
                y: {
                    if (!sel)
                        return 0;
                    if (fitsAbove)
                        return sel.y - height - gap;
                    // If toolbar is placed below the region, put the drag handle inside the top border of the region
                    if (toolbarIsBelow || !fitsBelow)
                        return sel.y + gap;
                    return sel.y + sel.height + gap;
                }
                width: Theme.iconSize + Theme.spacingM
                height: Theme.iconSizeSmall + Theme.spacingS
                radius: Theme.fullRadius(width, height)
                color: regionDragArea.pressed ? Theme.primaryContainer : (regionDragArea.containsMouse ? Theme.readableSurfaceHigh : Theme.readableSurface)
                border.color: regionDragArea.pressed || regionDragArea.containsMouse ? Theme.primary : Theme.outlineVariant
                border.width: Theme.outlineWidth
                scale: regionDragArea.pressed ? 0.96 : (regionDragArea.containsMouse ? 1.04 : 1)

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.shortDuration
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }

                DIcon {
                    anchors.centerIn: parent
                    name: "drag_pan"
                    size: Theme.iconSizeSmall
                    color: regionDragArea.pressed ? Theme.onPrimaryContainer : Theme.surfaceText
                }

                MouseArea {
                    id: regionDragArea

                    property point start
                    property var startSelection: null

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                    onPressed: mouse => {
                        layer.commitText();
                        start = mapToItem(content, mouse.x, mouse.y);
                        startSelection = layer.crop;
                    }

                    onPositionChanged: mouse => {
                        if (!pressed || !startSelection)
                            return;
                        const p = mapToItem(content, mouse.x, mouse.y);
                        const dx = p.x - start.x;
                        const dy = p.y - start.y;
                        const s = startSelection;
                        const nx = Math.max(0, Math.min(win.width - s.width, s.x + dx));
                        const ny = Math.max(0, Math.min(win.height - s.height, s.y + dy));
                        win.pendingSelection = Qt.rect(nx, ny, s.width, s.height);
                    }

                    onReleased: {
                        const sel = win.pendingSelection;
                        win.pendingSelection = null;
                        const s = startSelection;
                        startSelection = null;
                        const unchanged = s && sel && sel.x === s.x && sel.y === s.y && sel.width === s.width && sel.height === s.height;
                        if (sel && sel.width >= 4 && sel.height >= 4 && !unchanged)
                            layer.commit(layer.shapes, sel);
                    }

                    onCanceled: {
                        win.pendingSelection = null;
                        startSelection = null;
                    }
                }
            }

            Rectangle {
                id: toolbar

                readonly property var sel: layer.crop
                readonly property real gap: Theme.spacingS
                readonly property bool fitsBelow: sel !== null && sel.y + sel.height + gap + height <= win.height
                // Shrinks to fit an output narrower than the tools.
                readonly property real fit: Math.min(1, (win.width - gap * 2) / (width + gap + closeButtonCard.width))
                readonly property real totalWidth: (width + gap + closeButtonCard.width) * fit

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
                radius: Theme.fullRadius(width, height)
                color: Theme.readableSurface
                scale: fit
                transformOrigin: Item.TopLeft

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

                    DActionButton {
                        iconName: "content_copy"
                        iconSize: Theme.chipIconSize
                        iconColor: Theme.surfaceText
                        tooltipText: I18n.tr("Copy", "screenshot markup, copies the annotated image to the clipboard")
                        onClicked: root.finish("copy")
                    }

                    DActionButton {
                        iconName: "save"
                        iconSize: Theme.chipIconSize
                        iconColor: Theme.surfaceText
                        tooltipText: I18n.tr("Save", "screenshot markup, saves the annotated image to a file")
                        onClicked: root.finish("save")
                    }

                    DActionButton {
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
                x: toolbar.x + (toolbar.width + toolbar.gap) * toolbar.fit
                y: toolbar.y
                radius: Theme.fullRadius(width, height)
                color: Theme.readableSurface
                scale: toolbar.fit
                transformOrigin: Item.TopLeft

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => mouse.accepted = true
                }

                DActionButton {
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
