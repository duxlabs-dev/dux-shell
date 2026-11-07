import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DFloatingWindow {
    id: root
    readonly property var log: Log.scoped("WorkspaceRenameModal")

    objectName: "workspaceRenameModal"
    title: I18n.tr("Rename Workspace")
    minimumSize: Qt.size(400, renameDialog.implicitHeight)
    maximumSize: Qt.size(400, renameDialog.implicitHeight)
    implicitWidth: minimumSize.width
    implicitHeight: minimumSize.height
    visible: false

    onClosed: hide()

    function show(name) {
        nameInput.text = name;
        visible = true;
        Qt.callLater(() => nameInput.forceActiveFocus());
    }

    function hide() {
        visible = false;
    }

    function submitAndClose() {
        if (!root.visible)
            return;
        renameWorkspace(nameInput.text);
        hide();
    }

    function focusedWorkspaceName() {
        if (CompositorService.isNiri)
            return NiriService.workspaces[NiriService.focusedWorkspaceId]?.name ?? "";
        if (CompositorService.isHyprland)
            return HyprlandService.focusedWorkspaceName();
        return "";
    }

    function renameWorkspace(name) {
        if (CompositorService.isNiri) {
            NiriService.renameWorkspace(name);
        } else if (CompositorService.isHyprland) {
            HyprlandService.renameWorkspace(name);
        } else {
            log.warn("rename not supported for this compositor");
        }
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(() => nameInput.forceActiveFocus());
            return;
        }
        nameInput.text = "";
    }

    DDialog {
        id: renameDialog

        anchors.fill: parent
        windowControls: renameWindowControls
        title: root.title
        supportingText: I18n.tr("Enter a new name for this workspace")
        onAccepted: root.submitAndClose()
        onRejected: root.hide()

        DTextField {
            id: nameInput

            width: parent.width
            outlined: true
            controlHeight: Theme.fieldHeightLarge
            labelText: I18n.tr("Workspace name")
            leftIconName: "edit"
            enabled: root.visible
            onAccepted: root.submitAndClose()
        }

        actions: [
            DButton {
                maximumWidth: renameDialog.actionWidth
                wrapText: true
                text: I18n.tr("Cancel")
                variant: "text"
                onClicked: root.hide()
            },
            DButton {
                maximumWidth: renameDialog.actionWidth
                wrapText: true
                text: I18n.tr("Rename", "verb, rename button")
                onClicked: root.submitAndClose()
            }
        ]
    }

    FloatingWindowControls {
        id: renameWindowControls
        targetWindow: root
    }
}
