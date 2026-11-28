.pragma library

// Native notched modes in physical px, notch centered; reported only with show_notch=1.
// 14" Pro is from Phosh gmobile; the 16" Pro and Airs are unverified estimates.
const panels = [
    {
        width: 3024,
        height: 1964,
        notchWidth: 368,
        notchHeight: 64
    },
    {
        width: 3456,
        height: 2234,
        notchWidth: 368,
        notchHeight: 64
    },
    {
        width: 2560,
        height: 1664,
        notchWidth: 322,
        notchHeight: 56
    },
    {
        width: 2880,
        height: 1864,
        notchWidth: 322,
        notchHeight: 56
    }
];

// Fractional scales round the logical size.
const tolerance = 2;

function isApple(compatible) {
    return Array.isArray(compatible) && compatible.some(entry => typeof entry === "string" && entry.startsWith("apple,"));
}

function cutout(compatible, logicalWidth, logicalHeight, scale) {
    if (!isApple(compatible) || !(logicalWidth > 0) || !(logicalHeight > 0) || !(scale > 0))
        return null;
    const width = logicalWidth * scale;
    const height = logicalHeight * scale;
    const panel = panels.find(entry => Math.abs(entry.width - width) <= tolerance && Math.abs(entry.height - height) <= tolerance);
    if (!panel)
        return null;
    const half = panel.notchWidth / scale / 2;
    return {
        start: logicalWidth / 2 - half,
        end: logicalWidth / 2 + half,
        height: panel.notchHeight / scale
    };
}
