import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

test("shell staging and archives exclude tests and preserve runtime assets", t => {
    const root = fileURLToPath(new URL("../../", import.meta.url));
    const temporary = mkdtempSync(join(tmpdir(), "dms-shell-embed-"));
    t.after(() => rmSync(temporary, { recursive: true, force: true }));
    const source = join(temporary, "source");
    const dist = join(temporary, "dist");
    const common = join(temporary, "common");
    const excluded = ["tests/qml/layout.qml", "Common/tests/fixture.json", "Tests/test.qml", "testdata/settings.json",
        "Modules/__tests__/widget.qml", "harness/shell.qml", "harnesses/layout.qml", "Common/layout.test.mjs", "Common/layout.test.js",
        "Widgets/tst_button.qml", "Widgets/button_test.qml", "DCommon/tests/qml/slider.qml"];
    const included = ["shell.qml", "VERSION", "Common/LayoutResolver.js", "scripts/gtk.sh", "scripts/qt.sh",
        "scripts/bluez-card-profile.lua", "DCommon/Widgets/DIcon.qml", "Widgets/LatestUpdate.qml"];
    mkdirSync(source);
    mkdirSync(common);
    symlinkSync(common, join(source, "DCommon"));
    for (const path of [...included, ...excluded]) {
        const target = join(source, path);
        mkdirSync(dirname(target), { recursive: true });
        writeFileSync(target, path);
    }
    symlinkSync(join(temporary, "missing-vfs"), join(source, ".qmlls.ini"));
    execFileSync("make", ["-s", "-C", join(root, "core"), "sync-shell", "SHELL_SRC=" + source, "EMBED_DIR=" + dist]);
    for (const path of excluded)
        assert.equal(existsSync(join(dist, path)), false, path);
    for (const path of included)
        assert.equal(readFileSync(join(dist, path), "utf8"), path);
    assert.match(readFileSync(join(dist, ".dankrev"), "utf8"), /^[a-f0-9]{16}\n$/);

    const archive = join(temporary, "shell.tar");
    execFileSync("tar", ["-C", source, "--exclude=.qmlls.ini", "--exclude-from=" + join(root, "scripts/shell-test-excludes.txt"), "-chf", archive, "."]);
    const entries = execFileSync("tar", ["-tf", archive], { encoding: "utf8" }).split("\n");
    for (const path of excluded)
        assert.equal(entries.includes("./" + path), false, path);
    for (const path of included)
        assert.equal(entries.includes("./" + path), true, path);
});
