function directionIndex(degrees) {
    if (!Number.isFinite(degrees))
        return -1;
    return Math.round(((degrees % 360) + 360) % 360 / 45) % 8;
}

function relativeLevel(value, values, zeroBased) {
    if (!Number.isFinite(value))
        return 0;
    const finite = values.filter(v => Number.isFinite(v));
    if (finite.length === 0)
        return 0;
    const minimum = zeroBased ? 0 : Math.min(...finite);
    const maximum = Math.max(...finite);
    if (maximum <= minimum)
        return zeroBased ? (value > 0 ? 1 : 0) : 0.5;
    return Math.max(0, Math.min(1, (value - minimum) / (maximum - minimum)));
}

function levelPath(width, height, radius, progress, amplitude) {
    const r = Math.min(radius, width / 2, height / 2);
    const y = Math.max(r, height * (1 - Math.max(0, Math.min(1, progress))));
    const cornerDistance = Math.max(y - (height - r), 0);
    const inset = r > 0 ? r - Math.sqrt(Math.max(0, r * r - cornerDistance * cornerDistance)) : 0;
    const wave = cornerDistance > 0 ? 0 : Math.min(amplitude, y / 2, (height - y) / 2);
    const span = width - inset * 2;
    let path = `M ${inset} ${y}`;
    for (let i = 0; i < 4; i++) {
        const x = inset + span * i / 4;
        path += ` C ${x + span / 12} ${y - wave} ${x + span / 6} ${y + wave} ${x + span / 4} ${y}`;
    }
    if (y <= height - r)
        path += ` L ${width} ${height - r}`;
    path += r > 0 ? ` A ${r} ${r} 0 0 1 ${width - r} ${height}` : ` L ${width} ${height}`;
    path += ` L ${r} ${height}`;
    if (y > height - r)
        return path + ` A ${r} ${r} 0 0 1 ${inset} ${y} Z`;
    path += r > 0 ? ` A ${r} ${r} 0 0 1 0 ${height - r}` : ` L 0 ${height}`;
    return path + " Z";
}

function pressurePath(size, inset, progress, square) {
    const fraction = Math.max(0, Math.min(1, progress));
    const radius = Math.max(0, size / 2 - inset);
    if (!square) {
        const start = Math.PI * 3 / 4;
        const end = start + Math.PI * 3 / 2 * fraction;
        const center = size / 2;
        return `M ${center + radius * Math.cos(start)} ${center + radius * Math.sin(start)} A ${radius} ${radius} 0 ${fraction > 2 / 3 ? 1 : 0} 1 ${center + radius * Math.cos(end)} ${center + radius * Math.sin(end)}`;
    }
    const points = [[inset, size - inset], [inset, inset], [size - inset, inset], [size - inset, size - inset]];
    let path = `M ${points[0][0]} ${points[0][1]}`;
    for (let i = 0; i < 3; i++) {
        const amount = Math.max(0, Math.min(1, fraction * 3 - i));
        if (amount === 0)
            break;
        path += ` L ${points[i][0] + (points[i + 1][0] - points[i][0]) * amount} ${points[i][1] + (points[i + 1][1] - points[i][1]) * amount}`;
    }
    return path;
}

function conditionShape(code, isDay) {
    switch (code) {
    case 0:
    case 1:
        return isDay ? "sunny" : "cookie9";
    case 2:
    case 3:
        return "puffy";
    case 45:
    case 48:
        return "pill";
    case 71:
    case 73:
    case 75:
    case 77:
    case 85:
    case 86:
        return "cookie12";
    case 95:
    case 96:
    case 99:
        return "burst";
    default:
        return "clover4";
    }
}

function uvCategory(value) {
    if (!Number.isFinite(value) || value < 0)
        return -1;
    if (value < 3)
        return 0;
    if (value < 6)
        return 1;
    if (value < 8)
        return 2;
    if (value < 11)
        return 3;
    return 4;
}
