.pragma library

// « Keep this change? » for settings that can cut the keyboard or the screen.
// Only the section's own edits go through edit(): a style, the KDL drawer or undo never start the countdown.

var seconds = 15;

function _same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
}

// pending: {key: value before the first unkept change}; left: seconds before revert, 0 when idle.
function idle() {
    return { "pending": {}, "left": 0 };
}

function edit(state, risky, key, before, after) {
    if (risky.indexOf(key) < 0 || _same(before, after))
        return state;
    const pending = Object.assign({}, state.pending);
    if (!(key in pending))
        pending[key] = before;
    else if (_same(pending[key], after))
        delete pending[key];
    return { "pending": pending, "left": Object.keys(pending).length ? seconds : 0 };
}

// What revert writes: only keys that still differ; a default value goes back as a reset.
function restores(pending, current, defaultOf) {
    return Object.keys(pending).filter(key => !_same(current(key), pending[key])).map(key => ({
        "key": key,
        "value": pending[key],
        "reset": _same(pending[key], defaultOf(key))
    }));
}
