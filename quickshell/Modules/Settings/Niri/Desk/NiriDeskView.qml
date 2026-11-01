pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets
import "../../../../Common/niri/desk.js" as Desk

// Rounded clip like a real screen: columns scrolled out of view are cut at its edges
ClippingRectangle {
    id: root

    property var deskState: ({})
    property var columns: []
    property var floats: []
    required property real outputWidth
    required property real outputHeight
    // Whose wallpaper is drawn behind the windows
    property string screenName: ""
    property var workspaces: []
    // Only false today (the gesture scene): a true value would need edit affordances back
    property bool editable: false
    property bool barAtBottom: false
    // Mockup's "Loading config": windows hide under a scrim while niri loads the written config
    property bool loading: false

    // niri keeps the view where it was until focus leaves it, so the offset carries over between layouts
    property real viewOffset: NaN

    readonly property real barHeight: Theme.spacingM
    readonly property var shown: deskState
    readonly property real areaHeight: Desk.workArea(columns, outputHeight)
    readonly property var geo: Desk.layout(columns, floats, {
        outputWidth: outputWidth,
        height: areaHeight,
        top: barAtBottom ? 0 : outputHeight - areaHeight,
        gaps: shown.gaps,
        columnWidth: shown.columnWidth
    })
    readonly property var tilesById: geo.tiles.reduce((m, t) => {
        m[t.id] = t;
        return m;
    }, {})
    readonly property var focusedColumn: geo.columns[geo.focus] ?? null
    readonly property real kx: width / outputWidth
    readonly property real ky: scene.height / areaHeight

    function themeColor(c) {
        return c === "secondary" ? Theme.secondary : c === "tertiary" ? Theme.tertiary : c?.startsWith("#") ? c : Theme.primary;
    }

    onGeoChanged: viewOffset = Desk.follow(viewOffset, focusedColumn, outputWidth, shown.gaps, shown.centerFocused)
    Component.onCompleted: viewOffset = Desk.follow(viewOffset, focusedColumn, outputWidth, shown.gaps, shown.centerFocused)

    implicitHeight: Math.round(width * outputHeight / outputWidth)
    radius: Theme.cornerRadius
    color: "transparent"

    NiriWallpaper {
        anchors.fill: parent
        screenName: root.screenName
    }

    Rectangle {
        id: bar
        y: root.barAtBottom ? root.height - height : 0
        width: parent.width
        height: root.barHeight
        color: Theme.withAlpha(Theme.surface, Theme.pendingOpacity)

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            Repeater {
                model: root.workspaces

                Rectangle {
                    required property var modelData
                    width: Theme.spacingM
                    height: Theme.spacingXS
                    radius: height / 2
                    color: modelData.is_active ? Theme.primary : Theme.surfaceTextAlpha
                }
            }
        }
    }

    Item {
        id: scene
        anchors.top: root.barAtBottom ? parent.top : bar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: root.barAtBottom ? bar.top : parent.bottom
        opacity: root.loading ? 0 : 1

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingXS
            visible: root.geo.tiles.length === 0

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "desktop_windows"
                size: Theme.iconSizeLarge
                color: Theme.surfaceTextMedium
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("No windows on this workspace", "niri page: mini desktop when the workspace is empty")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
        }

        // Keyed by window id so a moving window keeps its delegate and eases to its new place
        Repeater {
            model: ScriptModel {
                values: root.geo.tiles.map(t => t.id)
            }

            NiriDeskTile {
                id: tile
                required property var modelData
                readonly property var t: root.tilesById[modelData] ?? null
                readonly property real k: root.kx

                z: t?.floating ? 1 : 0
                x: ((t?.x ?? 0) - (t?.floating ? 0 : root.viewOffset)) * k
                y: (t?.y ?? 0) * root.ky
                width: (t?.width ?? 0) * k
                height: (t?.height ?? 0) * root.ky
                appId: t?.appId ?? ""
                title: t?.title ?? ""
                active: t?.focused ?? false
                radius: (root.shown.radius ?? 0) * k
                ringWidth: root.shown.ringOn ? Math.max(1, root.shown.ringWidth * k) : 0
                ringColor: root.themeColor(root.shown.ringColor)
                borderOn: root.shown.borderOn === true
                borderWidth: Math.max(1, (root.shown.borderWidth ?? 0) * k)
                borderColor: root.themeColor(root.shown.borderColor)
                borderInactiveColor: Theme.outline
                blurOn: root.shown.blurOn === true
                shadowOn: root.shown.shadowOn === true
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: title || appId

                FocusRing {}
            }
        }
    }

    Rectangle {
        anchors.fill: scene
        z: 3
        visible: root.loading
        color: Theme.withAlpha(Theme.surface, Theme.scrimAlpha)

        StyledText {
            anchors.centerIn: parent
            text: I18n.tr("Reading config…", "niri page: mini desktop skeleton while niri loads the config")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
        }
    }
}
