pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null
    property bool pageActive: true

    readonly property string profileId: SettingsUiState.selectedConfigProfileId
    readonly property var profile: ConfigProfileService.find(profileId)
    property var diff: []
    property var selected: []
    readonly property int valueMaxLength: 60
    readonly property var settingLabels: {
        const labels = {};
        for (const e of SettingsSearchService.settingsIndex)
            labels[e.section] = e.label;
        return labels;
    }

    function _refresh() {
        if (!pageActive)
            return;
        const d = ConfigProfileService.compare(profileId);
        if (d === null) {
            parentModal?.goBack();
            return;
        }
        // Keep the user's picks across live refreshes; groups that newly differ start ticked.
        const shown = diff.map(e => e.group);
        selected = d.map(e => e.group).filter(g => !shown.includes(g) || selected.includes(g));
        diff = d;
    }

    function _reset() {
        diff = [];
        _refresh();
    }

    function _show(v) {
        if (v === undefined)
            return I18n.tr("Default");
        if (typeof v === "boolean")
            return v ? I18n.tr("On") : I18n.tr("Off");
        const s = typeof v === "string" && v !== "" ? v : JSON.stringify(v) ?? "";
        return s.length > valueMaxLength ? s.slice(0, valueMaxLength - 1) + "…" : s;
    }

    function _toggle(group, on) {
        selected = on ? selected.concat(group) : selected.filter(g => g !== group);
    }

    function _apply() {
        if (ConfigProfileService.applyGroups(profileId, selected))
            _refresh();
    }

    onProfileChanged: _refresh()
    onProfileIdChanged: _reset()
    onPageActiveChanged: _reset()
    Component.onCompleted: _reset()

    Connections {
        target: ConfigProfileService
        function onLiveChanged() {
            root._refresh();
        }
    }

    SettingsPage {
        SettingsCard {
            width: parent.width
            visible: root.profile !== null && root.diff.length === 0

            SettingsRow {
                title: I18n.tr("Matches the current settings", "config profile compare page: applying would change nothing")
            }
        }

        Repeater {
            model: root.diff

            SettingsCard {
                id: groupCard

                required property var modelData

                width: parent?.width ?? 0

                SettingsToggleRow {
                    text: ConfigProfileService.groupLabel(groupCard.modelData.group)
                    checked: root.selected.includes(groupCard.modelData.group)
                    onToggled: on => root._toggle(groupCard.modelData.group, on)
                }

                Repeater {
                    model: groupCard.modelData.changes

                    SettingsRow {
                        required property var modelData

                        title: modelData.source !== "plugins" && root.settingLabels[modelData.key] ? I18n.tr(root.settingLabels[modelData.key]) : modelData.key
                        subtitle: root._show(modelData.current) + (I18n.isRtl ? " ← " : " → ") + root._show(modelData.stored)
                    }
                }
            }
        }

        SettingsFabBar {
            shown: root.selected.length > 0

            DFab {
                text: I18n.tr("Apply")
                iconName: "check"
                onClicked: root._apply()
            }
        }
    }
}
