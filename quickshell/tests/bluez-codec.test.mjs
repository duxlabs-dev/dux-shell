import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const read = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");

// codecNameFromBluez reads BlueZ's Configuration byte array: the first four
// bytes are the vendor id, the next two the vendor codec id, both little endian.
function bluezConfiguration(vendor, codec) {
    const bytes = [];
    for (let i = 0; i < 4; i++)
        bytes.push((vendor >>> (i * 8)) & 0xff);
    bytes.push(codec & 0xff, (codec >>> 8) & 0xff);
    return bytes;
}

const serviceSource = read("Services/BluetoothService.qml");

function methods(names) {
    const bodies = names.map(name => {
        const start = serviceSource.indexOf("    function " + name + "(");
        assert.notEqual(start, -1, "BluetoothService.qml lost " + name);
        const end = serviceSource.indexOf("\n    }", start) + 6;
        return serviceSource.slice(start, end);
    });
    const context = vm.createContext({ I18n: { tr: text => text } });
    vm.runInContext(bodies.join("\n"), context);
    return context;
}

const luaScript = new URL("../scripts/bluez-card-profile.lua", import.meta.url).pathname;

// list mode emits the profile index and the raw description; set mode matches a
// profile by index, by name, or by an untranslated codec literal passed from the
// UI. The script never parses the translated description, so word order and
// punctuation no longer matter.
const deviceDriver = String.raw`
local path = arg[1]
local src = assert(io.open(path)):read("*a")
local region = assert(src:match("(local function profile_available.-\nend\n)\nom:connect"),
  "bluez-card-profile.lua: profile_available/handle_device region moved")

cutils = { parseParam = function(param) return param end }
Pod = { Object = function(table) return table end }
Core = { quit = function() end, sync = function(callback) if callback then callback() end end }
fail = function(message) print("FAIL\t" .. message) end
dev_name = "test-dev"
mode = "list"
target = ""
args = {}
handled = false

local handle_device = assert(load(region .. "\nreturn handle_device", "handle"))()

local function device_with(profiles, active, name)
  return {
    properties = { ["device.name"] = name or "test-dev" },
    iterate_params = function(self, kind)
      local list = profiles
      if kind == "Profile" then
        list = active and { { index = active } } or {}
      end
      local i = 0
      return function()
        i = i + 1
        return list[i]
      end
    end,
    set_param = function(self, kind, param)
      print(string.format("SET\t%s\t%s", kind, tostring(param.index)))
    end,
  }
end

local function run_list(label, profiles, active)
  mode = "list"
  handled = false
  target = ""
  args = {}
  print("CASE\t" .. label)
  handle_device(device_with(profiles, active))
  print("HANDLED\t" .. tostring(handled))
end

local function run_set(label, requested, requested_index, requested_codec, profiles)
  mode = "set"
  handled = false
  target = requested
  args = { index = requested_index, codec = requested_codec }
  print("CASE\t" .. label)
  handle_device(device_with(profiles))
  print("HANDLED\t" .. tostring(handled))
end

run_list("list", {
  { name = "a2dp-sink", description = "高保真回放 (A2DP 信宿, 编码 LHDC v5)", index = 3 },
  { name = "a2dp-sink-sbc", description = "High Fidelity Playback (A2DP Sink, codec SBC)", index = 1 },
  { name = "off", description = "关", index = 0 },
}, 3)

run_set("set-index", "a2dp-sink", 5, "", {
  { name = "a2dp-sink", description = "高保真回放 (A2DP 信宿, 编码 LHDC v5)", index = 5 },
})
run_set("set-name", "a2dp-sink-sbc_xq", nil, "", {
  { name = "a2dp-sink-sbc_xq", description = "High Fidelity Playback (A2DP Sink, codec SBC-XQ)", index = 4 },
})
run_set("set-codec-fi", "", nil, "LHDC v5", {
  { name = "a2dp-sink", description = "Korkealaatuinen toisto (A2DP-kohde, LHDC v5-koodekki)", index = 7 },
})
run_set("set-codec-bg", "", nil, "LHDC v5", {
  { name = "a2dp-sink", description = "Изпълнение с висока точност (елемент-приемник A2DP, кодер „LHDC v5“)", index = 9 },
})
run_set("set-no-match", "", nil, "aptX", {
  { name = "a2dp-sink-sbc", description = "High Fidelity Playback (A2DP Sink, codec SBC)", index = 1 },
})
run_set("set-name-over-index", "a2dp-sink-sbc_xq", 1, "", {
  { name = "a2dp-sink-sbc", description = "High Fidelity Playback (A2DP Sink, codec SBC)", index = 1 },
  { name = "a2dp-sink-sbc_xq", description = "High Fidelity Playback (A2DP Sink, codec SBC-XQ)", index = 2 },
})
`;

function parseDeviceOutput(output) {
    const cases = {};
    let current = null;
    for (const line of output.split("\n")) {
        const columns = line.split("\t");
        if (columns[0] === "CASE") {
            current = cases[columns[1]] = { codecs: [], set: null, ok: null, fail: null, handled: null };
        } else if (!current) {
            continue;
        } else if (columns[0] === "CODEC") {
            current.codecs.push(columns.slice(1));
        } else if (columns[0] === "SET") {
            current.set = columns[1] + ":" + columns[2];
        } else if (columns[0] === "OK") {
            current.ok = columns[1];
        } else if (columns[0] === "FAIL") {
            current.fail = columns[1];
        } else if (columns[0] === "HANDLED") {
            current.handled = columns[1] === "true";
        }
    }
    return cases;
}

test("list mode reports every available profile by index and raw description", () => {
    const output = execFileSync("lua", ["-", luaScript], { input: deviceDriver, encoding: "utf8" });
    const cases = parseDeviceOutput(output);
    assert.deepEqual(cases.list.codecs, [
        ["3", "a2dp-sink", "高保真回放 (A2DP 信宿, 编码 LHDC v5)", "1"],
        ["1", "a2dp-sink-sbc", "High Fidelity Playback (A2DP Sink, codec SBC)", "0"],
        ["0", "off", "关", "0"],
    ]);
});

test("set mode matches a profile by index, name or untranslated codec literal", () => {
    const output = execFileSync("lua", ["-", luaScript], { input: deviceDriver, encoding: "utf8" });
    const cases = parseDeviceOutput(output);
    assert.deepEqual(cases["set-index"], { codecs: [], set: "Profile:5", ok: "a2dp-sink", fail: null, handled: true });
    assert.deepEqual(cases["set-name"], { codecs: [], set: "Profile:4", ok: "a2dp-sink-sbc_xq", fail: null, handled: true });
    assert.deepEqual(cases["set-codec-fi"], { codecs: [], set: "Profile:7", ok: "a2dp-sink", fail: null, handled: true });
    assert.deepEqual(cases["set-codec-bg"], { codecs: [], set: "Profile:9", ok: "a2dp-sink", fail: null, handled: true });
    assert.deepEqual(cases["set-no-match"], { codecs: [], set: null, ok: null, fail: "profile not found: aptX", handled: true });
    assert.deepEqual(cases["set-name-over-index"], { codecs: [], set: "Profile:2", ok: "a2dp-sink-sbc_xq", fail: null, handled: true });
});

test("a codec is identified from its description in any locale", () => {
    const context = methods(["codecMap", "codecAliases", "codecInfoFromDescription", "getCodecInfo"]);
    const info = description => context.codecInfoFromDescription(description);
    assert.equal(info("高保真回放 (A2DP 信宿, 编码 LHDC v5)").name, "LHDC v5");
    assert.equal(info("Korkealaatuinen toisto (A2DP-kohde, LHDC v5-koodekki)").name, "LHDC v5");
    assert.equal(info("Magas hűségű lejátszás (A2DP fogadó, LHDC v5 kodek)").name, "LHDC v5");
    assert.equal(info("Изпълнение с висока точност (елемент-приемник A2DP, кодер „LHDC v5“)").name, "LHDC v5");
    assert.equal(info("မိုက်ပါနားကြပ်ခေါင်းယူနစ် (HSP/HFP၊ codec LHDC v5)").name, "LHDC v5");
    assert.equal(info("High Fidelity Playback (A2DP Sink, codec SBC-XQ)").name, "SBC-XQ");
    assert.equal(info("High Fidelity Playback (A2DP Sink, codec SBC)").name, "SBC");
    assert.equal(info("Playback (A2DP Sink, codec aptX-LL)").name, "aptX LL");
    // The exact PipeWire name wins over a shorter one inside it.
    assert.equal(info("High Fidelity Playback (A2DP Sink, codec LC3plus HR)").name, "LC3plus HR");
    assert.equal(info("Playback (A2DP Sink, codec aptX-LL mSBC)").name, "aptX LL");
    assert.equal(info("Headset (HSP/HFP, codec MSBC)").name, "mSBC");
    assert.equal(info("关"), null);
    assert.equal(info("Auto: Prefer Quality (A2DP)"), null);
});

test("a CODEC line carries the profile index and the codec read from the description", () => {
    const context = methods(["codecMap", "codecAliases", "codecInfoFromDescription", "codecLabelFromProfile", "getCodecInfo", "parseCodecLine"]);
    const entry = context.parseCodecLine("CODEC\t3\ta2dp-sink\t高保真回放 (A2DP 信宿, 编码 LHDC v5)\t1");
    assert.equal(entry.name, "LHDC v5");
    assert.equal(entry.profile, "a2dp-sink");
    assert.equal(entry.index, 3);
    assert.equal(entry.codec, "LHDC v5");
    assert.equal(entry.current, true);
    assert.equal(context.parseCodecLine("CODEC\t0\toff\t关\t0"), null);
    assert.equal(context.parseCodecLine("OK\ta2dp-sink"), null);
    // A codec outside the vocabulary stays selectable under its profile name.
    const unknown = context.parseCodecLine("CODEC\t9\ta2dp-sink-brandnew_x\tHigh Fidelity Playback (A2DP Sink, codec BrandNew X)\t0");
    assert.equal(unknown.name, "BRANDNEW_X");
    assert.equal(unknown.codec, "");
    assert.equal(unknown.description, "Unknown codec");
    const bareUnknown = context.parseCodecLine("CODEC\t3\ta2dp-sink\t高保真回放 (A2DP 信宿, 编码 未知编解码器)\t1");
    assert.equal(bareUnknown.name, "Unknown");
    assert.equal(bareUnknown.profile, "a2dp-sink");
    assert.equal(bareUnknown.codec, "");
    assert.equal(bareUnknown.current, true);
    assert.equal(bareUnknown.unknown, true);
    assert.equal(entry.unknown, false);
    const headsetUnknown = context.parseCodecLine("CODEC\t4\theadset-head-unit\tHeadset (HSP/HFP)\t0");
    assert.equal(headsetUnknown.name, "Unknown");
    assert.equal(headsetUnknown.profile, "headset-head-unit");
});

test("an active unknown profile cannot claim a codec name before BlueZ lookup", () => {
    const context = methods(["codecMap", "codecAliases", "codecInfoFromDescription", "codecLabelFromProfile", "getCodecInfo", "parseCodecLine", "codecCategory"]);
    const process = serviceSource.split("        id: codecListProcess")[1].split("    Process {")[0];
    const handlerSource = process.match(/onRead: (data => \{[\s\S]*?\n            \})\n        \}\n\n        onExited/)?.[1];
    assert.ok(handlerSource, "codecListProcess onRead handler moved");
    const state = { detectedCodec: "", currentIndex: -1, availableCodecs: [] };
    context.root = context;
    context.codecListProcess = state;
    const onRead = vm.runInContext(handlerSource, context);
    onRead("CODEC\t3\ta2dp-sink\t高保真回放 (A2DP 信宿, 编码 未知编解码器)\t1");
    assert.equal(state.detectedCodec, "");
    assert.equal(state.currentIndex, 3);
    assert.equal(state.availableCodecs[0].name, "Unknown");
    assert.equal(state.availableCodecs[0].profile, "a2dp-sink");
    onRead("CODEC\t4\theadset-head-unit\tHeadset (HSP/HFP)\t0");
    assert.equal(state.availableCodecs[1].name, "Unknown");
    assert.notEqual(state.availableCodecs[0].index, state.availableCodecs[1].index);
    const exitSource = process.match(/onExited: (function \(exitCode\) \{[\s\S]*?\n        \})\n    \}/)?.[1];
    assert.ok(exitSource, "codecListProcess onExited handler moved");
    state.callback = (codecs, current, currentIndex) => {
        assert.equal(codecs.length, 2);
        assert.equal(current, "");
        assert.equal(currentIndex, 3);
    };
    Object.assign(context, state);
    vm.runInContext(`(${exitSource})`, context)(0);
    assert.equal(context.currentIndex, -1);
});

test("an unknown active PipeWire profile preserves choices but defers current codec to BlueZ", () => {
    const context = methods(["refreshDeviceCodec", "getAvailableCodecs", "invalidateCodecQuery", "codecQueryIsCurrent"]);
    const device = { connected: true, address: "AA:BB" };
    const pipewire = [{ name: "Unknown", profile: "a2dp-sink", index: 3 }];
    const bluez = [{ name: "LHDC v5" }];
    let bluezQueries = 0;
    const updates = [];
    context.isAudioDevice = () => true;
    context.whenCodecBackendReady = callback => callback();
    context.root = {
        invalidateCodecQuery: context.invalidateCodecQuery,
        codecQueryIsCurrent: context.codecQueryIsCurrent,
        codecQueryVersions: {},
        adapter: { devices: { values: [device] } },
        wpexecAvailable: true,
        dbusBridgeAvailable: true,
        queryCardProfiles: (_device, callback) => callback(pipewire, "", 3),
        queryBluezCodecState: (_device, callback) => { bluezQueries++; callback(bluez, "LHDC v5"); },
        updateDeviceCodec: (_address, name) => updates.push(name)
    };
    context.refreshDeviceCodec(device);
    assert.deepEqual(updates, ["LHDC v5"]);
    context.getAvailableCodecs(device, (codecs, current, currentIndex) => {
        assert.equal(codecs, pipewire);
        assert.equal(current, "LHDC v5");
        assert.equal(currentIndex, 3);
    });
    assert.equal(bluezQueries, 2);

    context.root.queryBluezCodecState = (_device, callback) => callback([], "");
    context.refreshDeviceCodec(device);
    assert.deepEqual(updates, ["LHDC v5", "Unknown"]);
    context.getAvailableCodecs(device, (codecs, current, currentIndex) => {
        assert.equal(codecs, pipewire);
        assert.equal(current, "Unknown");
        assert.equal(currentIndex, 3);
    });
    context.root.queryBluezCodecState = (_device, callback) => callback([], "VENDOR");
    context.refreshDeviceCodec(device);
    assert.equal(updates.at(-1), "Unknown");
    context.getAvailableCodecs(device, (codecs, current) => {
        assert.equal(codecs, pipewire);
        assert.equal(current, "Unknown");
    });
    context.root.dbusBridgeAvailable = false;
    context.getAvailableCodecs(device, (codecs, current) => {
        assert.equal(codecs, pipewire);
        assert.equal(current, "Unknown");
    });
});

test("a late BlueZ lookup cannot undo a successful codec switch", () => {
    const context = methods(["refreshDeviceCodec", "invalidateCodecQuery", "updateDeviceCodec", "codecQueryIsCurrent"]);
    const device = { connected: true, address: "AA:BB" };
    const updates = [];
    let reply;
    context.isAudioDevice = () => true;
    context.whenCodecBackendReady = callback => callback();
    context.root = context;
    context.wpexecAvailable = true;
    context.dbusBridgeAvailable = true;
    context.adapter = { devices: { values: [device] } };
    context.codecQueryVersions = {};
    context.deviceCodecs = {};
    context.queryCardProfiles = (_device, callback) => callback([], "", 3);
    context.queryBluezCodecState = (_device, callback) => { reply = callback; };
    context.updateDeviceCodec = (_address, name) => updates.push(name);

    context.refreshDeviceCodec(device);
    assert.equal(typeof reply, "function");
    // The selector invalidates its pending lookup when switching starts.
    context.invalidateCodecQuery(device.address);
    context.updateDeviceCodec(device.address, "AAC");
    reply([], "LDAC");
    assert.deepEqual(updates, ["AAC"]);
});

test("only the newest refresh for a device can publish a codec", () => {
    const context = methods(["refreshDeviceCodec", "invalidateCodecQuery", "codecQueryIsCurrent"]);
    const device = { connected: true, address: "AA:BB" };
    const other = { connected: true, address: "CC:DD" };
    const replies = new Map();
    const updates = [];
    context.isAudioDevice = () => true;
    context.whenCodecBackendReady = callback => callback();
    context.root = context;
    context.wpexecAvailable = true;
    context.dbusBridgeAvailable = true;
    context.adapter = { devices: { values: [device, other] } };
    context.codecQueryVersions = {};
    context.queryCardProfiles = (_device, callback) => callback([], "", 3);
    context.queryBluezCodecState = (target, callback) => {
        const callbacks = replies.get(target.address) || [];
        callbacks.push(callback);
        replies.set(target.address, callbacks);
    };
    context.updateDeviceCodec = (address, name) => updates.push([address, name]);

    context.refreshDeviceCodec(device);
    context.refreshDeviceCodec(other);
    context.refreshDeviceCodec(device);
    replies.get(device.address)[0]([], "LDAC");
    replies.get(other.address)[0]([], "SBC");
    replies.get(device.address)[1]([], "AAC");
    assert.deepEqual(updates, [["CC:DD", "SBC"], ["AA:BB", "AAC"]]);
});

test("a replaced adapter cannot receive a late BlueZ codec", () => {
    const context = methods(["refreshDeviceCodec", "invalidateCodecQuery", "codecQueryIsCurrent"]);
    const device = { connected: true, address: "AA:BB" };
    const updates = [];
    let reply;
    context.isAudioDevice = () => true;
    context.whenCodecBackendReady = callback => callback();
    context.root = context;
    context.wpexecAvailable = true;
    context.dbusBridgeAvailable = true;
    context.adapter = { dbusPath: "/adapter/old", devices: { values: [device] } };
    context.codecQueryVersions = {};
    context.queryCardProfiles = (_device, callback) => callback([], "", 3);
    context.queryBluezCodecState = (_device, callback) => { reply = callback; };
    context.updateDeviceCodec = (_address, name) => updates.push(name);

    context.refreshDeviceCodec(device);
    context.adapter = { dbusPath: "/adapter/new", devices: { values: [device] } };
    reply([], "LDAC");
    assert.deepEqual(updates, []);
});

test("a disconnected device cannot receive a late BlueZ codec", () => {
    const context = methods(["refreshDeviceCodec", "invalidateCodecQuery", "codecQueryIsCurrent"]);
    const device = { connected: true, address: "AA:BB" };
    let reply;
    const updates = [];
    context.isAudioDevice = () => true;
    context.whenCodecBackendReady = callback => callback();
    context.root = context;
    context.wpexecAvailable = true;
    context.dbusBridgeAvailable = true;
    context.adapter = { devices: { values: [device] } };
    context.codecQueryVersions = {};
    context.queryCardProfiles = (_device, callback) => callback([], "", 3);
    context.queryBluezCodecState = (_device, callback) => { reply = callback; };
    context.updateDeviceCodec = (_address, name) => updates.push(name);

    context.refreshDeviceCodec(device);
    device.connected = false;
    reply([], "LDAC");
    assert.deepEqual(updates, []);
});

test("known PipeWire codec does not query BlueZ again", () => {
    const context = methods(["refreshDeviceCodec", "getAvailableCodecs", "invalidateCodecQuery", "codecQueryIsCurrent"]);
    const device = { connected: true, address: "AA:BB" };
    const pipewire = [{ name: "LHDC v5", index: 3 }];
    const updates = [];
    context.isAudioDevice = () => true;
    context.whenCodecBackendReady = callback => callback();
    context.root = {
        invalidateCodecQuery: context.invalidateCodecQuery,
        codecQueryIsCurrent: context.codecQueryIsCurrent,
        codecQueryVersions: {},
        adapter: { devices: { values: [device] } },
        wpexecAvailable: true, dbusBridgeAvailable: true,
        queryCardProfiles: (_device, callback) => callback(pipewire, "LHDC v5", 3),
        queryBluezCodecState: () => assert.fail("known current codec should not query BlueZ"),
        updateDeviceCodec: (_address, name) => updates.push(name)
    };
    context.refreshDeviceCodec(device);
    assert.deepEqual(updates, ["LHDC v5"]);
    context.getAvailableCodecs(device, (codecs, current) => {
        assert.equal(codecs, pipewire);
        assert.equal(current, "LHDC v5");
    });
});

test("vendor codecs are read from the BlueZ configuration bytes", () => {
    const context = methods(["bytesFromDbusValue", "codecNameFromBluez"]);
    const nameOf = (vendor, codec) => context.codecNameFromBluez(0xff, bluezConfiguration(vendor, codec));
    assert.equal(nameOf(0x0000004f, 0x0001), "APTX");
    assert.equal(nameOf(0x000000d7, 0x0024), "APTX_HD");
    assert.equal(nameOf(0x0000012d, 0x00aa), "LDAC");
    assert.equal(nameOf(0x0000053a, 0x4c35), "LHDC_V5");
    assert.equal(nameOf(0x0000053a, 0x4c33), "LHDC_V3");
    assert.equal(nameOf(0x0000ffff, 0x1234), "VENDOR");
    assert.equal(context.codecNameFromBluez(0x00, []), "SBC");
    assert.equal(context.codecNameFromBluez(0x02, []), "AAC");
    assert.equal(context.codecNameFromBluez(0x04, []), "ATRAC");
    assert.equal(context.codecNameFromBluez(0x03, []), "");
    assert.equal(context.codecNameFromBluez(0xff, [0x3a, 0x05]), "VENDOR");
    assert.equal(context.codecNameFromBluez(0xff, []), "VENDOR");
});

test("LHDC codecs carry a name, description and category", () => {
    const context = methods(["codecMap", "getCodecInfo", "codecCategory", "codecNameFromProfile"]);
    const v5 = context.getCodecInfo("LHDC_V5");
    assert.equal(v5.name, "LHDC v5");
    assert.notEqual(v5.description, "Unknown codec");
    assert.equal(context.getCodecInfo("lhdc-v5").name, "LHDC v5");
    assert.equal(context.getCodecInfo("LHDC_V3").name, "LHDC v3");
    assert.equal(context.codecCategory(v5.name, "a2dp-sink"), "media");
    assert.equal(context.codecCategory(v5.name, "headset-head-unit"), "call");
    assert.equal(context.codecNameFromProfile("a2dp-sink"), "");
    assert.equal(context.codecNameFromProfile("a2dp-sink-aac"), "AAC");
});

// BlueZ Alias falls back to the dashed address when a device sends no name.
test("scan list sorts named devices above alias-is-address devices", () => {
    const context = methods(["hasRealName", "sortDevices"]);
    const sorted = context.sortDevices([
        { name: "23-5F-24-05-F3-4A", address: "23:5F:24:05:F3:4A" },
        { name: "ATH-M20xBT", address: "AA:BB:CC:DD:EE:FF" },
        { name: "", deviceName: "", address: "01:02:03:04:05:06" }
    ]);
    assert.deepEqual(sorted.map(d => d.address), ["AA:BB:CC:DD:EE:FF", "01:02:03:04:05:06", "23:5F:24:05:F3:4A"]);
});
