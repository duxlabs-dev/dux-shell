pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Drawer

// The right column: the section's own side pane on top when it declares one, the KDL drawer under it.
Column {
    id: root

    property bool wide: false
    property bool expert: false
    property string sectionId: ""
    property string title: ""
    property Component sidePane: null
    // A closed drawer still rebuilds the section KDL on every page or theme change: create it on first use
    property bool drawerWanted: false
    readonly property NiriKdlDrawer drawer: drawerLoader.item as NiriKdlDrawer

    readonly property bool keybinds: sectionId === "keybinds"
    readonly property Component pane: sidePane
    readonly property real paneWidth: Math.min(width - Theme.spacingL * 2, wide || keybinds ? Infinity : width)
    readonly property real paneHeight: wide ? Math.max(Theme.listItemHeight * 3, (root.parent?.height ?? 0) - topPadding - bottomPadding - (drawerLoader.visible ? drawerLoader.height + spacing : 0)) : Theme.listItemHeight * 8

    topPadding: Theme.spacingL
    bottomPadding: Theme.spacingL
    spacing: Theme.spacingL

    Loader {
        active: root.pane !== null
        visible: active
        x: Theme.spacingL
        width: root.paneWidth
        height: active ? root.paneHeight : 0
        sourceComponent: root.pane
    }

    // The drawer's own open flag is the only open state; leaving Expert unloads it, which closes it
    Loader {
        id: drawerLoader
        active: root.expert && root.drawerWanted
        visible: root.drawer?.open ?? false
        width: parent.width

        sourceComponent: NiriKdlDrawer {
            sectionId: root.sectionId
            title: root.title
        }
    }
}