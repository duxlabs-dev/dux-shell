.pragma library

// Extracts the numeric slots of an action from the free text a user typed
// ("%40", "yüzde kırk", "1 saat 30 dk", "15m"). Turkish and English, with or
// without diacritics: matching runs on a folded copy of the text.

const FOLD = {
    "ç": "c",
    "ğ": "g",
    "ı": "i",
    "ö": "o",
    "ş": "s",
    "ü": "u",
    "â": "a",
    "î": "i",
    "û": "u"
};

function fold(text) {
    return String(text === undefined || text === null ? "" : text).replace(/İ/g, "i").toLowerCase().replace(/[̀-ͯ]/g, "").replace(/[çğıöşüâîû]/g, c => FOLD[c]);
}

const UNITS = {
    one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
    eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
    zero: 0, sifir: 0, bir: 1, iki: 2, uc: 3, dort: 4, bes: 5, alti: 6, yedi: 7, sekiz: 8, dokuz: 9
};

const TENS = {
    twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90,
    on: 10, yirmi: 20, otuz: 30, kirk: 40, elli: 50, altmis: 60, yetmis: 70, seksen: 80, doksan: 90
};

const HUNDRED = { hundred: 100, yuz: 100 };

const ORDINALS = {
    first: 1, second: 2, third: 3, fourth: 4, fifth: 5, sixth: 6, seventh: 7, eighth: 8, ninth: 9, tenth: 10,
    birinci: 1, ikinci: 2, ucuncu: 3, dorduncu: 4, besinci: 5, altinci: 6, yedinci: 7, sekizinci: 8, dokuzuncu: 9, onuncu: 10
};

// "bir" (a/one) and "on" (the English preposition, Turkish ten) are only
// numbers next to a unit or a percent marker, never on their own.
const AMBIGUOUS = { bir: true, on: true };

const DURATION_UNITS = {
    saniye: "s", sn: "s", second: "s", seconds: "s", sec: "s", secs: "s",
    dakika: "m", dk: "m", minute: "m", minutes: "m", min: "m", mins: "m",
    saat: "h", hour: "h", hours: "h", hr: "h", hrs: "h"
};

// One-letter and short forms only count when glued to or right after a number.
const SHORT_UNITS = { s: "s", m: "m", h: "h", sa: "h" };

const UNIT_MINUTES = { s: 1 / 60, m: 1, h: 60 };
const TARGET_MINUTES = { seconds: 1 / 60, minutes: 1, hours: 60 };

const PERCENT_BEFORE = { yuzde: true, percent: true, pct: true };
const PERCENT_AFTER = { percent: true, pct: true, yuzde: true };

// After a Turkish "on" (ten) only Turkish digits can follow ("on beş"); an
// English "turn on two lights" must not become twelve.
const TURKISH_DIGITS = { sifir: true, bir: true, iki: true, uc: true, dort: true, bes: true, alti: true, yedi: true, sekiz: true, dokuz: true };

function tokenize(text) {
    const folded = fold(text);
    const raw = [];
    const pattern = /(\d+(?:[.,]\d+)?)|([a-z]+)|(%)/g;
    let match;
    while ((match = pattern.exec(folded)) !== null) {
        if (match[1] !== undefined)
            raw.push({ type: "num", value: parseFloat(match[1].replace(",", ".")), digits: true });
        else if (match[2] !== undefined)
            raw.push({ type: "word", word: match[2] });
        else
            raw.push({ type: "pct" });
    }
    return raw;
}

function isUnitWord(raw, i, previousIsNumber) {
    const token = raw[i];
    if (!token || token.type !== "word")
        return null;
    if (DURATION_UNITS[token.word])
        return DURATION_UNITS[token.word];
    if (previousIsNumber && SHORT_UNITS[token.word])
        return SHORT_UNITS[token.word];
    return null;
}

function percentMarkerAt(raw, i, before) {
    const token = raw[i];
    if (!token)
        return false;
    if (token.type === "pct")
        return true;
    if (token.type !== "word")
        return false;
    // "per cent" is two words, the second one marks it.
    return before ? !!PERCENT_BEFORE[token.word] : !!PERCENT_AFTER[token.word];
}

function wordValue(word) {
    if (word in TENS)
        return { kind: "tens", value: TENS[word] };
    if (word in HUNDRED)
        return { kind: "hundred", value: HUNDRED[word] };
    if (word in UNITS)
        return { kind: "unit", value: UNITS[word] };
    if (word in ORDINALS)
        return { kind: "ordinal", value: ORDINALS[word] };
    return null;
}

// Merges runs of number words ("yirmi beş", "twenty-five", "one hundred")
// into numeric tokens and attaches units, percent markers and the half-unit
// forms ("1 buçuk saat", "half an hour").
function lex(text) {
    const raw = tokenize(text);
    const out = [];
    for (let i = 0; i < raw.length; ) {
        const token = raw[i];
        if (token.type !== "word") {
            out.push(token);
            i++;
            continue;
        }

        // "second" is the unit after a number ("15 second") and the ordinal otherwise.
        const before = out[out.length - 1];
        const first = token.word === "second" && before && before.type === "num" ? null : wordValue(token.word);
        if (first) {
            let value = 0;
            let j = i;
            let consumedUnit = false;
            let sawTens = false;
            let tensWord = "";
            while (j < raw.length && raw[j].type === "word") {
                const part = wordValue(raw[j].word);
                if (!part)
                    break;
                if (part.kind === "ordinal") {
                    if (j === i) {
                        value = part.value;
                        j++;
                    }
                    break;
                }
                if (part.kind === "hundred") {
                    value = (value > 0 && value < 10 ? value : 1) * 100;
                    j++;
                    break;
                }
                if (part.kind === "tens") {
                    if (sawTens || consumedUnit)
                        break;
                    value += part.value;
                    sawTens = true;
                    tensWord = raw[j].word;
                    j++;
                    continue;
                }
                if (tensWord === "on" && !TURKISH_DIGITS[raw[j].word])
                    break;
                if (consumedUnit || (sawTens && part.value >= 10) || (!sawTens && j > i))
                    break;
                value += part.value;
                consumedUnit = true;
                j++;
            }
            if (j > i) {
                const ambiguous = j === i + 1 && AMBIGUOUS[token.word] === true;
                const previousIsPercent = out.length > 0 && percentMarkerAt(out, out.length - 1, true);
                const nextUnit = isUnitWord(raw, j, true) !== null || percentMarkerAt(raw, j, false) || (raw[j] && raw[j].type === "word" && raw[j].word === "bucuk");
                if (!ambiguous || previousIsPercent || nextUnit) {
                    out.push({ type: "num", value: value, digits: false });
                    i = j;
                    continue;
                }
            }
        }

        if ((token.word === "yarim" || token.word === "half") && i + 1 < raw.length) {
            let k = i + 1;
            if (raw[k].type === "word" && (raw[k].word === "an" || raw[k].word === "bir"))
                k++;
            const unit = isUnitWord(raw, k, false);
            if (unit) {
                out.push({ type: "num", value: 0.5, digits: false }, { type: "unit", unit: unit });
                i = k + 1;
                continue;
            }
        }
        if (token.word === "ceyrek" && i + 1 < raw.length) {
            const unit = isUnitWord(raw, i + 1, false);
            if (unit === "h") {
                out.push({ type: "num", value: 15, digits: false }, { type: "unit", unit: "m" });
                i += 2;
                continue;
            }
        }
        if (token.word === "bucuk") {
            out.push({ type: "half" });
            i++;
            continue;
        }

        const previous = out[out.length - 1];
        const unit = isUnitWord(raw, i, previous !== undefined && previous.type === "num");
        if (unit) {
            out.push({ type: "unit", unit: unit });
            i++;
            continue;
        }
        if (token.word === "per" && raw[i + 1] && raw[i + 1].type === "word" && raw[i + 1].word === "cent") {
            out.push({ type: "pct" });
            i += 2;
            continue;
        }
        out.push(token);
        i++;
    }

    // "1 buçuk saat": the half marker adds 0.5 to the number before it.
    const merged = [];
    for (const token of out) {
        const last = merged[merged.length - 1];
        if (token.type === "half" && last && last.type === "num") {
            last.value += 0.5;
            continue;
        }
        if (token.type !== "half")
            merged.push(token);
    }
    return merged;
}

function clamp(value, spec) {
    let out = value;
    if (typeof spec.min === "number" && out < spec.min)
        out = spec.min;
    if (typeof spec.max === "number" && out > spec.max)
        out = spec.max;
    return out;
}

function roundFor(value, spec) {
    if (spec.type === "duration")
        return Math.round(value * 1000) / 1000;
    return Math.round(value);
}

function findQuantity(tokens, used, spec) {
    // A number tied to a percent marker is the value the user means.
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token.type !== "num" || used[i])
            continue;
        const tied = (i > 0 && percentMarkerAt(tokens, i - 1, true)) || percentMarkerAt(tokens, i + 1, false);
        if (tied) {
            used[i] = true;
            return token.value;
        }
    }
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token.type !== "num" || used[i])
            continue;
        if (tokens[i + 1] && tokens[i + 1].type === "unit" && spec.type !== "duration")
            continue;
        used[i] = true;
        return token.value;
    }
    return null;
}

function findDuration(tokens, used, spec) {
    const target = TARGET_MINUTES[spec.unit] || 1;
    let minutes = 0;
    let found = false;
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token.type !== "num" || used[i])
            continue;
        const next = tokens[i + 1];
        if (next && next.type === "unit") {
            minutes += token.value * UNIT_MINUTES[next.unit];
            used[i] = true;
            used[i + 1] = true;
            found = true;
            i++;
        }
    }
    if (found)
        return minutes / target;
    // No unit typed: the number is already in the spec's own unit.
    return findQuantity(tokens, used, { type: "int" });
}

// Returns {name: value} for every param found in the query. Values are
// clamped to the spec's min/max and expressed in the spec's unit (durations
// default to minutes). A query without a usable number yields no key for it;
// an action without params always yields {}.
function parse(query, params) {
    const out = {};
    if (!params || params.length === 0)
        return out;
    const tokens = lex(query);
    const used = {};
    for (const spec of params) {
        const value = spec.type === "duration" ? findDuration(tokens, used, spec) : findQuantity(tokens, used, spec);
        if (value === null || value === undefined || isNaN(value))
            continue;
        out[spec.name] = clamp(roundFor(value, spec), spec);
    }
    return out;
}

const ON_WORDS = {
    ac: true, etkinlestir: true, baslat: true, calistir: true, on: true, enable: true, start: true,
    activate: true, connect: true, baglan: true, bagla: true
};
const OFF_WORDS = {
    kapat: true, kapa: true, durdur: true, sondur: true, off: true, disable: true, stop: true,
    deactivate: true, disconnect: true, kes: true
};
const MUTE_WORDS = { mute: true, sustur: true, sessize: true, sessiz: true, muted: true };
const UNMUTE_WORDS = { unmute: true, unmuted: true };

// "on" | "off" | "": what the user asked a switch to become. invert is for
// mute-like switches where opening the sound ("sesi aç") turns the switch off.
function intent(query, invert) {
    const words = fold(query).match(/[a-z]+/g) || [];
    let on = false;
    let off = false;
    let mute = false;
    let unmute = false;
    for (let i = 0; i < words.length; i++) {
        const word = words[i];
        if (ON_WORDS[word])
            on = true;
        if (OFF_WORDS[word])
            off = true;
        if (word === "devre" && words[i + 1] === "disi")
            off = true;
        if (MUTE_WORDS[word])
            mute = true;
        if (UNMUTE_WORDS[word])
            unmute = true;
    }
    if (invert) {
        if (unmute && !mute)
            return "off";
        if (mute && !unmute)
            return "on";
        if (on !== off)
            return on ? "off" : "on";
        return "";
    }
    if (on === off)
        return "";
    return on ? "on" : "off";
}
