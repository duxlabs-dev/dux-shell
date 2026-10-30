import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const collections = loadScript(new URL("../Services/DSearchCollections.js", import.meta.url));
const index = JSON.parse(readFileSync(new URL("../translations/settings_search_index.json", import.meta.url), "utf8")).filter(entry => entry.runtimeType !== "barWidgetOption");

test("every real settings entry gets its own id, and the id opens the setting the way the launcher does", () => {
    const items = collections.settingsItems(index);
    const staticEntries = index.filter(entry => !entry.runtimeType);
    assert.equal(items.length, staticEntries.length);
    assert.equal(new Set(Array.from(items, item => item.id)).size, items.length);
    // AppSearchService turns an entry into settings_page:<page> or settings_nav:<tab>:<section>.
    const page = index.find(entry => entry.page === "personalization" && entry.section === "wallpaperAdvanced");
    const nav = index.find(entry => !entry.page && entry.tabIndex >= 0);
    const pageId = collections.settingId(page);
    assert.equal(collections.settingAction(pageId), "settings_page:personalization");
    assert.equal(collections.settingSection(pageId), "wallpaperAdvanced");
    const navId = collections.settingId(nav);
    assert.equal(collections.settingAction(navId), `settings_nav:${nav.tabIndex}:${nav.section}`);
    assert.equal(collections.settingSection(navId), nav.section);
});

test("settings text is the English source, not a translation, and carries the page it lives on", () => {
    const entry = { section: "notificationTimeoutLow", label: "Low", tabIndex: -1, page: "notifications", category: "Timeouts", parentLabel: "Notifications", description: "How long low priority popups stay", keywords: ["timeout"] };
    const [item] = collections.settingsItems([entry]);
    assert.equal(item.title, "Low");
    assert.equal(item.text, "How long low priority popups stay. Setting in Notifications > Timeouts");
    assert.deepEqual(Array.from(item.keywords), ["timeout"]);
    assert.deepEqual(Array.from(collections.settingsItems([{ section: "x", label: "Runtime", runtimeType: "plugin", tabIndex: 12 }, { label: "No section", tabIndex: 1 }])), []);
});

test("an application becomes name, generic name, comment and readable categories", () => {
    const items = collections.appItems([
        { id: "firefox.desktop", name: "Firefox", genericName: "Web Browser", comment: "Browse the World Wide Web", keywords: ["internet"], categories: ["Network", "WebBrowser", "X-Foo"] },
        { id: "firefox.desktop", name: "Duplicate" },
        { id: "", name: "No id" },
        { id: "bare.desktop", name: "Bare" }
    ]);
    assert.equal(items.length, 2);
    assert.deepEqual(JSON.parse(JSON.stringify(items[0])), { id: "firefox.desktop", title: "Firefox", text: "Web Browser. Browse the World Wide Web. Network, Web Browser", keywords: ["internet"] });
    assert.equal(items[1].text, "");
});

test("the signature changes with any item and with nothing else", () => {
    const a = [{ id: "a", title: "A", text: "t", keywords: [] }];
    assert.equal(collections.signature(a), collections.signature(JSON.parse(JSON.stringify(a))));
    assert.notEqual(collections.signature(a), collections.signature([{ id: "a", title: "A", text: "u", keywords: [] }]));
    assert.notEqual(collections.signature(a), collections.signature([]));
});
