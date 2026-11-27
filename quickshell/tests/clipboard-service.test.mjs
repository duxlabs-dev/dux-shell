import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../Services/ClipboardService.qml", import.meta.url), "utf8");

function createClipboardService({ clipboardShowPinned = false, pinnedCount = 0, pinnedEntries = [], unpinnedEntries = [] } = {}) {
    const settingsCalls = [];
    const context = vm.createContext({
        SettingsData: {
            clipboardShowPinned,
            set(key, value) {
                settingsCalls.push([key, value]);
                this[key] = value;
            }
        },
        pinnedCount,
        pinnedEntries,
        unpinnedEntries,
        selectedIndex: 0,
        keyboardNavigationActive: false,
        get showPinned() {
            return this.SettingsData.clipboardShowPinned && this.pinnedCount > 0;
        },
        get displayedEntries() {
            return this.showPinned && this.pinnedEntries.length > 0 ? this.pinnedEntries.concat(this.unpinnedEntries) : this.unpinnedEntries;
        }
    });

    for (const name of ["setShowPinned", "toggleShowPinned", "applyEntries", "clampSelection"]) {
        const match = source.match(new RegExp(`^    function ${name}\\([^\\n]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
        assert.ok(match, `Missing ${name} in ClipboardService.qml`);
        vm.runInContext(match[0], context);
    }

    return { context, settingsCalls };
}

test("toggleShowPinned persists the setting and resets selection when pins exist", () => {
    const { context, settingsCalls } = createClipboardService({
        clipboardShowPinned: false,
        pinnedCount: 2,
        pinnedEntries: [{ id: 1 }, { id: 2 }],
        unpinnedEntries: [{ id: 10 }, { id: 11 }]
    });
    context.selectedIndex = 1;
    context.keyboardNavigationActive = true;

    context.toggleShowPinned();
    assert.equal(context.SettingsData.clipboardShowPinned, true);
    assert.equal(context.selectedIndex, 0);
    assert.equal(context.keyboardNavigationActive, false);
    assert.deepEqual(settingsCalls, [["clipboardShowPinned", true]]);

    context.selectedIndex = 3;
    context.toggleShowPinned();
    assert.equal(context.SettingsData.clipboardShowPinned, false);
    assert.equal(context.selectedIndex, 0);
    assert.deepEqual(settingsCalls, [["clipboardShowPinned", true], ["clipboardShowPinned", false]]);
});

test("toggleShowPinned does nothing when there are no pinned entries and setting is off", () => {
    const { context, settingsCalls } = createClipboardService({
        clipboardShowPinned: false,
        pinnedCount: 0
    });

    context.toggleShowPinned();
    assert.equal(context.SettingsData.clipboardShowPinned, false);
    assert.deepEqual(settingsCalls, []);
});

test("applyEntries keeps selection on an unpinned entry when pinned entries shift above it", () => {
    const { context } = createClipboardService({
        clipboardShowPinned: true,
        pinnedCount: 1,
        pinnedEntries: [{ id: 1 }],
        unpinnedEntries: [{ id: 10 }, { id: 11 }]
    });
    context.selectedIndex = 2; // unpinned entry id 11

    context.pinnedCount = 2;
    context.applyEntries(true, [{ id: 2 }, { id: 1 }], true);
    assert.equal(context.displayedEntries[context.selectedIndex].id, 11);
    assert.equal(context.selectedIndex, 3);
});

test("clampSelection uses the combined displayedEntries length when pins are shown", () => {
    const { context } = createClipboardService({
        clipboardShowPinned: true,
        pinnedCount: 2,
        pinnedEntries: [{ id: 1 }, { id: 2 }],
        unpinnedEntries: [{ id: 10 }]
    });
    context.selectedIndex = 5;
    context.keyboardNavigationActive = true;

    context.clampSelection();
    assert.equal(context.selectedIndex, 2);

    context.applyEntries(true, [], false);
    context.pinnedCount = 0;
    context.applyEntries(false, [], false);
    assert.equal(context.selectedIndex, 0);
    assert.equal(context.keyboardNavigationActive, false);
});
