.pragma library

function stepAccumulator(accumulated, delta, threshold) {
    const base = (accumulated * delta) < 0 ? 0 : accumulated;
    const next = base + delta;
    const units = Math.trunc(Math.abs(next) / threshold);
    if (units <= 0)
        return {
            remainder: next,
            units: 0,
            sign: 0
        };
    const sign = next > 0 ? 1 : -1;
    return {
        remainder: next - sign * units * threshold,
        units: units,
        sign: sign
    };
}
