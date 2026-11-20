.pragma library

function modeVisible(mode, fullscreen) {
    if (mode === "off")
        return false;
    if (mode === "always")
        return true;
    if (mode === "unlessFullscreen")
        return !fullscreen;
    return false;
}

function anchorsFor(corner) {
    return {
        topLeft:    { top: true, right: false, bottom: false, left: true },
        topRight:   { top: true, right: true, bottom: false, left: false },
        bottomLeft: { top: false, right: false, bottom: true, left: true },
        bottomRight: { top: false, right: true, bottom: true, left: false }
    }[corner] || { top: false, right: false, bottom: false, left: false };
}
