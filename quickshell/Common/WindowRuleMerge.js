.pragma library

// The Go providers round-trip more fields than the editor shows; a save starts
// from the stored object so those survive, and clears only the keys it owns.
function carry(stored, ownedKeys) {
    const out = Object.assign({}, stored || {});
    for (const key of ownedKeys)
        delete out[key];
    return out;
}
