pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    property var parentModal: null
    property string editingAppId: ""
    property var editingShortcut: null

    readonly property var savedBinds: GlobalShortcutsService.savedBinds()

    function editShortcut(appId, shortcut) {
        editingAppId = appId;
        editingShortcut = shortcut;
        editor.show(shortcut.triggers?.[0] ?? "");
    }

    function saveKey(key) {
        GlobalShortcutsService.setTriggers(editingAppId, editingShortcut.id, key ? [key] : []);
        editor.hide();
    }

    function confirmRemoveAll(appId, appName) {
        removeConfirm.showWithOptions({
            "title": I18n.tr("Remove all shortcuts"),
            "message": I18n.tr("Remove every global shortcut %1 has registered?", "remove global shortcuts confirmation, %1 is an app name").arg(appName),
            "confirmText": I18n.tr("Remove"),
            "danger": true,
            "onConfirm": () => GlobalShortcutsService.remove(appId)
        });
    }

    Component.onCompleted: GlobalShortcutsService.retainBinds()
    Component.onDestruction: GlobalShortcutsService.releaseBinds()

    SettingsDialogFocusTrap {
        dialog: editor.item
        active: editor.opened && !removeConfirm.visible
    }

    SettingsPage {
        SettingsDeferred {
            when: GlobalShortcutsService.apps.length === 0

            SettingsCard {

                SettingsRow {
                    subtitle: I18n.tr("Apps that register global shortcuts appear here.", "global shortcuts settings page empty state")
                }
            }
        }

        Repeater {
            model: GlobalShortcutsService.apps

            delegate: SettingsCard {
                id: appCard

                required property var modelData
                readonly property string appName: GlobalShortcutsService.appName(modelData.id)

                title: appName
                headerActions: DButton {
                    text: I18n.tr("Remove all shortcuts")
                    iconName: "delete"
                    buttonHeight: Theme.buttonHeightXS
                    variant: "text"
                    onClicked: root.confirmRemoveAll(appCard.modelData.id, appCard.appName)
                }

                Repeater {
                    model: appCard.modelData.shortcuts ?? []

                    delegate: GlobalShortcutRow {
                        id: shortcutRow

                        required property var modelData

                        shortcut: modelData
                        conflicts: GlobalShortcutsService.conflicts(key, appCard.modelData.id, modelData.id, root.savedBinds)
                        onEditRequested: root.editShortcut(appCard.modelData.id, shortcutRow.modelData)
                        onResetRequested: GlobalShortcutsService.setTriggers(appCard.modelData.id, shortcutRow.modelData.id, shortcutRow.modelData.preferred ?? [])
                    }
                }
            }
        }
    }

    SettingsShortcutDialog {
        id: editor
        parent: root.parentModal?.modalFocusScope ?? root
        supportingText: root.editingShortcut?.description ?? ""
        conflicts: GlobalShortcutsService.conflicts(key, root.editingAppId, root.editingShortcut?.id ?? "", root.savedBinds)
        onAccepted: key => root.saveKey(key)
    }

    ConfirmDialogOverlay {
        id: removeConfirm
        parent: root.parentModal?.modalFocusScope ?? root
        z: 1001
    }
}
