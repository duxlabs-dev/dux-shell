import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

function functionSource(file, name) {
    const source = readFileSync(new URL(file, import.meta.url), "utf8");
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\)(?:: \\w+)? \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in ${file}`);
    return found[0];
}

const context = vm.createContext({});
for (const name of ["parseCards", "collectDisabledOutputCards"])
    vm.runInContext(functionSource("../Services/AudioService.qml", name), context);

function card(name, activeProfile, profiles) {
    return [
        "Card #1",
        `\tName: ${name}`,
        "\tProperties:",
        `\t\tdevice.description = "${name}"`,
        "\tProfiles:",
        ...profiles.map(line => `\t\t${line}`),
        `\tActive Profile: ${activeProfile}`,
        "\tPorts:"
    ].join("\n");
}

const off = "off: Off (sinks: 0, sources: 0, priority: 0, available: yes)";

test("off cards re-enable on their best sink profile whatever its name, other cards are not disabled", () => {
    const output = [
        card("alsa_card.usb-Headset-00", "off", [
            off,
            "output:analog-stereo+input:mono-fallback: Analog Stereo Output + Mono Input (sinks: 1, sources: 1, priority: 6501, available: yes)",
            "output:analog-stereo: Analog Stereo Output (sinks: 1, sources: 0, priority: 6500, available: yes)",
            "input:mono-fallback: Mono Input (sinks: 0, sources: 1, priority: 1, available: yes)"
        ]),
        // Nothing plugged in: every analog profile is unavailable and only pro-audio is left
        card("alsa_card.pci-0000_0f_00.6", "off", [
            off,
            "output:analog-stereo+input:analog-stereo: Analog Stereo Duplex (sinks: 1, sources: 1, priority: 6565, available: no)",
            "input:analog-stereo: Analog Stereo Input (sinks: 0, sources: 1, priority: 65, available: no)",
            "pro-audio: Pro Audio (sinks: 1, sources: 2, priority: 1, available: yes)"
        ]),
        card("alsa_card.pci-0000_00_1f.3-platform-skl_hda_dsp_generic", "off", [
            "HiFi (HDMI1, Headphones, Mic1, Speaker): Play HiFi quality Music (sinks: 2, sources: 1, priority: 8200, available: yes)",
            "HiFi (HDMI1, Mic1, Speaker): Play HiFi quality Music (sinks: 2, sources: 1, priority: 8100, available: yes)",
            off
        ]),
        card("bluez_card.AA_BB_CC_DD_EE_FF", "off", [
            off,
            "a2dp-sink-sbc: High Fidelity Playback (A2DP Sink, codec SBC) (sinks: 1, sources: 0, priority: 18, available: yes)",
            "a2dp-sink: High Fidelity Playback (A2DP Sink, codec AAC) (sinks: 1, sources: 0, priority: 21, available: yes)",
            "headset-head-unit: Headset Head Unit (HSP/HFP, codec mSBC) (sinks: 1, sources: 1, priority: 2, available: yes)"
        ]),
        card("alsa_card.usb-Webcam-00", "input:mono-fallback", [
            "input:mono-fallback: Mono Input (sinks: 0, sources: 1, priority: 1, available: yes)",
            off
        ]),
        card("alsa_card.pci-0000_03_00.1", "output:hdmi-stereo", [
            "output:hdmi-stereo: Digital Stereo (HDMI) Output (sinks: 1, sources: 0, priority: 5900, available: yes)",
            off
        ])
    ].join("\n\n");

    const disabled = JSON.parse(JSON.stringify(context.collectDisabledOutputCards(context.parseCards(output)).map(entry => [entry.cardName, entry.profile])));

    assert.deepEqual(disabled, [
        ["alsa_card.usb-Headset-00", "output:analog-stereo+input:mono-fallback"],
        ["alsa_card.pci-0000_00_1f.3-platform-skl_hda_dsp_generic", "HiFi (HDMI1, Headphones, Mic1, Speaker)"],
        ["bluez_card.AA_BB_CC_DD_EE_FF", "a2dp-sink"]
    ]);
});
