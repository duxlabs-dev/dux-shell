import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../DMSShellIPC.qml", import.meta.url), "utf8");
const body = source.match(/^ {8}function openNiri\(section: string\): string \{\n[\s\S]*?^ {8}\}$/m)[0].replace("(section: string): string", "(section)");

function shell(isNiri, expert = false) {
    const opened = [];
    const writes = [];
    const context = vm.createContext({
        CompositorService: { isNiri },
        SettingsData: { niriPageExpert: expert, set: (key, value) => writes.push([key, value]) },
        SettingsUiState: { niriSection: "windows" },
        PopoutService: { openSettingsWithTab: tab => opened.push(tab) },
        niriSections: { all: [{ id: "windows" }, { id: "animations" }, { id: "advanced", expertOnly: true }] }
    });
    vm.runInContext(body, context);
    return { context, opened, writes };
}

test("openNiri never switches Expert on: an Expert section is refused in Simple mode", () => {
    const simple = shell(true);
    assert.equal(simple.context.openNiri("advanced"), "SETTINGS_OPEN_FAILED: advanced is an Expert section, switch the niri page to Expert first");
    assert.equal(simple.context.SettingsUiState.niriSection, "windows");
    assert.deepEqual(simple.opened, []);
    const expert = shell(true, true);
    assert.equal(expert.context.openNiri("advanced"), "SETTINGS_OPEN_SUCCESS: niri advanced");
    assert.deepEqual(expert.opened, ["niri"]);
    assert.deepEqual([...simple.writes, ...expert.writes], []);
});

test("openNiri lands on the asked section", () => {
    const { context, opened } = shell(true);
    assert.equal(context.openNiri("animations"), "SETTINGS_OPEN_SUCCESS: niri animations");
    assert.equal(context.SettingsUiState.niriSection, "animations");
    assert.deepEqual(opened, ["niri"]);
});

test("openNiri without a section keeps the last one", () => {
    const { context, opened } = shell(true);
    assert.equal(context.openNiri(""), "SETTINGS_OPEN_SUCCESS: niri windows");
    assert.deepEqual(opened, ["niri"]);
});

test("openNiri refuses an unknown section and other compositors", () => {
    const niri = shell(true);
    assert.equal(niri.context.openNiri("bogus"), "SETTINGS_OPEN_FAILED: Unknown niri section bogus");
    assert.equal(niri.context.SettingsUiState.niriSection, "windows");
    const hypr = shell(false);
    assert.equal(hypr.context.openNiri("animations"), "SETTINGS_OPEN_FAILED: The niri page needs niri");
    assert.deepEqual([...niri.opened, ...hypr.opened], []);
});
