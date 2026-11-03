import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.WindowManager
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DOSD {
    id: root

    osdKind: "workspace"

    property string workspaceLabel: ""
    property var lastActiveWorkspaceId: null

    readonly property real horizontalPadding: Theme.spacingL
    readonly property real itemSpacing: Theme.spacingM
    readonly property real textWidth: Math.ceil(textMetrics.width)
    readonly property real digitReserve: Math.ceil(digitMetrics.width)
    readonly property var activeWorkspace: root.getActiveWorkspace()
    readonly property bool useNativeWorkspace: CompositorService.hasWorkspaceIpc
    readonly property bool useExtWorkspace: {
        if (Quickshell.env("DMS_FORCE_EXTWS") === "1")
            return (WindowManager.windowsets?.length ?? 0) > 0;
        if (!CompositorService.compositorDetected || root.useNativeWorkspace)
            return false;
        return (WindowManager.windowsets?.length ?? 0) > 0;
    }

    osdWidth: Math.min(Math.max(140, horizontalPadding * 2 + Theme.buttonHeightS + itemSpacing + textWidth + digitReserve), screenWidth - Theme.spacingM * 2)
    osdHeight: Theme.osdHeight
    autoHideInterval: 1500
    enableMouseInteraction: false

    function inOverview() {
        return root.useNativeWorkspace && CompositorService.overviewActiveForScreen(root.screen?.name);
    }

    function getActiveWorkspace() {
        const screenName = root.screen?.name ?? "";
        if (root.useNativeWorkspace)
            return CompositorService.activeWorkspaceForScreen(screenName);
        if (!root.useExtWorkspace || !root.screen)
            return null;
        const projection = WindowManager.screenProjection(root.screen);
        const ws = projection?.windowsets?.find(w => w.active);
        if (!ws)
            return null;
        const name = (ws.name ?? "").trim();
        const id = ws.id || name;
        if (id === undefined || id === null || id === "")
            return null;
        const parsed = parseInt(name, 10);
        return {
            "id": id,
            "idx": (name !== "" && String(parsed) === name) ? parsed : null,
            "name": name,
            "output": screenName
        };
    }

    function handleWorkspaceChange() {
        if (!SettingsData.osdWorkspaceEnabled)
            return;

        const ws = root.activeWorkspace;
        if (!ws || ws.id === undefined || ws.id === null)
            return;

        if (root.lastActiveWorkspaceId === null) {
            root.lastActiveWorkspaceId = ws.id;
            return;
        }
        if (root.lastActiveWorkspaceId === ws.id)
            return;
        if (root.inOverview())
            return;

        root.lastActiveWorkspaceId = ws.id;
        root.updateWorkspaceInfo(ws);
        root.show();
    }

    function updateWorkspaceInfo(ws) {
        if (!ws)
            return;
        const num = (ws.idx !== undefined && ws.idx !== null && ws.idx > 0) ? ws.idx : (typeof ws.id === "number" && ws.id > 0 ? ws.id : null);
        const name = (ws.name ?? "").trim();

        if (num !== null) {
            if (name !== "" && name !== String(num)) {
                root.workspaceLabel = I18n.tr("Workspace %1: %2", "workspace switch OSD, %1 is workspace number, %2 is workspace name").arg(num).arg(name);
            } else {
                root.workspaceLabel = I18n.tr("Workspace %1", "workspace switch OSD, %1 is workspace number").arg(num);
            }
        } else if (name !== "") {
            root.workspaceLabel = name;
        } else {
            root.workspaceLabel = I18n.tr("Workspace", "fallback label when workspace has no number or name");
        }
    }

    onActiveWorkspaceChanged: root.handleWorkspaceChange()

    Component.onCompleted: root.handleWorkspaceChange()

    StyledTextMetrics {
        id: textMetrics
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        text: root.workspaceLabel
    }

    StyledTextMetrics {
        id: digitMetrics
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        text: "0"
    }

    content: Item {
        anchors.fill: parent

        RowLayout {
            anchors {
                fill: parent
                leftMargin: root.horizontalPadding
                rightMargin: root.horizontalPadding
            }
            spacing: root.itemSpacing

            OsdIcon {
                Layout.alignment: Qt.AlignVCenter
                iconName: "view_module"
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.workspaceLabel
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }
}
