import QtQuick
import qs.Modules.Settings.Widgets

// choices: [{value, label}]. A stored value it can't name shows as an extra literal option; picking it again writes nothing.
SettingsDropdownRow {
    id: root

    property var choices: []
    property var stored
    property var labelFor: v => String(v)
    readonly property bool storedKnown: choices.some(c => c.value === stored)
    readonly property var allChoices: storedKnown || stored === undefined || stored === null || stored === "" ? choices : choices.concat([
            {
                "value": stored,
                "label": labelFor(stored)
            }
        ])

    signal picked(var value)

    // Index keys: DDropdown shows an empty key as unset, and values can be numbers or booleans.
    options: allChoices.map(c => c.label)
    optionValues: allChoices.map((c, i) => String(i))
    currentValue: {
        const i = allChoices.findIndex(c => c.value === stored);
        return i < 0 ? "" : String(i);
    }
    onValueChanged: key => {
        const hit = root.allChoices[Number(key)];
        if (hit && hit.value !== root.stored)
            root.picked(hit.value);
        root.resync();
    }
}
