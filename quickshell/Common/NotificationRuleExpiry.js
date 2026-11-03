// Pure helpers for notification-rule expiry (timed mute rules). Kept free of
// QML dependencies so the logic test suite can exercise them directly.
// A rule with expiresAt > 0 (ms since epoch) stops muting once the
// timestamp passes; expiresAt of 0 or absent means "never expires".
// Remaining-time text is deliberately NOT formatted here: callers use the
// shared Common/Format.js formatter with translated format strings.

function isRuleExpired(rule, nowMs) {
    const expiresAt = rule && rule.expiresAt ? rule.expiresAt : 0;
    if (expiresAt <= 0)
        return false;
    const now = nowMs === undefined ? Date.now() : nowMs;
    return now > expiresAt;
}

// True when any rule carries an expiry timestamp (expired or not). Gates
// the expiry clock and sweeper so shells without timed rules run no
// periodic work at all; expired-but-unswept rules keep counting so the
// sweeper stays on until they are dropped.
function hasTimedRule(rules) {
    const source = rules || [];
    for (let i = 0; i < source.length; i++) {
        const expiresAt = source[i] && source[i].expiresAt ? source[i].expiresAt : 0;
        if (expiresAt > 0)
            return true;
    }
    return false;
}
