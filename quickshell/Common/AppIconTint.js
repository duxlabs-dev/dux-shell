.pragma library
.import "../DCommon/Common/Hct.js" as Hct

// Dux Labs app icons are drawn in tones of this purple. Paints of any other hue keep their color.
const BRAND_HUE = 299;
const BRAND_CHROMA = 48;
const BRAND_HUE_REACH = 30;
const PAINT = /((?:fill|stroke|stop-color)\s*[=:]\s*["']?)#([0-9a-f]{6})\b/gi;

function hexToRgb(hex) {
    const value = parseInt(hex, 16);
    return {
        r: (value >> 16) / 255,
        g: (value >> 8 & 255) / 255,
        b: (value & 255) / 255
    };
}

// The theme color is one tone of its palette, so its chroma is measured against the brand at that tone.
function chromaScale(theme) {
    const brand = Hct.toHct(Hct.fromHct(BRAND_HUE, BRAND_CHROMA, theme.tone));
    return theme.chroma / Math.max(brand.chroma, 1);
}

function recolor(svg, theme) {
    const scale = chromaScale(theme);
    return svg.replace(PAINT, (paint, lead, hex) => {
        const hct = Hct.toHct(hexToRgb(hex));
        if (Hct.differenceDegrees(hct.hue, BRAND_HUE) > BRAND_HUE_REACH)
            return paint;
        return lead + String(Hct.fromHct(theme.hue + hct.hue - BRAND_HUE, hct.chroma * scale, hct.tone));
    });
}

function url(svg, theme) {
    const start = svg.indexOf("<svg");
    if (start === -1)
        return "";
    return "data:image/svg+xml;utf8," + encodeURIComponent(recolor(svg.slice(start), theme));
}
