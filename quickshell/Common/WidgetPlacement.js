.pragma library

function luminance(red, green, blue) {
    const linear = value => value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue);
}

function intersects(a, b) {
    return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
}

function candidates(width, height, blockWidth, blockHeight, inset, obstacles) {
    const right = width - inset - blockWidth;
    const bottom = height - inset - blockHeight;
    if (right < inset || bottom < inset)
        return [];
    const result = [];
    for (const y of [inset, (height - blockHeight) / 2, bottom]) {
        for (const x of [(width - blockWidth) / 2, inset, right]) {
            const rect = {
                x,
                y,
                width: blockWidth,
                height: blockHeight
            };
            if (!obstacles.some(obstacle => intersects(rect, obstacle)))
                result.push(rect);
        }
    }
    return result;
}

function choose(luma, sampleWidth, sampleHeight, width, height, choices, foregrounds) {
    if (!choices.length || !foregrounds.length || !luma.length || width <= 0 || height <= 0)
        return null;
    let best = null;
    let bestScore = -Infinity;
    for (const rect of choices) {
        const left = Math.max(0, Math.floor(rect.x * sampleWidth / width));
        const top = Math.max(0, Math.floor(rect.y * sampleHeight / height));
        const right = Math.min(sampleWidth, Math.ceil((rect.x + rect.width) * sampleWidth / width));
        const bottom = Math.min(sampleHeight, Math.ceil((rect.y + rect.height) * sampleHeight / height));
        const contrasts = [];
        let edges = 0;
        for (let y = top; y < bottom; y++) {
            for (let x = left; x < right; x++) {
                const value = luma[y * sampleWidth + x];
                contrasts.push(Math.min(...foregrounds.map(foreground => (Math.max(value, foreground) + 0.05) / (Math.min(value, foreground) + 0.05))));
                if (x > left)
                    edges += Math.abs(value - luma[y * sampleWidth + x - 1]);
                if (y > top)
                    edges += Math.abs(value - luma[(y - 1) * sampleWidth + x]);
            }
        }
        if (!contrasts.length)
            continue;
        contrasts.sort((a, b) => a - b);
        const score = contrasts[Math.floor(contrasts.length / 10)] - edges / contrasts.length * 4;
        if (score <= bestScore)
            continue;
        bestScore = score;
        best = rect;
    }
    return best;
}
