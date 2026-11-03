import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.DCommon.Widgets
import qs.Widgets

// Edit-mode actions hung off the panel; a removable drag turns the strip into the trash.
Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property bool editMode: false
    property bool dragging: false
    property bool dragRemovable: false
    property bool canUndo: false
    property var transientSurfaceTracker: null
    readonly property bool trashShown: editMode && dragging && dragRemovable
    property bool overTrash: false
    property color backgroundColor: CcMetrics.dialogColor
    property vector4d cornerRadii: Qt.vector4d(Theme.windowRadius, Theme.windowRadius, Theme.windowRadius, Theme.windowRadius)
    property bool joined: false
    property bool above: false
    readonly property real leftRadius: above ? cornerRadii.x : cornerRadii.w
    readonly property real rightRadius: above ? cornerRadii.y : cornerRadii.z
    readonly property color trashColor: overTrash ? Theme.errorContainer : Theme.withAlpha(Theme.error, Theme.stateLayerDrag)
    // `above` flips y, which also reverses every arc's sweep.
    readonly property string outline: {
        const w = width;
        const h = height;
        const lf = Math.min(leftRadius, w / 2, h / 2);
        const rf = Math.min(rightRadius, w / 2, h / 2);
        const y = v => above ? h - v : v;
        const s = flag => above ? 1 - flag : flag;
        const joinedEdge = joined ? `M 0 ${y(0)} L ${w} ${y(0)}` : `M 0 ${y(lf)} A ${lf} ${lf} 0 0 ${s(1)} ${lf} ${y(0)} L ${w - rf} ${y(0)} A ${rf} ${rf} 0 0 ${s(1)} ${w} ${y(rf)}`;
        return `${joinedEdge} L ${w} ${y(h - rf)} A ${rf} ${rf} 0 0 ${s(1)} ${w - rf} ${y(h)} L ${lf} ${y(h)} A ${lf} ${lf} 0 0 ${s(1)} 0 ${y(h - lf)} Z`;
    }

    signal addWidgetRequested
    signal undoRequested
    signal resetRequested
    signal clearRequested
    signal finishRequested
    signal cancelRequested

    implicitHeight: CcMetrics.editActionsHeight
    visible: editMode

    function actionsY(rowHeight) {
        if (!joined)
            return (height - rowHeight) / 2;
        return above ? height - rowHeight : 0;
    }

    // No far or side edge, so a held tile stays held until it moves back into the panel.
    function trashContains(scenePosition) {
        if (!trashShown)
            return false;
        const y = mapFromItem(null, scenePosition.x, scenePosition.y).y;
        return above ? y <= height + CcMetrics.sheetPadding : y >= -CcMetrics.sheetPadding;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.backgroundColor
            PathSvg {
                path: root.outline
            }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.trashShown ? 1 : 0
        visible: opacity > 0

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height
                GradientStop {
                    position: 0
                    color: root.above ? root.trashColor : "transparent"
                }
                GradientStop {
                    position: 1
                    color: root.above ? "transparent" : root.trashColor
                }
            }
            PathSvg {
                path: root.outline
            }
        }

        Behavior on opacity {
            enabled: CcMetrics.animationsEnabled
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: CcMetrics.sheetPadding
        y: root.actionsY(height)
        spacing: Theme.spacingS
        visible: !root.trashShown

        DButton {
            buttonHeight: Theme.iconButtonSize
            iconName: "add"
            text: I18n.tr("Add widget")
            backgroundColor: Theme.secondaryContainer
            textColor: Theme.onSecondaryContainer
            onClicked: root.addWidgetRequested()
        }

        DActionButton {
            id: moreButton

            buttonSize: Theme.iconButtonSize
            iconName: "more_horiz"
            iconSize: CcMetrics.iconBoxIconSize
            iconColor: Theme.onSecondaryContainer
            backgroundColor: Theme.secondaryContainer
            tooltipText: I18n.tr("More")
            onClicked: editMenu.openAt(moreButton)
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: CcMetrics.sheetPadding
        y: root.actionsY(height)
        spacing: Theme.spacingS
        visible: !root.trashShown

        DActionButton {
            buttonSize: Theme.iconButtonSize
            iconName: "close"
            iconSize: CcMetrics.iconBoxIconSize
            iconColor: Theme.onSurface
            backgroundColor: Theme.chipSurface
            tooltipText: I18n.tr("Discard")
            onClicked: root.cancelRequested()
        }

        DActionButton {
            buttonSize: Theme.iconButtonSize
            iconName: "check"
            iconSize: CcMetrics.iconBoxIconSize
            iconColor: Theme.onPrimary
            backgroundColor: Theme.primary
            tooltipText: I18n.tr("Finish")
            onClicked: root.finishRequested()
        }
    }

    DIcon {
        anchors.centerIn: parent
        name: "delete"
        size: CcMetrics.iconBoxIconSize
        filled: root.overTrash
        color: Theme.error
        visible: root.trashShown
        Accessible.role: Accessible.Graphic
        Accessible.name: I18n.tr("Remove")
    }

    CcMenu {
        id: editMenu

        transientSurfaceTracker: root.transientSurfaceTracker
        items: [
            {
                "iconName": "undo",
                "label": I18n.tr("Undo"),
                "enabled": root.canUndo,
                "action": () => root.undoRequested()
            },
            {
                "iconName": "settings_backup_restore",
                "label": I18n.tr("Reset to default"),
                "action": () => root.resetRequested()
            },
            {
                "iconName": "clear_all",
                "label": I18n.tr("Clear All"),
                "destructive": true,
                "action": () => root.clearRequested()
            }
        ]
    }
}
