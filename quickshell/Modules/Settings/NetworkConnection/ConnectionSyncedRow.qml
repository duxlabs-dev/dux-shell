import QtQuick
import qs.Modules.Settings.Widgets

// Refills only when the stored value changed and differs from the typed text, so half-typed text survives other edits.
SettingsTextFieldRow {
    id: root

    property string stored: ""
    property string lastStored: ""
    // Password field: the text is kept as typed instead of trimmed.
    property bool secret: false
    property var check: t => true
    property var commit: null
    // Digits match their normalized number ("050" is "50", "0" is unset), so a refill can't move the cursor.
    property var same: (typed, stored) => typed === stored || (!secret && /^\d+$/.test(typed) && (String(Number(typed)) === stored || (Number(typed) === 0 && stored === "")))
    // Object with a reset() signal; on reset the row refills unconditionally.
    property var resetOn: null
    readonly property bool ok: check(clean(value))
    // The field reports programmatic text changes as edits too; refills must not commit.
    property bool syncing: false

    function clean(text) {
        return secret ? text : text.trim();
    }

    function fill(text) {
        syncing = true;
        value = text;
        syncing = false;
    }

    isError: !ok
    echoMode: secret ? TextInput.Password : TextInput.Normal
    showPasswordToggle: secret
    leftIconName: secret ? "lock" : ""
    onStoredChanged: {
        if (stored === lastStored)
            return;
        lastStored = stored;
        if (!same(clean(value), stored))
            fill(stored);
    }
    Component.onCompleted: fill(lastStored = stored)
    onValueEdited: text => {
        if (!root.syncing && root.commit && root.check(root.clean(text)))
            root.commit(root.clean(text));
    }

    Connections {
        target: root.resetOn
        ignoreUnknownSignals: true

        function onReset() {
            root.fill(root.lastStored = root.stored);
        }
    }
}
