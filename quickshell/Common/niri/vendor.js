.pragma library

function vendorKind(sysVendorText) {
    const vendor = String(sysVendorText ?? "").trim().toLowerCase();
    return vendor.startsWith("framework") ? "framework" : "other";
}

// Relative to the shell dir.
function logoFor(kind) {
    return kind === "framework" ? "assets/niri-page/framework.svg" : "assets/niri-page/microslop.svg";
}
