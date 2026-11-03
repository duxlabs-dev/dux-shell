.pragma library

const PERCENT = "%";
const PIXELS = "px";

function parse(value) {
    const parts = String(value || "").trim().split(/\s+/);
    if (parts[0] !== "proportion")
        return {
            unit: PIXELS,
            amount: parts[parts.length - 1] || ""
        };
    const fraction = parseFloat(parts[1]);
    return {
        unit: PERCENT,
        amount: isNaN(fraction) ? "" : String(Math.round(fraction * 10000) / 100)
    };
}

function format(unit, amount) {
    const number = parseFloat(amount);
    if (isNaN(number) || number <= 0)
        return "";
    if (unit === PERCENT)
        return "proportion " + Math.round(number * 100) / 10000;
    return "fixed " + Math.round(number);
}

function label(value) {
    const size = parse(value);
    return size.amount + size.unit;
}
