pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/niri/colwidth.js" as ColWidth
import "../Common/niri/sections/columns.js" as Columns

Singleton {
    id: root

    // Mod+R cycle (colwidth.js): forgotten on any window change the key did not ask for.
    // NiriService calls observe() on each windows change: a Connections here would be a creation-time cycle.
    property var _state: null

    function observe() {
        if (root._state)
            root._state = ColWidth.observe(root._state, ColWidth.focused(NiriService.windows));
    }

    // Returns the IPC reply: CYCLED, NATIVE (option off or no tiled window focused: niri's stock switch) or FAILED.
    function cycleColumnWidth() {
        const win = ColWidth.target(SettingsData.niriPage, Columns.defaults, NiriService.windows);
        const outputName = win ? NiriService.workspaces[win.workspace_id]?.output : "";
        const outputWidth = NiriService.outputs[outputName]?.logical?.width ?? 0;
        const presets = SettingsData.niriPage["columns.presetWidths"] ?? Columns.defaults["columns.presetWidths"];
        const next = ColWidth.press(root._state, win, ColWidth.atTop(win?.width, outputWidth, presets));
        root._state = next.state;
        if (!NiriService.send({
            "Action": next.action
        }))
            return "COLUMN_WIDTH_FAILED";
        return win ? "COLUMN_WIDTH_CYCLED" : "COLUMN_WIDTH_NATIVE";
    }
}
