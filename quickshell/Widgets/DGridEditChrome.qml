import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string sizeText: ""
    property bool dragging: false
    property bool resizing: false
    property bool hasOptions: false
    property bool atDefault: false
    property bool snapped: false
    property bool removable: true
    property string removeIcon: "close"
    property bool horizontalResize: false
    property bool edgeResize: false
    property bool cornerResize: true
    property real resizeEdgeWidth: -1
    property real hitOverflow: -1
    // A child of the tile that keeps its own input in edit mode; resize bands never claim points over it.
    property Item passthrough: null
    property real cornerRadius: Theme.cornerRadiusXL
    property vector4d cornerRadii: Qt.vector4d(cornerRadius, cornerRadius, cornerRadius, cornerRadius)
    property real buttonSize: Theme.iconSizeLarge
    property real iconSize: Theme.iconSizeSmall
    readonly property real handleThickness: Theme.spacingM
    readonly property real touchTargetSize: Math.max(Theme.minimumTouchTargetSize, buttonSize)
    readonly property real contentInset: touchTargetSize / 2
    readonly property bool showOptionsButton: hasOptions
    // Too narrow to sit beside the remove button: both move onto the top corners instead.
    readonly property bool cornerButtons: hasOptions && width - contentInset * 2 < touchTargetSize * (1 + (removable ? 1 : 0) + (horizontalResize ? 1 : 0))
    readonly property int chromeButtons: (removable ? 1 : 0) + (showOptionsButton && !cornerButtons ? 1 : 0)
    readonly property rect hitBounds: Qt.rect(contentInset - hitOverflow, contentInset - hitOverflow, width - (contentInset - hitOverflow) * 2, height - (contentInset - hitOverflow) * 2)

    signal removeRequested
    signal optionsRequested(var anchor)
    signal resizeStarted(real px, real py, int signX)
    signal resizeCanceled
    signal resizeMoved(real px, real py, int modifiers)
    signal resizeEnded

    component HitMask: Item {
        required property Item target
        readonly property real insetX: Math.max(0, root.hitBounds.x - target.x)
        readonly property real insetY: Math.max(0, root.hitBounds.y - target.y)

        x: insetX
        y: insetY
        width: Math.max(0, Math.min(target.width, root.hitBounds.x + root.hitBounds.width - target.x) - insetX)
        height: Math.max(0, Math.min(target.height, root.hitBounds.y + root.hitBounds.height - target.y) - insetY)
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.contentInset
        topLeftRadius: root.cornerRadii.x
        topRightRadius: root.cornerRadii.y
        bottomRightRadius: root.cornerRadii.z
        bottomLeftRadius: root.cornerRadii.w
        color: root.dragging || root.resizing ? Theme.withAlpha(Theme.primary, Theme.stateLayerDrag) : "transparent"
        border.color: Theme.primary
        border.width: Theme.outlineWidthFocused
    }

    component ButtonChip: Rectangle {
        height: root.buttonSize
        radius: Theme.fullRadius(width, height)
        color: Theme.chipSurface
        border.color: Theme.primary
        border.width: Theme.outlineWidth
    }

    ButtonChip {
        x: root.cornerButtons ? removeButton.x + (root.touchTargetSize - root.buttonSize) / 2 : I18n.isRtl ? root.width - root.contentInset - width - (root.touchTargetSize - root.buttonSize) / 2 : root.contentInset + (root.touchTargetSize - root.buttonSize) / 2
        y: root.contentInset - height / 2
        width: root.buttonSize + root.touchTargetSize * Math.max(0, root.chromeButtons - 1)
        visible: root.chromeButtons > 0
    }

    ButtonChip {
        x: optionsButton.x + (root.touchTargetSize - root.buttonSize) / 2
        y: root.contentInset - height / 2
        width: root.buttonSize
        visible: root.cornerButtons
    }

    DActionButton {
        id: removeButton

        x: {
            if (root.cornerButtons)
                return I18n.isRtl ? root.width - width : 0;
            return I18n.isRtl ? root.width - root.contentInset - width : root.contentInset;
        }
        y: 0
        width: root.touchTargetSize
        height: root.touchTargetSize
        buttonSize: root.buttonSize
        iconSize: root.iconSize
        iconName: root.removeIcon
        iconColor: Theme.error
        tooltipText: I18n.tr("Remove")
        visible: root.removable
        enabled: !root.dragging && !root.resizing
        containmentMask: root.hitOverflow < 0 ? null : removeMask
        onClicked: root.removeRequested()

        HitMask {
            id: removeMask
            target: removeButton
        }
        onPressAndHold: {
            if (root.hasOptions)
                root.optionsRequested(removeButton);
        }
        Shortcut {
            sequences: ["Menu", "Shift+F10"]
            enabled: root.hasOptions && removeButton.activeFocus && removeButton.enabled
            onActivated: root.optionsRequested(removeButton)
        }
    }

    DActionButton {
        id: optionsButton

        readonly property real slotOffset: root.removable ? root.touchTargetSize : 0

        x: {
            if (root.cornerButtons)
                return I18n.isRtl ? 0 : root.width - width;
            return I18n.isRtl ? root.width - root.contentInset - slotOffset - width : root.contentInset + slotOffset;
        }
        y: 0
        width: root.touchTargetSize
        height: root.touchTargetSize
        buttonSize: root.buttonSize
        iconSize: root.iconSize
        iconName: "tune"
        iconColor: Theme.primary
        tooltipText: I18n.tr("Options")
        visible: root.showOptionsButton
        enabled: !root.dragging && !root.resizing
        containmentMask: root.hitOverflow < 0 ? null : optionsMask
        onClicked: root.optionsRequested(optionsButton)

        HitMask {
            id: optionsMask
            target: optionsButton
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: sizeLabel.implicitWidth + Theme.spacingM * 2
        height: root.buttonSize
        radius: Theme.fullRadius(width, height)
        color: root.atDefault || root.snapped ? Theme.primary : Theme.chipSurface
        visible: root.resizing && root.sizeText.length > 0

        StyledText {
            id: sizeLabel
            anchors.centerIn: parent
            text: root.sizeText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: root.atDefault || root.snapped ? Theme.onPrimary : Theme.surfaceText
        }
    }

    readonly property real gripRadius: Math.max(0, Math.min(cornerRadius, width / 2 - contentInset, height / 2 - contentInset) - Theme.outlineWidthFocused / 2)
    property real handleOverhang: edgeResize || Math.min(width, height) - contentInset * 2 < touchTargetSize * 2 ? contentInset : Theme.spacingS / 2
    readonly property real gripInset: handleOverhang - Theme.spacingS / 2

    component ResizeBand: MouseArea {
        property int signX: 1
        property real startX: 0
        property real startY: 0

        enabled: visible && !root.dragging
        hoverEnabled: true
        preventStealing: true

        onPressed: mouse => {
            const p = mapToItem(root, mouse.x, mouse.y);
            startX = p.x - root.contentInset;
            startY = p.y - root.contentInset;
            root.resizeStarted(startX, startY, signX);
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const p = mapToItem(root, mouse.x, mouse.y);
            root.resizeMoved(p.x - root.contentInset, p.y - root.contentInset, mouse.modifiers);
        }
        onReleased: root.resizeEnded()
        onCanceled: root.resizeCanceled()
    }

    component Handle: Item {
        id: handleItem

        property int signX: 1
        readonly property bool diagonalFlipped: (signX > 0) === I18n.isRtl

        y: root.horizontalResize ? (root.height - height) / 2 : root.height - root.contentInset - height + root.handleOverhang
        width: root.touchTargetSize
        height: root.touchTargetSize

        Rectangle {
            anchors.centerIn: parent
            width: root.handleThickness
            height: root.buttonSize
            radius: Theme.fullRadius(width, height)
            color: Theme.primary
            visible: root.horizontalResize
        }

        DResizeGrip {
            anchors.fill: parent
            anchors.leftMargin: handleItem.signX < 0 ? root.gripInset : 0
            anchors.rightMargin: handleItem.signX > 0 ? root.gripInset : 0
            anchors.bottomMargin: root.gripInset
            visible: !root.horizontalResize
            gripRadius: root.gripRadius
            mirrored: handleItem.diagonalFlipped
        }

        ResizeBand {
            id: band

            anchors.fill: parent
            signX: handleItem.signX
            cursorShape: root.horizontalResize ? Qt.SizeHorCursor : (handleItem.diagonalFlipped ? Qt.SizeBDiagCursor : Qt.SizeFDiagCursor)
            containmentMask: root.hitOverflow < 0 && !root.passthrough ? null : bandMask

            HitMask {
                id: handleMask
                target: handleItem
            }

            QtObject {
                id: bandMask

                function overButton(button: Item, point: point): bool {
                    return button.visible && button.contains(band.mapToItem(button, point.x, point.y));
                }

                function contains(point: point): bool {
                    if (root.hitOverflow >= 0 && (point.x < handleMask.x || point.y < handleMask.y || point.x >= handleMask.x + handleMask.width || point.y >= handleMask.y + handleMask.height))
                        return false;
                    if (overButton(removeButton, point) || overButton(optionsButton, point))
                        return false;
                    if (root.resizeEdgeWidth >= 0 && !root.horizontalResize) {
                        const local = band.mapToItem(root, point.x, point.y);
                        const fromEdge = handleItem.diagonalFlipped ? local.x - root.contentInset : root.width - root.contentInset - local.x;
                        if (fromEdge > root.resizeEdgeWidth && root.height - root.contentInset - local.y > root.resizeEdgeWidth)
                            return false;
                    }
                    const target = root.passthrough;
                    if (!target?.visible)
                        return true;
                    return !target.contains(band.mapToItem(target, point.x, point.y));
                }
            }
        }
    }

    Handle {
        anchors.right: parent.right
        anchors.rightMargin: root.contentInset - (root.horizontalResize ? width / 2 : root.handleOverhang)
        z: 1
        visible: root.cornerResize
    }

    Loader {
        anchors.fill: parent
        active: root.edgeResize && root.visible

        sourceComponent: Item {
            Handle {
                anchors.left: parent.left
                anchors.leftMargin: root.contentInset - (root.horizontalResize ? width / 2 : root.handleOverhang)
                signX: -1
            }
        }
    }
}
