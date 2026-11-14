import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const formats = loadScript(new URL("../Common/WallpaperFormats.js", import.meta.url));

test("isVideo reads the file extension only", () => {
    const cases = [["/home/me/Videos/rain.MP4", true], ["file:///home/me/a b/loop.mkv", true], ["/home/me/sea.png", false], ["/home/me/movie.mp4.d/still", false], ["/home/me/noext", false], ["#1e1e2e", false], ["", false]];
    for (const [path, expected] of cases)
        assert.equal(formats.isVideo(path), expected, path);
});
