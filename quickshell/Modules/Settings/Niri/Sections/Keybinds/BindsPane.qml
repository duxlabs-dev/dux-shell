pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import qs.Common
import qs.Modals.Common
import qs.Modules.Settings
import qs.Services
import qs.DCommon.Widgets
import "../../../../../Common/niri/keymaps.js" as Keymaps

// Side pane of the keybinds section: the shortcuts of the key or category picked on the keyboard, plus New and the ⋯ tools
Item {
    id: root

    // "", "new", "menu", "packs" or "export"
    property string mode: ""
    // "all", "dms" (dms/binds.kdl) or "niri" (config.kdl)
    property string origin: "all"
    property string newKey: ""

    readonly property var pick: SettingsUiState.niriKeyPick
    readonly property var groups: KeybindsService._dataVersion >= 0 ? KeybindsService.getFlatBinds() : []
    readonly property var listed: {
        const rows = [];
        if (!pick)
            return rows;
        for (const group of groups) {
            if (!pick.key && group.category.toLowerCase() !== String(pick.category ?? "").toLowerCase())
                continue;
            group.keys.forEach((key, index) => {
                if (origin !== "all" && originOf(key) !== origin)
                    return;
                if (pick.key && norm(key.key) !== norm(pick.key))
                    return;
                rows.push({
                    "group": group,
                    "index": index
                });
            });
        }
        return rows;
    }

    function norm(key) {
        return Keymaps.chordId(key, KeybindsService.modKey);
    }

    function originOf(key) {
        return key.source === "config" ? "niri" : "dms";
    }

    function close() {
        if (mode !== "") {
            mode = "";
            return;
        }
        SettingsUiState.niriKeyPick = null;
    }

    function openNew(key) {
        newKey = key ?? "";
        mode = "new";
    }

    function edit(group, index) {
        editorLoader.active = true;
        (editorLoader.item as KeybindEditorDialog).present(group, index, false, null);
    }

    function confirmRemove(key) {
        removeConfirm.showWithOptions({
            "title": I18n.tr("Remove Shortcut?"),
            "message": I18n.tr("Remove the shortcut %1?", "remove shortcut confirmation, %1 is the key combination").arg(key),
            "confirmText": I18n.tr("Remove"),
            "confirmColor": Theme.error,
            "onConfirm": () => KeybindsService.removeBind(key)
        });
    }

    // Keys bound twice whose extra copy sits in dms/binds.kdl (rule and tests in keymaps.js)
    readonly property var doubleKeys: Keymaps.doubleKeys(groups, KeybindsService.modKey)
    // The records the last clean-up removed, kept for one Undo (the mockup keeps "Annuler possible")
    property var cleaned: []
    property var writeQueue: []

    function cleanDoubles() {
        const keys = doubleKeys;
        if (keys.length === 0)
            return;
        removeConfirm.showWithOptions({
            "title": I18n.tr("Clean up doubles", "niri keybinds, remove the extra binding of a key bound twice"),
            "message": I18n.tr("Remove the DMS copy of %1 keys bound twice? Their other binding stays: %2", "niri keybinds clean up confirmation, %1 is a count, %2 the keys").arg(keys.length).arg(keys.join(", ")),
            "confirmText": I18n.tr("Remove"),
            "confirmColor": Theme.error,
            "onConfirm": () => {
                root.cleaned = Keymaps.doubleBinds(groups, KeybindsService.modKey);
                root.writeQueue = keys.map(key => ({
                    "key": key,
                    "restore": null
                }));
                root.writeNext();
            }
        });
    }

    function undoClean() {
        if (cleaned.length === 0 || writeQueue.length > 0)
            return;
        writeQueue = cleaned.map(record => ({
            "key": record.key,
            "restore": record
        }));
        cleaned = [];
        writeNext();
    }

    // removeBind and saveBind each have one process: the next key goes once the list reloaded after the previous one
    function writeNext() {
        if (KeybindsService.bindMutationBusy || writeQueue.length === 0)
            return;
        const job = writeQueue[0];
        writeQueue = writeQueue.slice(1);
        if (job.restore)
            KeybindsService.saveBind(job.key, job.restore);
        else
            KeybindsService.removeBind(job.key);
    }

    Connections {
        target: KeybindsService
        enabled: root.writeQueue.length > 0
        function onBindsLoaded() {
            root.writeNext();
        }
        // A failed save reloads nothing: the queue would stall without this
        function onBindSaveCompleted(success) {
            if (!success)
                root.writeNext();
        }
    }

    onPickChanged: mode = ""

    Component.onCompleted: {
        KeybindsService.addRef();
        if (KeybindsService.available && (KeybindsService._dataVersion === 0 || KeybindsService.keybinds?.provider !== KeybindsService.currentProvider))
            KeybindsService.loadBinds();
    }
    Component.onDestruction: KeybindsService.removeRef()

    BindsHead {
        id: head
        width: parent.width
        pane: root
    }

    DFlickable {
        id: flick
        anchors.top: head.bottom
        anchors.topMargin: Theme.spacingM
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        contentWidth: width
        contentHeight: body.height

        Column {
            id: body
            width: flick.width
            spacing: Theme.spacingS

            // One Undo for the last clean-up, standing in for the mockup snack bar's Undo
            Rectangle {
                id: undoPlate

                visible: root.cleaned.length > 0
                width: parent.width
                height: Theme.listItemHeight
                radius: Theme.cornerRadiusM
                color: Theme.surfaceContainerHigh

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "cleaning_services"
                        size: Theme.iconSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Cleaned up %1 doubles", "niri keybinds, the clean-up just removed the extra copies; %1 is a count").arg(root.cleaned.length)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                }

                DActionButton {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "undo"
                    tooltipText: I18n.tr("Undo", "niri keybinds, put back the shortcuts the clean-up removed")
                    Accessible.name: tooltipText
                    onClicked: root.undoClean()
                }
            }

            BindsInclude {
                width: parent.width
            }

            // A source URL, not the type: the panels are not compiled before their first open,
            // and a URL item cannot take required properties: they land through Binding after creation
            Loader {
                id: addLoader
                width: parent.width
                active: root.mode === "new"
                visible: active
                source: "BindsAdd.qml"
                Binding { target: addLoader.item; property: "groups"; value: root.groups }
                Binding { target: addLoader.item; property: "key"; value: root.newKey }
                Connections {
                    target: addLoader.item
                    function onDone() {
                        root.mode = ""
                    }
                }
            }

            Loader {
                id: menuLoader
                width: parent.width
                active: root.mode === "menu"
                visible: active
                source: "BindsMenu.qml"
                Binding { target: menuLoader.item; property: "pane"; value: root }
            }

            Loader {
                id: packsLoader
                width: parent.width
                active: root.mode === "packs"
                visible: active
                source: "BindsPacks.qml"
                Binding { target: packsLoader.item; property: "pane"; value: root }
            }

            Loader {
                id: exportLoader
                width: parent.width
                active: root.mode === "export"
                visible: active
                source: "BindsExport.qml"
                Binding { target: exportLoader.item; property: "groups"; value: root.groups }
            }

            BindsEmpty {
                visible: root.mode === "" && root.listed.length === 0
                width: parent.width
                pane: root
            }

            Repeater {
                model: root.mode === "" ? root.listed : []

                delegate: BindsRow {
                    required property var modelData

                    width: body.width
                    group: modelData.group
                    keyData: modelData.group.keys[modelData.index]
                    origin: root.originOf(keyData)
                    onEditRequested: root.edit(modelData.group, modelData.index)
                    onRemoveRequested: root.confirmRemove(keyData.key)
                }
            }
        }
    }

    // Dialogs cover the whole settings window, like the old Keybinds tab
    Loader {
        id: editorLoader
        parent: root.Window.window?.contentItem ?? root
        anchors.fill: parent
        z: 100
        active: false

        sourceComponent: KeybindEditorDialog {
            id: editor
            panelWindow: root.QsWindow.window
            readOnly: KeybindsService.readOnly
            busy: KeybindsService.saving
            onSaveRequested: (originalKey, data) => {
                KeybindsService.saveBind(originalKey, data);
                editor.opened = false;
            }
            onResetRequested: key => {
                KeybindsService.resetBind(key);
                editor.opened = false;
            }
            onRejected: editor.opened = false
        }
    }

    ConfirmDialogOverlay {
        id: removeConfirm
        parent: root.Window.window?.contentItem ?? root
        z: 101
    }
}
