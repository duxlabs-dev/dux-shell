.pragma library

// A gap longer than breakGap seconds before a line, also before the first one, is an instrumental break.
function buildItems(lines, breakGap) {
    const items = [];
    let previousEnd = 0;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.t - previousEnd > breakGap)
            items.push({
                kind: "break",
                line: i,
                t: previousEnd,
                e: line.t
            });
        items.push({
            kind: "line",
            line: i,
            t: line.t,
            e: line.e,
            group: line
        });
        if (Number.isFinite(line.e))
            previousEnd = Math.max(previousEnd, line.e);
    }
    return items;
}

function plainItems(lines) {
    return lines.map((text, i) => ({
                kind: "plain",
                line: i,
                text
            }));
}

// The break being played wins over the line before it, and the line moving in early wins over the break.
function centreItem(items, at, followIndex) {
    let centre = 0;
    for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (item.t > at && item.line > followIndex)
            break;
        if (item.t <= at || (item.kind === "line" && item.line <= followIndex))
            centre = i;
    }
    return centre;
}

// Cues in text order, each with its character range and an end that never runs past the next cue.
function cueSpans(part) {
    const cues = part.w ?? [];
    const byTime = cues.map(cue => cue.t).sort((a, b) => a - b);
    const spans = [];
    let offset = 0;
    for (const cue of cues) {
        const next = byTime.find(t => t > cue.t) ?? Infinity;
        spans.push({
            start: offset,
            end: offset + cue.x.length,
            t: cue.t,
            e: Math.min(part.e, next, cue.e > cue.t ? cue.e : Infinity)
        });
        offset += cue.x.length;
    }
    return spans;
}

// Character ranges of the rows the text wraps into. Text without spaces breaks between cues, and
// a token wider than a row breaks between characters.
function layoutRows(text, spans, maxWidth, measure) {
    const tokens = [];
    if (/\s/.test(text.trim())) {
        const pattern = /\S+/g;
        let match;
        while ((match = pattern.exec(text)) !== null)
            tokens.push([match.index, match.index + match[0].length]);
    } else if (spans.length > 0) {
        for (const span of spans)
            tokens.push([span.start, span.end]);
    } else {
        tokens.push([0, text.length]);
    }
    const rows = [];
    let row = null;
    for (const [start, end] of tokens) {
        if (row && measure(text.slice(row.start, end)) <= maxWidth) {
            row.end = end;
            continue;
        }
        if (row)
            rows.push(row);
        row = {
            start,
            end
        };
        while (row.end - row.start > 1 && measure(text.slice(row.start, row.end)) > maxWidth) {
            let cut = row.start + 1;
            while (cut + 1 < row.end && measure(text.slice(row.start, cut + 1)) <= maxWidth)
                cut++;
            rows.push({
                start: row.start,
                end: cut
            });
            row = {
                start: cut,
                end: row.end
            };
        }
    }
    if (row)
        rows.push(row);
    return rows.map(range => {
        const rowText = text.slice(range.start, range.end);
        return {
            text: rowText,
            width: measure(rowText),
            segments: rowSegments(text, range, spans, measure)
        };
    });
}

// The pixel stretch of each cue inside a row. A cue split over two rows splits its time in proportion.
function rowSegments(text, range, spans, measure) {
    const segments = [];
    for (const span of spans) {
        const from = Math.max(span.start, range.start);
        const to = Math.min(span.end, range.end);
        if (from >= to)
            continue;
        const length = Math.max(1, span.end - span.start);
        const duration = Number.isFinite(span.e) ? span.e - span.t : 0;
        segments.push({
            x0: measure(text.slice(range.start, from)),
            x1: measure(text.slice(range.start, to)),
            t: span.t + duration * (from - span.start) / length,
            e: span.t + duration * (to - span.start) / length
        });
    }
    return segments;
}

function partLayouts(parts, width, lead, background, gap) {
    let y = 0;
    return parts.map(part => {
        const metrics = part.background ? background : lead;
        const rows = layoutRows(part.x || "\u00a0", cueSpans(part), width, text => metrics.advanceWidth(text));
        const rowHeight = Math.ceil(metrics.height);
        const layout = {
            part,
            rows,
            rowHeight,
            font: metrics.font,
            y
        };
        y += rows.length * rowHeight + gap;
        return layout;
    });
}

function layoutsHeight(layouts, gap) {
    return layouts.reduce((sum, layout) => sum + layout.rows.length * layout.rowHeight, 0) + Math.max(0, layouts.length - 1) * gap;
}

function rowHeight(item, layouts, breakSize, padding, gap) {
    return (item.kind === "break" ? breakSize : layoutsHeight(layouts, gap)) + padding * 2;
}

// How far into the row the sung part reaches at a time. Without the sweep a cue fills at once.
function rowFill(segments, at, sweep) {
    let fill = 0;
    for (const segment of segments) {
        if (segment.t > at)
            continue;
        const progress = sweep && segment.e > segment.t ? Math.min(1, (at - segment.t) / (segment.e - segment.t)) : 1;
        fill = Math.max(fill, segment.x0 + (segment.x1 - segment.x0) * progress);
    }
    return fill;
}

// The first strong character decides, so digits and punctuation do not count.
function isRtl(text) {
    for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        if ((code >= 0x0590 && code <= 0x08FF) || (code >= 0xFB1D && code <= 0xFDFF) || (code >= 0xFE70 && code <= 0xFEFF))
            return true;
        if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A) || (code >= 0xC0 && code <= 0x58F) || (code >= 0x900 && code <= 0x1FFF) || (code >= 0x2E80 && code <= 0xA4CF) || (code >= 0xAC00 && code <= 0xD7AF))
            return false;
    }
    return false;
}
