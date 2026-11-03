import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const utils = loadScript(new URL("../Modals/DLauncherV2/ControllerUtils.js", import.meta.url));

test("app source follows the binary, not BAMF_DESKTOP_FILE_HINT", () => {
    const cases = [
        ["env BAMF_DESKTOP_FILE_HINT=/nix/store/abc-codex/share/applications/codex.desktop /nix/store/abc-codex/bin/codex %u", "nix"],
        ["env BAMF_DESKTOP_FILE_HINT=/usr/share/applications/foo.desktop /usr/bin/foo", "system"],
        ["env BAMF_DESKTOP_FILE_HINT=/var/lib/snapd/desktop/applications/firefox_firefox.desktop /snap/bin/firefox %u", "snap"],
        ["snap run spotify", "snap"]
    ];
    for (const [exec, source] of cases)
        assert.equal(utils.classifyAppSource({ id: "app", execString: exec }), source, exec);
});
