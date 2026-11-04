import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const { spawnLines } = loadScript(new URL("../Common/niri/kdlspawn.js", import.meta.url));

const lines = text => Array.from(spawnLines(text));

test("finds every spawn node, top level or in a bind", () => {
    assert.deepEqual(lines('spawn-at-startup "waybar"'), [1]);
    assert.deepEqual(lines('spawn-sh-at-startup "a && b"'), [1]);
    assert.deepEqual(lines('binds {\n    Mod+T { spawn "alacritty"; }\n    Mod+D { spawn-sh "fuzzel | sh"; }\n}'), [2, 3]);
    assert.deepEqual(lines('binds { Mod+T hotkey-overlay-title="T" { focus-column-left; spawn "x"; }; }'), [1]);
    assert.deepEqual(lines('(t)spawn "x"'), [1]);
});

test("a quoted or escaped node name is still a spawn", () => {
    assert.deepEqual(lines('"spawn" "x"'), [1]);
    assert.deepEqual(lines('Mod+T { "sp\\u{61}wn-sh" "x"; }'), [1]);
});

test("ignores spawn in comments, strings, arguments and other names", () => {
    const quiet = [
        '// spawn "x"',
        '/* spawn "x"\n /* nested */ spawn "y" */ layout { gaps 8; }',
        '/-spawn "x"',
        '/-binds {\n    Mod+T { spawn "x"; }\n}',
        'window-rule { match title="spawn"; }',
        'window-rule { match app-id=r#"spawn "x""#; }',
        'window-rule { match app-id=#"spawn "x""#; }',
        'screenshot-path "~/spawn \\"x\\""',
        'output "spawn" { scale 1; }',
        'spawner "x"\nspawn-shell "x"\nmy-spawn "x"',
        'environment { SPAWN "1"; }',
        ''
    ];
    for (const text of quiet)
        assert.deepEqual(lines(text), [], text);
});

test("a comment closing on a line does not hide the next node", () => {
    assert.deepEqual(lines('/* note */ spawn "x"'), [1]);
    assert.deepEqual(lines('layout { gaps 8; } // spawn\nspawn "x"'), [2]);
    assert.deepEqual(lines('/-layout { gaps 8; }\nspawn "x"'), [2]);
    assert.deepEqual(lines('prefer-no-csd; spawn "x"'), [1]);
    assert.deepEqual(lines('prefer-no-csd spawn "x"'), [1]);
    assert.deepEqual(lines('prefer-no-csd\u0085spawn "x"'), [1]);
    assert.deepEqual(lines('prefer-no-csd \\\n  "a"\nspawn "x"'), [3]);
});

test("a quoted or raw type annotation holding a ) does not hide the next node", () => {
    assert.deepEqual(lines('/-x (")")"y"\nspawn-at-startup "true"'), [2]);
    assert.deepEqual(lines('/-x (")")"y"\nspawn-at-startup "true"\n/-z "\n'), [2]);
    assert.deepEqual(lines('/-x (r")")"y"\nspawn-at-startup "true"'), [2]);
    assert.deepEqual(lines('/-x (#")"#)"y"\nspawn-at-startup "true"'), [2]);
    assert.deepEqual(lines('binds {\n    /-Mod+Z (")")"y" { spawn "true"; }\n    Mod+Y { spawn "true"; }\n}'), [3]);
    assert.deepEqual(lines('(")")spawn-at-startup "true"'), [1]);
    assert.deepEqual(lines('(t)spawn-at-startup "true"'), [1]);
});

test("an unclosed string or comment reports nothing past it", () => {
    assert.deepEqual(lines('screenshot-path "~/x\nspawn "y"'), []);
    assert.deepEqual(lines('/* open\nspawn "y"'), []);
});
