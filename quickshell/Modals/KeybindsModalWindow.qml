import QtQuick
import qs.Common
import qs.Modals
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DFloatingWindow {
    id: win

    property alias shouldBeVisible: win.visible

    signal floatingToggleRequested

    function show() {
        visible = true;
    }

    function hide() {
        visible = false;
    }

    function toggle() {
        visible = !visible;
    }

    objectName: "keybindsModalWindow"
    title: I18n.tr("Keybinds")
    minimumSize: Qt.size(Math.min(560, Screen.width), Math.min(400, Screen.height))
    implicitWidth: 1000
    implicitHeight: heightWithin(820, 100)
    visible: false

    onVisibleChanged: {
        if (!visible)
            return;
        if (!Object.keys(KeybindsService.cheatsheet).length && KeybindsService.cheatsheetAvailable)
            KeybindsService.loadCheatsheet();
        Qt.callLater(() => {
            keybindsContent.forceActiveFocus();
            keybindsContent.searchField.forceActiveFocus();
        });
    }

    onClosed: win.visible = false

    Column {
        anchors.fill: parent
        spacing: 0

        DWindowHeader {
            id: titleBar
            width: parent.width
            z: 10
            controls: windowControls
            title: KeybindsService.cheatsheet.title || I18n.tr("Keybinds")
            onCloseRequested: win.hide()

            DActionButton {
                iconName: "close_fullscreen"
                buttonSize: Theme.buttonHeightXXS
                iconSize: Theme.iconSizeSmall
                iconColor: Theme.surfaceText
                tooltipText: I18n.tr("Dock window")
                onClicked: win.floatingToggleRequested()
            }
        }

        KeybindsContent {
            id: keybindsContent
            width: parent.width
            height: parent.height - titleBar.height
            showFloatingToggle: false
            floating: true
            onCloseRequested: win.hide()
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: win
    }
}
