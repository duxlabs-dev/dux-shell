pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    readonly property var groups: [
        {
            "id": "network",
            "label": I18n.tr("Network"),
            "icon": "lan",
            "setting": "showNetworkIcon"
        },
        {
            "id": "vpn",
            "label": I18n.tr("VPN", "virtual private network, widget and page title"),
            "icon": "vpn_lock",
            "setting": "showVpnIcon"
        },
        {
            "id": "bluetooth",
            "label": I18n.tr("Bluetooth"),
            "icon": "bluetooth",
            "setting": "showBluetoothIcon"
        },
        {
            "id": "audio",
            "label": I18n.tr("Audio"),
            "icon": "volume_up",
            "setting": "showAudioIcon",
            "subLabel": I18n.tr("Volume"),
            "subSetting": "showAudioPercent"
        },
        {
            "id": "microphone",
            "label": I18n.tr("Microphone"),
            "icon": "mic",
            "setting": "showMicIcon",
            "subLabel": I18n.tr("Microphone volume"),
            "subSetting": "showMicPercent"
        },
        {
            "id": "brightness",
            "label": I18n.tr("Brightness"),
            "icon": "brightness_high",
            "setting": "showBrightnessIcon",
            "subLabel": I18n.tr("Brightness value"),
            "subSetting": "showBrightnessPercent"
        },
        {
            "id": "battery",
            "label": I18n.tr("Battery"),
            "icon": "battery_full",
            "setting": "showBatteryIcon"
        },
        {
            "id": "printer",
            "label": I18n.tr("Printer", "toggle for the printer indicator icon"),
            "icon": "print",
            "setting": "showPrinterIcon"
        },
        {
            "id": "screenSharing",
            "label": I18n.tr("Screen sharing"),
            "icon": "screen_record",
            "setting": "showScreenSharingIcon"
        },
        {
            "id": "idleInhibitor",
            "label": I18n.tr("Idle inhibitor", "feature that keeps the session from going idle"),
            "icon": "local_cafe",
            "setting": "showIdleInhibitorIcon"
        },
        {
            "id": "doNotDisturb",
            "label": I18n.tr("Do not disturb"),
            "icon": "do_not_disturb_on",
            "setting": "showDoNotDisturbIcon"
        }
    ]

    readonly property var orderedGroups: {
        const saved = page.value("controlCenterGroupOrder") ?? [];
        const byId = {};
        for (const group of groups)
            byId[group.id] = group;
        const ordered = [];
        for (const id of saved) {
            if (byId[id])
                ordered.push(byId[id]);
        }
        for (const group of groups) {
            if (!ordered.includes(group))
                ordered.push(group);
        }
        return ordered;
    }

    function setSetting(key, value) {
        const updates = {};
        updates[key] = value;
        if (!value) {
            switch (key) {
            case "showAudioIcon":
                updates.showAudioPercent = false;
                break;
            case "showMicIcon":
                updates.showMicPercent = false;
                break;
            case "showBrightnessIcon":
                updates.showBrightnessPercent = false;
                break;
            }
        }
        for (const updateKey in updates)
            page.set(updateKey, updates[updateKey]);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        title: I18n.tr("Indicators", "noun, settings label for status indicator icons")
        settingKey: "barWidgetControlCenter"

        SettingsReorderList {
            id: indicatorList

            model: root.orderedGroups
            onReordered: indices => root.page.set("controlCenterGroupOrder", indices.map(i => root.orderedGroups[i].id))

            delegate: SettingsReorderRow {
                id: indicatorRow

                required property var modelData

                reorderList: indicatorList
                iconName: modelData.icon
                title: modelData.label
                clickable: true
                onClicked: root.setSetting(modelData.setting, !root.page.value(modelData.setting))

                DToggle {
                    hideText: true
                    checked: root.page.value(indicatorRow.modelData.setting)
                    onToggled: value => root.setSetting(indicatorRow.modelData.setting, value)
                }

                body: SettingsToggleRow {
                    width: parent.width
                    visible: !!indicatorRow.modelData.subSetting
                    height: visible ? implicitHeight : 0
                    paintBackground: false
                    text: indicatorRow.modelData.subLabel ?? ""
                    enabled: root.page.value(indicatorRow.modelData.setting)
                    checked: !!root.page.value(indicatorRow.modelData.subSetting ?? "")
                    onToggled: value => root.setSetting(indicatorRow.modelData.subSetting, value)
                }
            }
        }
    }
}
