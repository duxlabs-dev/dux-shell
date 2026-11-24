import QtQuick
import qs.Common
import qs.Services

SettingsRow {
    id: root

    property var parentModal: null
    property string ipcTarget: ""
    property string action: ""
    property string search: ""

    readonly property int keybindDataVersion: KeybindsService._dataVersion

    function keysLabel() {
        void (keybindDataVersion);
        if (!KeybindsService.available)
            return I18n.tr("Manual config");
        const keys = KeybindsService.keysForAction(action);
        if (!keys || keys.length === 0)
            return I18n.tr("Not bound");
        return keys.join(", ");
    }

    iconName: "keyboard"
    title: I18n.tr("Shortcut", "noun, keyboard shortcut row in settings")
    subtitle: KeybindsService.available ? "" : I18n.tr("Bind the %1 IPC action in your compositor config.", "settings shortcut row hint, %1 is the ipc target name").arg(ipcTarget)
    trailingBadge: keysLabel()
    trailingBadgeColor: Theme.primary
    showChevron: KeybindsService.available
    clickable: KeybindsService.available
    onClicked: {
        if (!parentModal)
            return;
        if (typeof parentModal.showKeybindsSearch === "function")
            parentModal.showKeybindsSearch(search);
        else
            parentModal.navigateTo("keybinds");
    }

    Component.onCompleted: {
        KeybindsService.addRef();
        if (KeybindsService.available)
            KeybindsService.loadBinds(false);
    }

    Component.onDestruction: KeybindsService.removeRef()
}
