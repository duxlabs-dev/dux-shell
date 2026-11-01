.pragma library

function kdlString(s) {
    return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"';
}

// niri replaces the user's whole device block with an included one, even an empty one
function deviceBlock(name, lines) {
    if (lines.length === 0)
        return "";
    return "    " + name + " {\n" + lines.map(line => "        " + line + "\n").join("") + "    }\n";
}

// niri's own defaults (accel-speed 0, flags off) are left out so an untouched device keeps the user's block
function pointerLines(d) {
    const lines = [];
    if (d.speed !== 0)
        lines.push(`accel-speed ${d.speed.toFixed(1)}`);
    if (d.profile !== "default")
        lines.push("accel-profile " + kdlString(d.profile));
    if (d.clickMethod !== undefined && d.clickMethod !== "default")
        lines.push("click-method " + kdlString(d.clickMethod));
    if (d.naturalScroll)
        lines.push("natural-scroll");
    if (d.leftHanded)
        lines.push("left-handed");
    if (d.disableOnExternalMouse)
        lines.push("disabled-on-external-mouse");
    if (d.disableWhileTyping)
        lines.push("dwt");
    if (d.middleEmulation)
        lines.push("middle-emulation");
    if (d.scrollFactor !== 1.0)
        lines.push(`scroll-factor ${d.scrollFactor.toFixed(1)}`);
    if (d.scrollMethod !== "default")
        lines.push("scroll-method " + kdlString(d.scrollMethod));
    return lines;
}

function mouseBlock(mouse) {
    return deviceBlock("mouse", pointerLines(mouse));
}

function touchpadBlock(touchpad) {
    const lines = pointerLines(touchpad);
    if (touchpad.tap)
        lines.unshift("tap");
    const pinch = touchpad.pinchSensitivity;
    // settings.json can be hand edited: keep the slider range (MouseTouchpadTab).
    if (Number.isFinite(pinch) && pinch >= 0.1 && pinch <= 3.0 && pinch !== 1.0)
        lines.push(`pinch-sensitivity ${touchpad.pinchSensitivity.toFixed(1)}`);
    if (!touchpad.tapAndDrag)
        lines.push("drag false");
    if (touchpad.dragLock)
        lines.push("drag-lock");
    return deviceBlock("touchpad", lines);
}
