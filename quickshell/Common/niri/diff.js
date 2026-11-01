.pragma library

// Longest common subsequence over lines; the custom KDL text stays small, so O(n*m) is fine.
function lineDiff(before, after, context) {
    const a = lines(before);
    const b = lines(after);
    const m = a.length;
    const n = b.length;
    const d = [];
    for (let i = 0; i <= m; i++)
        d.push(new Array(n + 1).fill(0));
    for (let i = m - 1; i >= 0; i--) {
        for (let j = n - 1; j >= 0; j--)
            d[i][j] = a[i] === b[j] ? d[i + 1][j + 1] + 1 : Math.max(d[i + 1][j], d[i][j + 1]);
    }
    const ops = [];
    let i = 0;
    let j = 0;
    while (i < m || j < n) {
        if (i < m && j < n && a[i] === b[j]) {
            ops.push({ kind: "same", text: a[i] });
            i++;
            j++;
        } else if (j >= n || (i < m && d[i + 1][j] >= d[i][j + 1])) {
            ops.push({ kind: "del", text: a[i++] });
        } else {
            ops.push({ kind: "add", text: b[j++] });
        }
    }
    return ops.filter((op, k) => ops.slice(Math.max(0, k - context), k + context + 1).some(near => near.kind !== "same"));
}

function lines(text) {
    if (!text)
        return [];
    const out = text.split("\n");
    if (out[out.length - 1] === "")
        out.pop();
    return out;
}
