pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings
import qs.Modules.Settings.Widgets
import qs.Widgets

DFloatingWindow {
    id: root

    readonly property string pendingToken: GlobalShortcutsService.prompts[0]?.token ?? ""
    property var prompt: null
    property var draftKeys: ({})
    property var editingShortcut: null

    readonly property var shortcuts: prompt?.shortcuts ?? []
    readonly property string appId: prompt?.appId ?? ""
    readonly property string appName: appId ? GlobalShortcutsService.appName(appId) : ""
    readonly property bool configuring: prompt?.kind === "configure"
    readonly property var knownBinds: GlobalShortcutsService.savedBinds().filter(bind => bind.appId !== appId).concat(shortcuts.map(shortcut => GlobalShortcutsService.bindEntry(appId, shortcut, keyFor(shortcut))))
    readonly property real dialogHeight: editor.item?.implicitHeight ?? dialog.implicitHeight

    function loadPrompt() {
        editor.hide();
        prompt = GlobalShortcutsService.prompts[0] ?? null;
        draftKeys = ({});
        visible = prompt !== null;
    }

    function keyFor(shortcut) {
        return draftKeys[shortcut.id] ?? shortcut.triggers?.[0] ?? "";
    }

    function setKey(shortcutId, key) {
        const keys = Object.assign({}, draftKeys);
        keys[shortcutId] = key;
        draftKeys = keys;
    }

    function editShortcut(shortcut) {
        editingShortcut = shortcut;
        editor.show(keyFor(shortcut));
    }

    function saveKey(key) {
        setKey(editingShortcut.id, key);
        editor.hide();
    }

    // Focus left on a row's edit button would make the next Enter reopen it instead of adding.
    function parkFocus() {
        const focused = dialog.Window.activeFocusItem;
        if (focused && focused !== dialog)
            focused.focus = false;
        dialog.forceActiveFocus();
    }

    function allow() {
        if (!prompt)
            return;
        const edits = Object.keys(draftKeys).map(shortcutId => ({
                    "id": shortcutId,
                    "triggers": draftKeys[shortcutId] ? [draftKeys[shortcutId]] : []
                }));
        GlobalShortcutsService.submit(prompt.token, edits);
    }

    function deny() {
        if (!prompt)
            return;
        GlobalShortcutsService.cancel(prompt.token);
    }

    objectName: "globalShortcutsModal"
    title: I18n.tr("Keyboard shortcuts")
    minimumSize: Qt.size(Theme.dialogMaxWidth, heightWithin(dialogHeight, Theme.spacingXL * 2))
    maximumSize: minimumSize
    implicitWidth: minimumSize.width
    implicitHeight: minimumSize.height
    visible: false

    onPendingTokenChanged: loadPrompt()
    onClosed: {
        visible = false;
        deny();
    }
    onVisibleChanged: {
        if (visible) {
            GlobalShortcutsService.retainBinds();
            Qt.callLater(parkFocus);
            return;
        }
        GlobalShortcutsService.releaseBinds();
    }
    Component.onCompleted: loadPrompt()
    Component.onDestruction: {
        if (visible)
            GlobalShortcutsService.releaseBinds();
    }

    DDialog {
        id: dialog

        anchors.fill: parent
        visible: !editor.opened
        focus: !editor.opened
        windowControls: controls
        title: root.title
        supportingText: I18n.tr("%1 can use these shortcuts from any window. Change them later in Settings.", "global shortcuts permission dialog, %1 is an app name").arg(root.appName)
        onAccepted: root.allow()
        onRejected: root.deny()

        SettingsGroup {
            Repeater {
                model: root.shortcuts

                delegate: GlobalShortcutRow {
                    id: shortcutRow

                    required property var modelData

                    shortcut: modelData
                    key: root.keyFor(modelData)
                    conflicts: GlobalShortcutsService.conflicts(key, root.appId, modelData.id, root.knownBinds)
                    onEditRequested: root.editShortcut(shortcutRow.modelData)
                    onResetRequested: root.setKey(shortcutRow.modelData.id, shortcutRow.preferredKey)
                }
            }
        }

        actions: [
            DButton {
                maximumWidth: dialog.actionWidth
                wrapText: true
                text: I18n.tr("Cancel")
                variant: "text"
                onClicked: root.deny()
            },
            DButton {
                maximumWidth: dialog.actionWidth
                wrapText: true
                text: root.configuring ? I18n.tr("Save") : I18n.tr("Add")
                onClicked: root.allow()
            }
        ]
    }

    SettingsShortcutDialog {
        id: editor
        embedded: true
        windowControls: controls
        acceptText: I18n.tr("Apply")
        supportingText: root.editingShortcut?.description ?? ""
        conflicts: GlobalShortcutsService.conflicts(key, root.appId, root.editingShortcut?.id ?? "", root.knownBinds)
        onAccepted: key => root.saveKey(key)
        onClosed: root.parkFocus()
    }

    FloatingWindowControls {
        id: controls
        targetWindow: root
    }
}
