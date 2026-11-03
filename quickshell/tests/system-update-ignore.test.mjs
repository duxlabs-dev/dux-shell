import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../Services/SystemUpdateService.qml", import.meta.url), "utf8");
const extract = (name) => {
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in SystemUpdateService.qml`);
    return found[0];
};

const scope = vm.createContext({
    SettingsData: { updaterIgnoredPackages: [], updaterAllowAUR: true, updaterIncludeFlatpak: true },
    pkgManager: "portage",
    systemHoldsAllowed: true,
});
for (const fn of ["isValidIgnoredName", "_packageMatchesIgnore", "_isIgnored", "canIgnorePackage", "_filterUpdates"])
    vm.runInContext(extract(fn), scope);

test("portage atoms and other package names can be ignored", () => {
    for (const name of ["mail-client/thunderbird:0", "bash.x86_64", "gtk+"])
        assert.equal(scope.isValidIgnoredName(name), true, name);
});

test("names with spaces or shell punctuation are rejected", () => {
    for (const name of ["", "sys apps", "$(reboot)", "sys-apps/*"])
        assert.equal(scope.isValidIgnoredName(name), false, name);
});

test("ignores match on base name when the ignore carries no slot", () => {
    const cases = [
        ["gui-wm/gamescope", "gui-wm/gamescope", true],
        ["app-misc/fastfetch:0", "app-misc/fastfetch", true],
        ["gui-wm/gamescope", "gui-wm/sway", false],
    ];
    for (const [pkg, ignored, want] of cases)
        assert.equal(scope._packageMatchesIgnore(pkg, ignored), want, `${pkg} vs ${ignored}`);
});

test("a slot in the ignore only matches that slot, or slot 0 when the package has none", () => {
    const cases = [
        ["app-misc/fastfetch:2", "app-misc/fastfetch:2", true],
        ["app-misc/fastfetch:2", "app-misc/fastfetch:0", false],
        ["app-misc/fastfetch", "app-misc/fastfetch:0", true],
        ["app-misc/fastfetch", "app-misc/fastfetch:2", false],
    ];
    for (const [pkg, ignored, want] of cases)
        assert.equal(scope._packageMatchesIgnore(pkg, ignored), want, `${pkg} vs ${ignored}`);
});

test("portage ignores drop the update from the list", () => {
    scope.SettingsData.updaterIgnoredPackages = ["gui-wm/gamescope"];
    const pkgs = [
        { name: "gui-wm/gamescope", repo: "gentoo (ebuild)", backend: "portage" },
        { name: "mail-client/thunderbird", repo: "gentoo (ebuild)", backend: "portage" },
    ];
    const kept = scope._filterUpdates(pkgs);
    assert.deepEqual(kept.map(p => p.name), ["mail-client/thunderbird"]);
});

test("excluded flatpak updates are dropped from the list", () => {
    scope.SettingsData.updaterIgnoredPackages = [];
    const pkgs = [
        { name: "org.freedesktop.Platform", repo: "flatpak", backend: "flatpak" },
        { name: "mail-client/thunderbird", repo: "gentoo (ebuild)", backend: "portage" },
    ];
    for (const [include, want] of [[true, ["org.freedesktop.Platform", "mail-client/thunderbird"]], [false, ["mail-client/thunderbird"]]]) {
        scope.SettingsData.updaterIncludeFlatpak = include;
        assert.deepEqual(scope._filterUpdates(pkgs).map(p => p.name), want, `includeFlatpak=${include}`);
    }
    scope.SettingsData.updaterIncludeFlatpak = true;
});
