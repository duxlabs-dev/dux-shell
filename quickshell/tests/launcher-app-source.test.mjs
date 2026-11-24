import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const utils = loadScript(new URL("../Modals/DLauncherV2/ControllerUtils.js", import.meta.url));

test("steam and waydroid entries win over their wrapper's source", () => {
    const cases = [
        ["steam steam://rungameid/220", "steam"],
        ["/nix/store/abc-steam/bin/steam steam://rungameid/220", "steam"],
        ["flatpak run com.valvesoftware.Steam steam://rungameid/220", "steam"],
        ["waydroid app launch com.android.settings", "waydroid"],
        ["/nix/store/abc-waydroid/bin/waydroid app launch com.android.settings", "waydroid"],
        ["steam %U", "system"]
    ];
    for (const [exec, source] of cases)
        assert.equal(utils.classifyAppSource({ id: "app", execString: exec }), source, exec);
});

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
