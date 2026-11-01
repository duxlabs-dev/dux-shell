# Niri page sections

One `.pragma library` file per section, `<id>.js`, tested with `node --test` (load it with `tests/qml-script.mjs`).

- `defaults`: `{key: value}` for the keys stored in `SettingsData.niriPage`. Keys are `"<id>.<name>"`.
- `limits` (optional): `{key: {min?, from, to} | [choices]}`. Sliders and the style import read them; `min` admits DMS sentinels (-1, -2) below `from`.
- `stored`: `{key: "SettingsData:<prop>" | "NiriService:<prop>:<setter>" | "page"}`. A key DMS already writes binds to that property, never written twice; a `NiriService` key reads `<prop>` and writes through `NiriService.<setter>(value)`.
- `toKdl(state)`: `[{block, lines}]`. `block` is a dotted path (`"layout.focus-ring"`) or `null` for top-level lines (`window-rule {…}`, `workspace "x"`). Leave out every default value: niri replaces some blocks whole (animations, input devices, struts), so emit only what the user changed. Empty blocks are dropped. To turn a block on, write its `on` line (`border { on }`): niri ignores an empty `border {}`. Quote strings with `kdlString` from `../../niriKdl.js`.
- `search`: `[{key, title, words}]`, words in English; the title is matched translated too.

`../assemble.js` merges all sections into one KDL text: blocks of the same path from several sections become one block, in section order then first appearance. Each section's custom KDL from the drawer goes to `dms/niri-custom.kdl`, which `dms/niri.kdl` includes last: niri refuses a block repeated in one file but merges it across included files.

Register the module in `../registry.js` with one `.import` line and one entry. `id` is the menu section the module belongs to (`windows`, `animations`, `workspaces`, `keybinds`, `gestures`, `input`, `startup`, `advanced`): several modules may share one id (`look.js`, `columns.js` and `rules.js` all register `windows`), the KDL drawer shows them together and the section's custom text is written once.

```js
.pragma library
.import "../../niriKdl.js" as Kdl

var defaults = { "look.ringWidth": 4, "look.ringColor": "" };
var stored = { "look.ringWidth": "page", "look.ringColor": "page", "look.gaps": "SettingsData:niriLayoutGapsOverride" };
var search = [{ key: "look.ringWidth", title: "Focus ring width", words: ["ring", "focus"] }];

function toKdl(state) {
    const ring = [];
    if (state["look.ringWidth"] !== defaults["look.ringWidth"])
        ring.push("width " + state["look.ringWidth"]);
    if (state["look.ringColor"])
        ring.push("active-color " + Kdl.kdlString(state["look.ringColor"]));
    return [{ block: "layout.focus-ring", lines: ring }];
}
```
