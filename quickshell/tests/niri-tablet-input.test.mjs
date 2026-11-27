import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import { loadScript } from './qml-script.mjs';

const spec = loadScript(new URL('../Common/settings/SettingsSpec.js', import.meta.url)).SPEC;
const defaults = Object.fromEntries(Object.entries(spec).map(([key, entry]) => [key, entry.def]));
const source = readFileSync(new URL('../Services/NiriService.qml', import.meta.url), 'utf8');
const fn = source.match(/    function generateNiriInputConfig\(\)[^]*?(?=\n    function )/);
assert.ok(fn, 'generateNiriInputConfig exists');

function tabletSection(settings, configNextSupported) {
    const context = vm.createContext({
        CompositorService: { isNiri: true },
        SettingsData: { ...defaults, ...settings },
        Paths: { strip: p => p },
        StandardPaths: { writableLocation: () => '/cfg', ConfigLocation: 0 },
        writeInputProcess: {},
        replaceFileCommand: () => '',
        configNextSupported
    });
    vm.runInContext(fn[0], context);
    vm.runInContext('generateNiriInputConfig()', context);
    return context.writeInputProcess.inputContent.match(/ {4}tablet \{\n[^]*?\n {4}\}\n/)?.[0] ?? null;
}

test('tablet section holds every set option and is left out when none applies', () => {
    const cases = [
        [{}, true, null],
        [{ niriTabletMapToFocusedWindow: true }, false, null],
        [{ niriTabletMapToOutput: 'eDP-1', niriTabletMapToFocusedWindow: true, niriTabletLeftHanded: true }, true, '    tablet {\n        map-to-output "eDP-1"\n        map-to-focused-window\n        left-handed\n    }\n'],
        [{ niriTabletMapToFocusedWindow: true, niriTabletLeftHanded: true }, false, '    tablet {\n        left-handed\n    }\n']
    ];
    for (const [settings, configNext, expected] of cases)
        assert.equal(tabletSection(settings, configNext), expected, JSON.stringify(settings));
});
