pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import "../../../../../Common/niri/sections/input.js" as InputSection

// A cursor of an installed theme, drawn for real: the theme's XCursor or PNG file
// renders, and the plain arrow pair shows while the file is being read or when
// the theme cannot be read at all.
Item {
    id: root

    property string theme: ""
    property string role: "default"
    property real displaySize: Theme.iconSizeLarge

    // "System Default" follows whatever the desktop picked, not a theme of that name.
    readonly property string resolvedTheme: theme === "System Default" ? SettingsData.systemDefaultCursorTheme : theme
    property string dataUrl: ""
    property int loadId: 0
    // Proc debounces by id, so each art gets its own even when two load the same cursor.
    property string probeId: ""

    implicitWidth: root.displaySize
    implicitHeight: root.displaySize
    Accessible.ignored: true

    Component.onCompleted: {
        root.probeId = Math.random().toString(36).slice(2, 9);
        reload();
    }
    onResolvedThemeChanged: reload()
    onRoleChanged: reload()

    function dataDirs() {
        const xdg = Quickshell.env("XDG_DATA_DIRS") || "";
        const local = Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
        return xdg.trim() !== "" ? xdg.split(":").concat([local]) : ["/usr/share", "/usr/local/share", local];
    }

    // One short probe prints the first readable cursor file as base64 (QML cannot read
    // local files itself); the loadId drops the answer of a superseded reload.
    function reload() {
        root.loadId += 1;
        root.dataUrl = "";
        if (root.resolvedTheme === "")
            return;
        const home = Paths.strip(StandardPaths.writableLocation(StandardPaths.HomeLocation));
        const dirs = InputSection.cursorThemeDirs(dataDirs(), home, root.resolvedTheme);
        const id = root.loadId;
        Proc.runCommand(root.probeId, InputSection.cursorProbe(dirs, root.role), (output, exitCode) => {
            if (id !== root.loadId || exitCode !== 0 || !output || root.dataUrl !== "")
                return;
            const bytes = InputSection.b64decode(output);
            if (InputSection.isPng(bytes)) {
                root.dataUrl = "data:image/png;base64," + InputSection.b64(bytes);
                return;
            }
            const image = InputSection.pickCursorImage(InputSection.xcursorImages(bytes), Math.round(root.displaySize * 2));
            if (image)
                root.dataUrl = InputSection.pngDataUrl(image.pixels, image.width, image.height);
        }, 0, undefined, root);
    }

    function looksLight(name) {
        return /white|light|snow|ice/i.test(name);
    }

    Image {
        anchors.centerIn: parent
        visible: root.dataUrl !== ""
        width: root.displaySize
        height: root.displaySize
        source: root.dataUrl
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    // The same drawn arrow pair as before, for a theme that reads wrong or not yet.
    Item {
        anchors.centerIn: parent
        visible: root.dataUrl === ""
        width: root.displaySize
        height: root.displaySize

        DIcon {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: Theme.outlineWidth
            anchors.verticalCenterOffset: Theme.outlineWidth
            name: "arrow_selector_tool"
            filled: true
            size: root.displaySize
            color: root.looksLight(root.resolvedTheme) ? Theme.contrastDark : Theme.contrastLight
        }

        DIcon {
            anchors.centerIn: parent
            name: "arrow_selector_tool"
            filled: true
            size: root.displaySize - Theme.outlineWidthFocused
            color: root.looksLight(root.resolvedTheme) ? Theme.contrastLight : Theme.contrastDark
        }
    }
}
