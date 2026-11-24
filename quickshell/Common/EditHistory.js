.pragma library

// A state is one JSON string of the edited keys, so Discard and undo compare and restore it whole.

const limit = 50;

function snapshot(settings, keys) {
    const state = {};
    for (const key of keys)
        state[key] = settings[key];
    return JSON.stringify(state);
}

// Writes only the keys that differ, so a restore never re-saves an untouched setting.
function restore(settings, state, keys) {
    if (!state)
        return;
    const wanted = JSON.parse(state);
    for (const key of keys) {
        if (JSON.stringify(settings[key]) !== JSON.stringify(wanted[key]))
            settings.set(key, wanted[key]);
    }
}

function push(stack, state) {
    return stack.concat([state]).slice(-limit);
}
