import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    property string selectedPopout: pluginData.selectedPopout || "controlCenter"

    property var popoutActions: ({
            "controlCenter": (x, y, w, s, scr) => popoutService?.toggleControlCenter(x, y, w, s, scr),
            "notificationCenter": (x, y, w, s, scr) => popoutService?.toggleNotificationCenter(x, y, w, s, scr),
            "appDrawer": (x, y, w, s, scr) => popoutService?.toggleAppDrawer(x, y, w, s, scr),
            "processList": (x, y, w, s, scr) => popoutService?.toggleProcessList(x, y, w, s, scr),
            "dankDash": (x, y, w, s, scr) => popoutService?.toggleDankDash(0, x, y, w, s, scr),
            "battery": (x, y, w, s, scr) => popoutService?.toggleBattery(x, y, w, s, scr),
            "vpn": (x, y, w, s, scr) => popoutService?.toggleVpn(x, y, w, s, scr),
            "systemUpdate": (x, y, w, s, scr) => popoutService?.toggleSystemUpdate(x, y, w, s, scr),
            "settings": () => popoutService?.openSettings(),
            "clipboardHistory": () => popoutService?.openClipboardHistory(),
            "spotlight": () => popoutService?.toggleDankLauncherV2(),
            "powerMenu": () => popoutService?.togglePowerMenu(),
            "colorPicker": () => popoutService?.showColorPicker(),
            "notepad": () => popoutService?.toggleNotepad()
        })

    property var popoutNames: ({
            "controlCenter": "Control Center",
            "notificationCenter": "Notification Center",
            "appDrawer": "App Drawer",
            "processList": "Process List",
            "dankDash": "DankDash",
            "battery": "Battery Info",
            "vpn": "VPN",
            "systemUpdate": "System Update",
            "settings": "Settings",
            "clipboardHistory": "Clipboard",
            "spotlight": "Spotlight",
            "powerMenu": "Power Menu",
            "colorPicker": "Color Picker",
            "notepad": "Notepad"
        })

    pillClickAction: (x, y, width, section, screen) => {
        if (popoutActions[selectedPopout]) {
            popoutActions[selectedPopout](x, y, width, section, screen);
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                name: "widgets"
                color: Theme.primary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: popoutNames[selectedPopout] || "Popouts"
                color: Theme.primary
                font.pixelSize: root.textSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DIcon {
                name: "widgets"
                color: Theme.primary
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: popoutNames[selectedPopout] || "Popouts"
                color: Theme.primary
                font.pixelSize: root.textSize
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
