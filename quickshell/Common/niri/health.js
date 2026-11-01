.pragma library

// A fragment DMS wrote but niri never included: its settings stay dormant,
// so the doctor's add-include finding is the one the page acts on by itself.
function dormant(findings) {
    return (findings ?? []).find(f => f?.fix === "add-include" && /^dms\/[\w.-]+$/.test(String(f?.subject ?? ""))) ?? null;
}

// The IPC fragment parameter of a finding subject: "dms/input.kdl" -> "input.kdl".
function fragmentOf(subject) {
    return String(subject ?? "").replace(/^dms\//, "");
}