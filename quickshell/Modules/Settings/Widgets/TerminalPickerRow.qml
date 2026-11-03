import QtQuick
import qs.Common

SettingsDropdownRow {
    id: root

    readonly property string autoLabel: I18n.tr("Auto")

    text: I18n.tr("Terminal")
    settingKey: "terminalOverride"
    resetStore: SessionData
    resetKeys: ["terminalOverride"]

    options: {
        const opts = [autoLabel];
        const installed = SessionData.installedTerminals || [];
        const list = installed.length > 0 ? installed : SessionData.terminalOptions;
        for (const t of list) {
            opts.push(t);
        }
        if (SessionData.terminalOverride && !opts.includes(SessionData.terminalOverride)) {
            opts.push(SessionData.terminalOverride);
        }
        return opts;
    }

    currentValue: SessionData.terminalOverride.length > 0 ? SessionData.terminalOverride : autoLabel

    Component.onCompleted: SessionData.probeTerminals()

    onValueChanged: label => {
        const next = label === autoLabel ? "" : label;
        SessionData.set("terminalOverride", next);
    }
}
