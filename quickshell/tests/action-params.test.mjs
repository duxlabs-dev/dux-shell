import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const params = loadScript(new URL("../Common/ActionParams.js", import.meta.url));

const percent = [{ name: "percent", type: "percent", min: 0, max: 100 }];
const minutes = [{ name: "duration", type: "duration", unit: "minutes", min: 1, max: 1440 }];
const step = [{ name: "step", type: "int", min: 1, max: 100 }];
const workspace = [{ name: "workspace", type: "int", min: 1, max: 99 }];

function parsed(query, spec) {
    return JSON.parse(JSON.stringify(params.parse(query, spec)));
}

test("percent forms", () => {
    const cases = [
        ["parlaklığı %40 yap", 40],
        ["40% brightness", 40],
        ["40 %", 40],
        ["yüzde 40", 40],
        ["yuzde kirk bes", 45],
        ["ses 40 yap", 40],
        ["sesi 80'e çıkar", 80],
        ["sesi 80’e çıkar", 80],
        ["volume to 35", 35],
        ["twenty-five percent", 25],
        ["set it to seventy five", 75],
        ["yüz", 100],
        ["one hundred", 100],
        ["sıfır", 0],
        ["ses %0", 0],
        ["yüzde bir", 1],
        ["2 saat 40 yap", 40]
    ];
    for (const [query, expected] of cases)
        assert.deepEqual(parsed(query, percent), { percent: expected }, query);
});

test("values are clamped to the spec range", () => {
    assert.deepEqual(parsed("sesi 250 yap", percent), { percent: 100 });
    assert.deepEqual(parsed("yüzde 150", percent), { percent: 100 });
    assert.deepEqual(parsed("adım 0", step), { step: 1 });
    assert.deepEqual(parsed("pencereyi 500. çalışma alanına taşı", workspace), { workspace: 99 });
});

test("no number, no key", () => {
    assert.deepEqual(parsed("sesi kıs", percent), {});
    assert.deepEqual(parsed("turn on the lights", percent), {});
    assert.deepEqual(parsed("bir şarkı çal", percent), {});
});

test("an action without params ignores any number", () => {
    assert.deepEqual(parsed("wifi 40 aç", []), {});
    assert.deepEqual(parsed("15 dakika", undefined), {});
});

test("durations in either language and unit spelling", () => {
    const cases = [
        ["15 dakika", 15],
        ["15 dk zamanlayıcı kur", 15],
        ["15m", 15],
        ["15 minutes", 15],
        ["1 saat 30 dk", 90],
        ["1h30m", 90],
        ["2 hours", 120],
        ["iki saat", 120],
        ["bir saat", 60],
        ["on dakika", 10],
        ["on beş dakika", 15],
        ["kırk beş dakika", 45],
        ["yarım saat", 30],
        ["half an hour", 30],
        ["bir buçuk saat", 90],
        ["çeyrek saat", 15],
        ["90 sn", 90 / 60],
        ["30", 30],
        ["rahatsız etme 45", 45],
        ["1 saat 15 dakika 30 saniye", 75.5]
    ];
    for (const [query, expected] of cases)
        assert.deepEqual(parsed(query, [{ name: "duration", type: "duration", unit: "minutes", min: 0, max: 1440 }]), { duration: expected }, query);
});

test("duration is expressed in the unit of the spec and clamped", () => {
    assert.deepEqual(parsed("2 dakika", [{ name: "d", type: "duration", unit: "seconds" }]), { d: 120 });
    assert.deepEqual(parsed("90 minutes", [{ name: "d", type: "duration", unit: "hours" }]), { d: 1.5 });
    assert.deepEqual(parsed("3000 dakika", minutes), { duration: 1440 });
    assert.deepEqual(parsed("5 saniye", minutes), { duration: 1 });
});

test("a number followed by a duration unit is not a percent", () => {
    assert.deepEqual(parsed("15 dakika sonra sesi 30 yap", percent), { percent: 30 });
    assert.deepEqual(parsed("sesi 30 yap 15 dakika", percent), { percent: 30 });
});

test("ordinals pick the workspace", () => {
    assert.deepEqual(parsed("pencereyi 3. çalışma alanına taşı", workspace), { workspace: 3 });
    assert.deepEqual(parsed("move to the third workspace", workspace), { workspace: 3 });
    assert.deepEqual(parsed("ikinci masaüstü", workspace), { workspace: 2 });
    assert.deepEqual(parsed("workspace 7", workspace), { workspace: 7 });
});

test("English on/ten and a Turkish article are not read as numbers", () => {
    assert.deepEqual(parsed("turn on wifi", percent), {});
    assert.deepEqual(parsed("turn on two lights", step), { step: 2 });
    assert.deepEqual(parsed("bir dakika", minutes), { duration: 1 });
    assert.deepEqual(parsed("second workspace", workspace), { workspace: 2 });
    assert.deepEqual(parsed("15 second", [{ name: "d", type: "duration", unit: "seconds" }]), { d: 15 });
});

test("diacritics and capital dotted letters fold", () => {
    assert.deepEqual(parsed("YÜZDE ELLİ", percent), { percent: 50 });
    assert.deepEqual(parsed("Altmış beş", percent), { percent: 65 });
    assert.deepEqual(parsed("ALTMIŞ", percent), { percent: 60 });
});

test("several params take their numbers in order", () => {
    const spec = [{ name: "level", type: "percent", min: 0, max: 100 }, { name: "length", type: "duration", unit: "minutes" }];
    assert.deepEqual(parsed("%30 sesle 10 dakika", spec), { level: 30, length: 10 });
});

test("intent of a switch", () => {
    const cases = [
        ["wifi aç", "on"],
        ["wifi'yi kapat", "off"],
        ["turn off bluetooth", "off"],
        ["turn on night light", "on"],
        ["bluetooth", ""],
        ["aç kapat", ""],
        ["devre dışı bırak", "off"],
        ["disable dnd", "off"],
        ["gece ışığı", ""]
    ];
    for (const [query, expected] of cases)
        assert.equal(params.intent(query, false), expected, query);
});

test("intent of a mute switch reads the sound, not the switch", () => {
    const cases = [
        ["sesi kapat", "on"],
        ["sesi aç", "off"],
        ["sustur", "on"],
        ["mikrofonu sustur", "on"],
        ["unmute", "off"],
        ["mute", "on"],
        ["turn off the sound", "on"],
        ["turn on the sound", "off"],
        ["ses", ""]
    ];
    for (const [query, expected] of cases)
        assert.equal(params.intent(query, true), expected, query);
});
