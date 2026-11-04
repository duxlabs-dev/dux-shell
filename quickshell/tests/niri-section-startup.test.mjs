import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Startup = loadScript(new URL("../Common/niri/sections/startup.js", import.meta.url));
const { assemble } = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));

const kdl = state => assemble([{ id: "startup", toKdl: Startup.toKdl }], { ...Startup.defaults, ...state });

test("writes no environment block by default", () => {
    assert.equal(kdl({}), "");
});

test("writes each variable quoted, and drops names niri would read as something else", () => {
    const env = { QT_QPA_PLATFORM: "wayland", "BAD NAME": "x", "X\"}": "y", PATH_EXTRA: "a \"b\"" };
    assert.equal(kdl({ "startup.env": env }), [
        "environment {",
        "    QT_QPA_PLATFORM \"wayland\"",
        "    PATH_EXTRA \"a \\\"b\\\"\"",
        "}",
        ""
    ].join("\n"));
});

test("reads NAME=value typed by the user", () => {
    assert.deepEqual({ ...Startup.parseEnv(" ELECTRON_OZONE_PLATFORM_HINT=auto") }, { name: "ELECTRON_OZONE_PLATFORM_HINT", value: "auto" });
    assert.deepEqual({ ...Startup.parseEnv("A=b=c") }, { name: "A", value: "b=c" });
    assert.deepEqual({ ...Startup.parseEnv("EMPTY=") }, { name: "EMPTY", value: "" });
    assert.equal(Startup.parseEnv("=x"), null);
    assert.equal(Startup.parseEnv("1BAD=x"), null);
    assert.equal(Startup.parseEnv("novalue"), null);
});
