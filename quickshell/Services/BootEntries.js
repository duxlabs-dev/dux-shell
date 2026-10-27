.pragma library

// Reads efibootmgr output into the current boot id and the entries as [{id, label}],
// where id is the upper-case hex Boot#### number.
// Inactive entries stay: dual-booters often deactivate Windows so it stops rewriting
// BootOrder, and BootNext still boots them.
function parseEntries(text) {
    const result = {
        currentId: "",
        entries: []
    };
    for (const line of text.split("\n")) {
        const current = line.match(/^BootCurrent:\s*([0-9A-Fa-f]{4})/);
        if (current) {
            result.currentId = current[1].toUpperCase();
            continue;
        }
        // efibootmgr 18+ appends a tab and the device path after the label
        const entry = line.match(/^Boot([0-9A-Fa-f]{4})\*?\s+([^\t]+)/);
        if (!entry)
            continue;
        result.entries.push({
            id: entry[1].toUpperCase(),
            label: entry[2].trim()
        });
    }
    return result;
}

// Entries that can still be added to the power menu, skipping the running OS and saved ones.
// name is the text shown in the picker. Firmware can hold several entries with the same label,
// one per disk or install, so those get their id appended.
function pickerOptions(entries, currentId, saved) {
    const addable = entries.filter(entry => entry.id !== currentId && !saved.some(item => item.id === entry.id));
    return addable.map(entry => ({
        id: entry.id,
        label: entry.label,
        name: addable.some(other => other !== entry && other.label === entry.label) ? entry.label + " (" + entry.id + ")" : entry.label
    }));
}
