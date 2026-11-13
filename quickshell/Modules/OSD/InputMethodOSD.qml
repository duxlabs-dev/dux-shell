import QtQuick
import qs.Common
import qs.Services

LabelOSD {
    id: root

    osdKind: "inputMethod"
    iconName: "language"
    label: currentIM
    extraWidthReserve: Theme.spacingM * 2

    property string lastIM: ""
    property bool imInitialized: false
    readonly property string currentIM: Fcitx5Service.currentIMLabel

    function observeIM() {
        if (currentIM === "") {
            imInitialized = false;
            lastIM = "";
            return;
        }
        if (!imInitialized) {
            lastIM = currentIM;
            imInitialized = true;
            return;
        }
        if (lastIM === currentIM)
            return;
        lastIM = currentIM;
        if (SettingsData.osdInputMethodEnabled)
            show();
    }

    onCurrentIMChanged: observeIM()

    Component.onCompleted: {
        Fcitx5Service.consumers++;
        observeIM();
    }
    Component.onDestruction: Fcitx5Service.consumers--
}
