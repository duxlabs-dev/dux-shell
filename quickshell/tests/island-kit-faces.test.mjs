import assert from "node:assert/strict";
import test from "node:test";
import { K } from "./island-kit-load.mjs";
import { readFileSync } from "node:fs";
import { loadScript } from "./qml-script.mjs";

const C = loadScript(new URL("../DCommon/Common/Contrast.js", import.meta.url));
// Contrast.mix builds its colour with Qt.rgba, as QML gives it.
for (const context of [C, K.Contrast])
    context.Qt = { rgba: (r, g, b, a) => ({ r, g, b, a }) };

test("an alert's rings, read off their clock: two leave a gap apart, each is gone after its span, then it is over", () => {
    const span = 1300, gap = K.beat("ringGap", 250), pause = K.beat("ringPause", 250);
    assert.ok(gap > 0 && gap < span && pause > gap);
    // One ring: it grows from 0, is gone at its span (1 = not out).
    assert.equal(K.ringT(0, span, gap, 1, pause, 1, 0), 0);
    assert.equal(K.ringT(span / 2, span, gap, 1, pause, 1, 0), 0.5);
    assert.equal(K.ringT(span, span, gap, 1, pause, 1, 0), 1);
    assert.ok(!K.ringsOver(span - 1, span, gap, 1, pause, 1));
    assert.ok(K.ringsOver(span, span, gap, 1, pause, 1));
    // Two rings: the second leaves one gap later, while the first still grows.
    assert.equal(K.ringT(gap / 2, span, gap, 2, pause, 1, 1), 1);
    assert.equal(K.ringT(gap, span, gap, 2, pause, 1, 0), gap / span);
    assert.equal(K.ringT(gap, span, gap, 2, pause, 1, 1), 0);
    assert.equal(K.ringT(span + 1, span, gap, 2, pause, 1, 0), 1);
    assert.ok(K.ringsOver(span + gap, span, gap, 2, pause, 1));
    // No animations: over at once.
    assert.ok(K.ringsOver(0, 0, 0, 2, 0, 1));
    assert.equal(K.ringT(0, 0, 0, 2, 0, 1, 0), 1);
    assert.equal(K.beat("ringGap", 0), 0);
});

// Colours as QML hands them to a script: r, g, b in 0..1.
const rgb = hex => ({ r: parseInt(hex.slice(1, 3), 16) / 255, g: parseInt(hex.slice(3, 5), 16) / 255, b: parseInt(hex.slice(5, 7), 16) / 255 });
const themeOf = colours => Object.fromEntries(Object.entries(colours).map(([role, hex]) => [role, rgb(hex)]));
// The island's grounds and the tones alertTones reads, in five themes: Monochrome's warning is dark (dark mode) or pale
// (light mode); the wallpaper ones have a pale (light) or dark (dark) error container, under 3:1 on their surfaces;
// stock Blue light without matugen takes Theme's blended error roles, its error container tone under 4.5:1 on its text.
const themes = {
    "Blue light, no matugen": { surface: "#f7f9ff", surfaceContainer: "#eceef4", surfaceContainerHigh: "#e6e8ee", surfaceContainerHighest: "#e0e2e8", surfaceBright: "#f7f9ff", surfaceDim: "#eceef4", surfaceText: "#181c20", warning: "#904A00", error: "#F2B8B5", onError: "#f7f9ff", errorContainer: "#ead7da", onErrorContainer: "#856a6a" },
    "Monochrome dark": { surface: "#2a2a2a", surfaceContainer: "#353535", surfaceContainerHigh: "#424242", surfaceContainerHighest: "#505050", surfaceBright: "#505050", surfaceDim: "#131315", surfaceText: "#e4e2e3", warning: "#3f4759", error: "#ffb4ab", onError: "#690005", errorContainer: "#93000a", onErrorContainer: "#ffdad6" },
    "Monochrome light": { surface: "#f5f5f6", surfaceContainer: "#e8e8ea", surfaceContainerHigh: "#dcdcde", surfaceContainerHighest: "#d0d0d2", surfaceBright: "#f5f5f6", surfaceDim: "#e8e8ea", surfaceText: "#2a2a2a", warning: "#f9e79f", error: "#ba1a1a", onError: "#ffffff", errorContainer: "#ffdad6", onErrorContainer: "#410002" },
    "wallpaper dark": { surface: "#141218", surfaceContainer: "#211f24", surfaceContainerHigh: "#2b292f", surfaceContainerHighest: "#36343a", surfaceBright: "#3b383e", surfaceDim: "#141218", surfaceText: "#e6e0e9", warning: "#FF9800", error: "#f2b8b5", onError: "#601410", errorContainer: "#8c1d18", onErrorContainer: "#f9dedc" },
    "wallpaper light": { surface: "#fef7ff", surfaceContainer: "#f3edf7", surfaceContainerHigh: "#ece6f0", surfaceContainerHighest: "#e6e0e9", surfaceBright: "#fef7ff", surfaceDim: "#ded8e1", surfaceText: "#1d1b20", warning: "#904A00", error: "#b3261e", onError: "#ffffff", errorContainer: "#f9dedc", onErrorContainer: "#410e0b" }
};

test("an alert's shape stands 3:1 off every island ground, its icon 3:1 and its initial 4.5:1 on it, in every theme; no alert, no tones", () => {
    for (const [name, colours] of Object.entries(themes)) {
        const theme = themeOf(colours);
        for (const alert of ["critical", "important"]) {
            const [shape, icon, text] = K.alertTones(alert, theme);
            for (const role of K.islandGrounds)
                assert.ok(C.ratio(shape, theme[role]) >= K.markContrast, `${name} ${alert} on ${role}: ${C.ratio(shape, theme[role]).toFixed(2)}`);
            assert.ok(C.ratio(icon, shape) >= K.markContrast, `${name} ${alert} icon: ${C.ratio(icon, shape).toFixed(2)}`);
            assert.ok(C.ratio(text, shape) >= K.textContrast, `${name} ${alert} initial: ${C.ratio(text, shape).toFixed(2)}`);
        }
        assert.equal(K.alertTones("", theme), null);
    }
    // Where it reads, the container keeps its own icon tone, the initial passing on to the surface where that tone is
    // under 4.5:1; a pale container gives way to full error.
    const dim = themeOf({ ...themes["wallpaper dark"], errorContainer: "#ff5449" });
    assert.deepEqual(Array.from(K.alertTones("critical", dim)), [dim.errorContainer, dim.onError, dim.surface]);
    const light = themeOf(themes["wallpaper light"]);
    assert.deepEqual(Array.from(K.alertTones("critical", light)), [light.error, light.onError, light.onError]);
});

test("the light warning tone reads at 4.5:1 on light surfaces", () => {
    const real = /readonly property color lightWarning: "(#[0-9A-Fa-f]{6})"/.exec(readFileSync(new URL("../Common/Theme.qml", import.meta.url), "utf8"))?.[1].toLowerCase();
    assert.ok(real, "Theme.qml declares lightWarning");
    // Stock Blue Light and a wallpaper light theme: surface and containers, the hover tint over them included.
    for (const ground of ["#f7f9ff", "#eceef4", "#e6e8ee", "#e0e2e8", "#fef7ff", "#f3edf7", "#ece6f0", "#e6e0e9", "#ded8e1"])
        assert.ok(C.ratio(rgb(real), rgb(ground)) >= 4.5, `${real} on ${ground}: ${C.ratio(rgb(real), rgb(ground)).toFixed(2)}`);
});

test("a warning ground keeps the light-mode text its readers lay on it (the toast) at 4.5:1; the light tone would not", () => {
    const theme = readFileSync(new URL("../Common/Theme.qml", import.meta.url), "utf8");
    const ground = /warningGround: currentThemeData\.warning \|\| stockWarning/.test(theme) && /readonly property color stockWarning: "(#[0-9A-Fa-f]{6})"/.exec(theme)?.[1];
    const light = /readonly property color lightWarning: "(#[0-9A-Fa-f]{6})"/.exec(theme)?.[1];
    assert.ok(ground && light, "Theme.qml declares warningGround on stockWarning, and lightWarning");
    // The toast's light-mode text is the surface text: the wallpaper and stock light themes'.
    for (const text of [themes["wallpaper light"].surfaceText, themes["Monochrome light"].surfaceText, "#191c20"]) {
        assert.ok(C.ratio(rgb(ground), rgb(text)) >= 4.5, `${text} on ${ground}: ${C.ratio(rgb(ground), rgb(text)).toFixed(2)}`);
        assert.ok(C.ratio(rgb(light), rgb(text)) < 4.5, `${light} is a text tone, not a ground`);
    }
});

test("a ready face's tone stands 3:1 off every island ground and off its ring's track there, else the surface's text", () => {
    for (const [name, colours] of Object.entries(themes)) {
        const theme = themeOf({ ...colours, primary: "#9ecaff", success: "#4CAF50" });
        for (const accent of ["error", "warning", "primary", "success", "unknown"]) {
            const tone = K.readyTone(accent, theme);
            for (const role of K.islandGrounds) {
                const track = C.mix(theme[role], tone, K.readyTrackAlpha);
                assert.ok(C.ratio(tone, theme[role]) >= K.markContrast && C.ratio(tone, track) >= K.markContrast, `${name} ${accent} on ${role}`);
            }
        }
    }
    // A pale accent on a light theme gives way; one that stands keeps its colour; an unknown one is the primary.
    const light = themeOf({ ...themes["wallpaper light"], primary: "#6750a4", success: "#4CAF50" });
    assert.equal(K.readyTone("success", light), light.surfaceText);
    assert.equal(K.readyTone("primary", light), light.primary);
    assert.equal(K.readyTone("unknown", light), light.primary);
    // The host surface the island paints counts: a primary container it does not stand on makes it give way.
    const hosted = themeOf({ ...themes["wallpaper light"], primary: "#6750a4", success: "#4CAF50", hostSurface: "#7d5260" });
    assert.ok(C.ratio(hosted.primary, hosted.hostSurface) < K.markContrast);
    assert.equal(K.readyTone("primary", hosted), hosted.surfaceText);
    assert.equal(K.readyTone("primary", themeOf({ ...themes["wallpaper light"], primary: "#6750a4", hostSurface: "#eaddff" })).r, light.primary.r);
});

test("a meter's share: NaN and below 0 read as 0, over 1 as 1", () => {
    assert.equal(K.unit(NaN), 0);
    assert.equal(K.unit(-0.2), 0);
    assert.equal(K.unit(undefined), 0);
    assert.equal(K.unit(0.4), 0.4);
    assert.equal(K.unit(1.7), 1);
    assert.equal(K.unit(Infinity), 1);
});

test("a ringing call rings again after a pause, forever, and its shape swings on each ring, still in the pause", () => {
    const span = 1300, gap = K.beat("ringGap", 250), pause = K.beat("ringPause", 250);
    const cycle = gap + span + pause;
    // cycles 0: never over; the next cycle's rings leave as the first's did.
    assert.ok(!K.ringsOver(100 * cycle, span, gap, 2, pause, 0));
    assert.equal(K.ringT(cycle + gap, span, gap, 2, pause, 0, 1), 0);
    assert.equal(K.ringT(gap + span + pause / 2, span, gap, 2, pause, 0, 0), 1);
    assert.equal(K.ringT(gap + span + pause / 2, span, gap, 2, pause, 0, 1), 1);
    // The swing (-1..1) on the wing's entry spring: at rest as a ring leaves, kicked right after, settled in the pause.
    const swing = ms => K.ringSwing(ms, span, gap, 2, pause, 0, 220, 0.6, 1);
    assert.equal(swing(0), 0);
    const peak = Math.max(...Array.from({ length: 40 }, (_, i) => Math.abs(swing(i * 10))));
    assert.ok(peak > 0.9 && peak <= 1.2);
    assert.ok(Math.abs(swing(cycle - 1)) < 0.01);
    assert.equal(swing(cycle + 50), swing(50));
    // Over (one cycle done) or no animations: still.
    assert.equal(K.ringSwing(cycle * 2, span, gap, 2, pause, 1, 220, 0.6, 1), 0);
    assert.equal(K.ringSwing(50, 0, 0, 2, 0, 0, 220, 0.6, 1), 0);
    // A negative damping ratio would grow: still, as without stiffness.
    assert.equal(K.ringSwing(50, span, gap, 2, pause, 0, 220, -0.5, 1), 0);
});
