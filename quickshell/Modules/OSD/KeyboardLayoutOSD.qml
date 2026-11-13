import QtQuick
import qs.Common
import qs.Services

LabelOSD {
    id: root

    osdKind: "keyboardLayout"
    iconName: "keyboard"
    label: currentLayout
    extraWidthReserve: Theme.spacingM * 2

    property string lastLayout: ""
    property bool layoutInitialized: false
    readonly property string currentLayout: KeyboardLayoutService.currentLayout

    function observeLayout() {
        if (!KeyboardLayoutService.layoutKnown) {
            layoutInitialized = false;
            lastLayout = "";
            return;
        }
        if (!layoutInitialized) {
            lastLayout = currentLayout;
            layoutInitialized = true;
            return;
        }
        if (lastLayout === currentLayout)
            return;
        lastLayout = currentLayout;
        if (SettingsData.osdKeyboardLayoutEnabled)
            show();
    }

    onCurrentLayoutChanged: observeLayout()

    Component.onCompleted: {
        KeyboardLayoutService.consumers++;
        observeLayout();
    }
    Component.onDestruction: KeyboardLayoutService.consumers--
}
