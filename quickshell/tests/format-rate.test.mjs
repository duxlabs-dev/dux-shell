import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const format = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/Format.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), format);

const KB = 1024;
const MB = KB * 1024;
const GB = MB * 1024;

test("compact rates never show bytes or more than three digits", () => {
    const cases = [
        [0, "0 KB/s", "0K"],
        [1, "1 KB/s", "1K"],
        [999.4 * KB, "999 KB/s", "999K"],
        [999.5 * KB, "1 MB/s", "1M"],
        [1000 * GB, "1 TB/s", "1T"]
    ];
    for (const [rate, long, short] of cases) {
        assert.equal(format.formatRateCompact(rate, false), long, `${rate} B/s`);
        assert.equal(format.formatRateCompact(rate, true), short, `${rate} B/s short`);
    }
});
