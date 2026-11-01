import QtQuick
import qs.Common
import qs.Services
import "../../../../Common/niri/desk.js" as Desk

// What a drawn desk shows: the focused output's workspace in niri, with the page's look keys.
// An Item, not a QtObject, so it can read its window's screen while niri has not reported the output.
Item {
    id: root

    property var pickedWorkspaceId: null

    readonly property var deskKeys: ["look.gaps", "look.ringOn", "look.ringWidth", "look.ringColor", "look.borderOn", "look.borderWidth", "look.borderColor", "look.radius", "look.shadowOn", "look.blurOn", "columns.centerFocused"]
    readonly property var liveKeys: deskKeys.reduce((m, k) => {
        m[k] = NiriPageService.get(k);
        return m;
    }, {})
    readonly property var deskContext: ({
            barSpacing: SettingsData.getPrimaryBarConfig()?.spacing,
            themeRadius: Theme.cornerRadiusL
        })
    // Columns are measured with the gaps niri draws now, not previewed ones
    readonly property var baseState: Desk.baseState(liveKeys, deskContext)

    readonly property var workspace: NiriService.workspaces[NiriService.focusedWorkspaceId] ?? null
    readonly property string outputName: workspace?.output ?? ""
    readonly property var outputSize: Desk.outputSize(NiriService.outputs[outputName], {
        name: Screen.name,
        width: Screen.width,
        height: Screen.height
    })
    readonly property var outputWorkspaces: NiriService.allWorkspaces.filter(w => w.output === outputName)
    readonly property var shownWorkspaceId: outputWorkspaces.some(w => String(w.id) === String(pickedWorkspaceId)) ? pickedWorkspaceId : NiriService.focusedWorkspaceId
    readonly property var columns: Desk.columns(NiriService.windows, shownWorkspaceId, outputSize.width, baseState.gaps)
    readonly property var floats: Desk.floating(NiriService.windows, shownWorkspaceId)
    readonly property bool barAtBottom: SettingsData.getPrimaryBarConfig()?.position === SettingsData.Position.Bottom
}
