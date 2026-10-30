import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const formats = loadScript(new URL("../Common/WallpaperFormats.js", import.meta.url));

test("isVideo reads the file extension only", () => {
    const cases = [["/home/me/Videos/rain.MP4", true], ["/home/me/clip.webm", true], ["file:///home/me/a b/loop.mkv", true], ["/home/me/sea.png", false], ["/home/me/movie.mp4.d/still", false], ["/home/me/noext", false], ["#1e1e2e", false], ["", false]];
    for (const [path, expected] of cases)
        assert.equal(formats.isVideo(path), expected, path);
});

test("findPredicate selects wallpapers case-insensitively and nothing else", () => {
    const dir = mkdtempSync(join(tmpdir(), "wallpaper-formats-"));
    try {
        for (const name of ["a.MP4", "b.png", "c.txt", "d.Webm", "e.svg"])
            writeFileSync(join(dir, name), "");
        const find = withVideo => execFileSync("sh", ["-c", `find "$1" -type f ${formats.findPredicate(withVideo)} | sort`, "sh", dir], { encoding: "utf8" }).trim().split("\n").map(path => path.slice(dir.length + 1));
        assert.deepEqual(find(true), ["a.MP4", "b.png", "d.Webm", "e.svg"]);
        assert.deepEqual(find(false), ["b.png", "e.svg"]);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});
