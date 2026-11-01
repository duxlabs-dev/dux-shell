pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.Niri.Shell
import "../../../../../Common/niri/sections/corners.js" as Corners

// The side pane of Gestures: the desktop plays one gesture once, fingers or pointer appear, then move with the effect.
Column {
    id: root

    property string gesture: ""
    property string sentence: ""
    // Enter or Space on a tile plays it again
    property int replays: 0

    // Points are fractions of the desk, or of the focused column when `col` is set.
    readonly property var specs: ({
            "ws": { dev: "pad", n: 3, from: [0.5, 0.7], to: [0.5, 0.35] },
            "cols": { dev: "pad", n: 3, from: [0.65, 0.55], to: [0.35, 0.55] },
            "ov": { dev: "pad", n: 4, from: [0.5, 0.7], to: [0.5, 0.35] },
            "view": { dev: "mouse", mod: true, btn: "middle", from: [0.65, 0.5], to: [0.35, 0.5] },
            "move": { dev: "mouse", mod: true, btn: "left", col: true, from: [0.5, 0.5], to: [0.58, 0.42] },
            "resize": { dev: "mouse", mod: true, btn: "right", col: true, from: [1, 0.5], to: [1.2, 0.5] },
            "tmove": { dev: "touch", mod: true, col: true, from: [0.5, 0.5], to: [0.58, 0.42] },
            "float": { dev: "touch", tap: true, col: true, from: [0.5, 0.5], to: [0.48, 0.55] }
        })
    readonly property var spec: specs[gesture] ?? null
    readonly property rect area: spec?.col ? desk.box : Qt.rect(0, 0, desk.width, desk.height)
    readonly property var corners: Corners.globalCorners(NiriPageService.state)
    readonly property int cornerCount: Object.values(corners).filter(a => a !== "none").length

    property real handIn: 0
    property real t: 0
    property real tapIn: 0

    function replay() {
        play.stop();
        handIn = 0;
        t = 0;
        tapIn = 0;
        // Not `spec`: its binding may not have caught up with `gesture` inside this handler.
        if (!specs[gesture])
            return;
        if (SettingsData.reduceMotion || !visible) {
            handIn = 1;
            t = 1;
            tapIn = 1;
            return;
        }
        play.start();
    }

    onGestureChanged: replay()
    onReplaysChanged: replay()

    width: parent?.width ?? 0
    spacing: Theme.spacingM

    SequentialAnimation {
        id: play

        NumberAnimation {
            target: root
            property: "handIn"
            from: 0
            to: 1
            duration: Theme.mediumDuration
        }
        NumberAnimation {
            target: root
            property: "t"
            from: 0
            to: 1
            duration: Theme.longDuration
            easing.type: Theme.standardEasing
        }
        NumberAnimation {
            target: root
            property: "tapIn"
            from: 0
            to: 1
            duration: Theme.shortDuration
        }
    }

    Row {
        width: root.width
        spacing: Theme.spacingS

        NiriSideHead {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (picker.visible ? picker.width + parent.spacing : 0)
            icon: "swipe"
            title: I18n.tr("Hover a gesture to watch it", "niri gestures preview")
        }

        DButtonGroup {
            id: picker
            anchors.verticalCenter: parent.verticalCenter
            visible: desk.outputWorkspaces.length > 1
            model: desk.outputWorkspaces.map(w => ({
                        "text": String(w.name || w.idx)
                    }))
            currentIndex: desk.outputWorkspaces.findIndex(w => String(w.id) === String(desk.shownWorkspaceId))
            Accessible.name: I18n.tr("Workspace shown", "niri page: picks the workspace drawn by the mini desktop")
            onSelectionChanged: (index, selected) => {
                if (selected)
                    desk.pickedWorkspaceId = desk.outputWorkspaces[index]?.id ?? null;
            }
        }
    }

    GestDesk {
        id: desk

        width: root.width
        fx: root.gesture === "view" ? "cols" : root.gesture === "tmove" ? "move" : root.gesture
        t: root.t
        corners: root.corners

        GestHand {
            spec: root.spec
            tapIn: root.tapIn
            pressIn: root.t
            opacity: root.handIn
            // A resize drag ends past the column edge: clamp the fraction so the pressed button stays in view
            x: root.spec ? root.area.x + root.area.width * Math.max(0.05, Math.min(root.spec.from[0] + (root.spec.to[0] - root.spec.from[0]) * root.t, 0.94)) : 0
            y: root.spec ? root.area.y + root.area.height * (root.spec.from[1] + (root.spec.to[1] - root.spec.from[1]) * root.t) : 0
        }
    }

    // The hint line sits under the column the gesture acts on. Its height is kept while empty: if the
    // cards below shifted on hover, the pointer would cross the tile edge and restart the animation forever.
    Item {
        width: root.width
        height: Theme.buttonHeightM

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.spec !== null ? 1 : 0
                name: root.spec?.dev === "mouse" ? "mouse" : root.spec?.dev === "touch" ? "touch_app" : "swipe"
                size: Theme.iconSizeMedium
                color: Theme.primary
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, root.width - Theme.iconSizeMedium - Theme.spacingS)
                text: root.spec ? root.sentence : ""
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }
        }
    }

    Rectangle {
        width: pill.implicitWidth + Theme.spacingS * 2
        height: pill.implicitHeight + Theme.spacingS
        radius: Theme.cornerRadiusS
        color: Theme.surface
        border.width: Theme.outlineWidth
        border.color: Theme.outlineVariant

        StyledText {
            id: pill
            anchors.centerIn: parent
            text: root.cornerCount === 1 ? I18n.tr("1 hot corner", "niri gestures preview: active corners") : I18n.tr("%1 hot corners", "niri gestures preview: active corners").arg(root.cornerCount)
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }
    }
}
