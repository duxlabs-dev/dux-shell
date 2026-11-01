pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/niri/sections/corners.js" as Corners

Singleton {
    id: root

    // The key DMS stores a screen's niri settings under, the same one outputs.kdl is written from.
    function screenId(name) {
        const output = NiriService.outputs[name];
        return output ? NiriService.getOutputIdentifier(output, name) : name;
    }

    function cornersFor(name) {
        const id = root.screenId(name);
        const state = NiriPageService.state;
        return Corners.screenCorners(state, SessionData.getNiriOutputSetting(id, "hotCorners", null), state["corners.screens"]?.[id]);
    }

    function zonesFor(name) {
        return Corners.zones(root.cornersFor(name));
    }

    function trigger(name, corner) {
        const command = Corners.commands[root.cornersFor(name)[corner]];
        if (!command)
            return;
        Quickshell.execDetached(command);
    }
}
