pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

SettingsCard {
    id: root
    property bool cursor: false
    property var snapshot: null
    property var changes: ({})
    property bool busy: false
    property string error: ""
    readonly property var report: cursor ? snapshot?.desktop_cursor : snapshot?.desktop_typography
    readonly property bool partial: (report?.failed_count || 0) > 0
    readonly property bool supported: snapshot?.capabilities?.includes(cursor ? "cursor_sync" : "typography_sync") || false
    readonly property bool working: busy || AqueousConfigService.busy
    readonly property bool hasChanges: Object.keys(changes).length > 0
    title: cursor ? I18n.tr("Aqueous cursor", "Aqueous compositor cursor synchronization settings") : I18n.tr("Aqueous typography", "Aqueous compositor font synchronization settings")
    iconName: cursor ? "mouse" : "text_fields"
    tab: cursor ? "theme" : "typography"
    tags: ["aqueous", "appearance"]

    function reload() {
        if (working)
            return;
        busy = true;
        AqueousConfigService.load((data, message) => {
            busy = false;
            error = message ? AqueousService.errorMessage(message) : "";
            if (!data)
                return;
            snapshot = data;
            changes = ({});
            if (!supported)
                error = I18n.tr("Unavailable");
        });
    }

    function targetStatus(target) {
        switch (target.state) {
        case "synced":
            return I18n.tr("Synchronized", "Aqueous appearance settings match this application or toolkit");
        case "drifted":
            return I18n.tr("Not synchronized", "Aqueous appearance settings differ from this application or toolkit");
        case "partial":
            return I18n.tr("Partially synchronized", "The application or toolkit cannot represent every Aqueous font setting");
        case "failed":
            return I18n.tr("Sync failed", "Applying Aqueous appearance settings to this application or toolkit failed");
        case "unavailable":
            return I18n.tr("Unavailable");
        case "unmanaged":
            return I18n.tr("Disabled");
        default:
            return I18n.tr("Unknown");
        }
    }

    function targetColor(target) {
        switch (target.state) {
        case "synced":
            return Theme.success;
        case "drifted":
        case "partial":
            return Theme.warning;
        case "failed":
            return Theme.error;
        default:
            return Theme.surfaceVariantText;
        }
    }

    function value(id) {
        if (Object.prototype.hasOwnProperty.call(changes, id))
            return changes[id];
        return snapshot?.fields?.find(f => f.id === id)?.value;
    }

    function stage(id, value) {
        const updated = Object.assign({}, changes);
        updated[id] = value;
        changes = updated;
    }

    function apply(retry) {
        if (working || !supported)
            return;
        const draft = {
            expected_generation: snapshot.generation,
            create_user_override: true,
            changes: retry ? [] : Object.keys(changes).map(id => ({
                        id: id,
                        value: changes[id]
                    }))
        };
        draft[cursor ? "sync_cursor" : "sync_typography"] = true;
        busy = true;
        AqueousConfigService.apply(draft, (data, message) => {
            busy = false;
            error = message ? AqueousService.errorMessage(message) : "";
            if (!data)
                return;
            snapshot = data;
            if (!retry)
                changes = ({});
            if (cursor)
                return;
            const typography = data.desktop_typography;
            if (!typography || typeof typography.family !== "string" || !Number.isFinite(typography.weight) || !Number.isFinite(typography.size_pt) || typography.size_pt <= 0)
                return;
            SettingsData.set("fontFamily", typography.family);
            SettingsData.set("fontWeight", typography.weight);
            SettingsData.set("fontScale", typography.size_pt * 96 / 72 / 14);
        });
    }

    Component.onCompleted: reload()

    headerActions: DActionButton {
        iconName: "refresh"
        iconColor: Theme.surfaceVariantText
        Accessible.name: I18n.tr("Refresh")
        enabled: !root.working
        onClicked: root.reload()
    }

    SettingsDropdownRow {
        visible: root.cursor
        enabled: root.supported && !root.working
        text: I18n.tr("Cursor Theme")
        options: root.snapshot?.desktop_cursor?.themes || []
        currentValue: root.value("desktop.cursor.theme") || "default"
        onValueChanged: value => {
            root.stage("desktop.cursor.theme", value);
            root.stage("desktop.cursor.managed", true);
        }
    }

    SettingsDropdownRow {
        visible: !root.cursor
        enabled: root.supported && !root.working
        text: I18n.tr("Normal Font")
        options: root.snapshot?.desktop_typography?.families || []
        currentValue: root.value("desktop.font.family") || "sans-serif"
        onValueChanged: value => {
            root.stage("desktop.font.family", value);
            root.stage("desktop.font.style", "");
        }
    }

    SettingsSliderRow {
        enabled: root.supported && !root.working
        text: root.cursor ? I18n.tr("Cursor Size") : I18n.tr("Font Size")
        minimum: root.cursor ? 12 : 6
        maximum: root.cursor ? 128 : 30
        value: root.value(root.cursor ? "desktop.cursor.size" : "desktop.font.size_pt") || (root.cursor ? 24 : 12)
        unit: root.cursor ? I18n.tr("px", "Cursor size unit, pixels") : I18n.tr("pt", "Font size unit, points")
        onSliderValueChanged: value => {
            root.stage(root.cursor ? "desktop.cursor.size" : "desktop.font.size_pt", value);
            if (root.cursor)
                root.stage("desktop.cursor.managed", true);
        }
    }

    SettingsRow {
        visible: !root.cursor
        subtitle: I18n.tr("DMS uses the font family, weight and scale. Exact face, slant, width and separately scaled bars may differ.", "Aqueous font synchronization, describing which font settings DMS can represent")
    }

    SettingsRow {
        visible: root.error !== "" || root.partial
        iconName: "error"
        iconColor: Theme.error
        subtitle: root.error || I18n.tr("Error")
        subtitleColor: Theme.error

        DButton {
            visible: root.partial
            text: I18n.tr("Retry")
            enabled: root.supported && !root.working
            onClicked: root.apply(true)
        }
    }

    Repeater {
        model: root.report?.targets || []

        SettingsRow {
            required property var modelData
            title: modelData.id
            trailingBadge: root.targetStatus(modelData)

            DBadge {
                color: root.targetColor(modelData)
            }
        }
    }

    SettingsFabBar {
        shown: root.hasChanges

        DFab {
            text: I18n.tr("Discard")
            iconName: "undo"
            colorRole: "secondaryContainer"
            enabled: !root.working
            onClicked: root.changes = ({})
        }

        DFab {
            text: I18n.tr("Apply changes")
            iconName: "check"
            colorRole: "primary"
            busy: root.working
            enabled: root.supported && !root.working
            onClicked: root.apply(false)
        }
    }
}
