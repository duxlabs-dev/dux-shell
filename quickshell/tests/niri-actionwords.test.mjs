import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const words = loadScript(new URL("../Common/niri/actionwords.js", import.meta.url));

test("actionSearchWords gives the delete words for the workspace close action", () => {
    const found = words.actionSearchWords("spawn dms ipc call workspace closeAll");
    for (const word of ["delete", "remove", "close", "workspace"])
        assert.ok(found.includes(word), word);
    for (const word of ["supprimer", "suppr", "fermer", "espace"])
        assert.ok(!found.includes(word), word);
});

test("actionSearchWords stays empty for unknown actions", () => {
    // The script runs in its own realm: compare lengths, not array identities.
    assert.equal(words.actionSearchWords("close-window").length, 0);
    assert.equal(words.actionSearchWords("").length, 0);
    assert.equal(words.actionSearchWords(null).length, 0);
});
