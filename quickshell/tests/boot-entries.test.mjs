import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const bootEntries = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Services/BootEntries.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), bootEntries);
const plain = value => JSON.parse(JSON.stringify(value));

test("parses active and inactive entries and the current boot from efibootmgr output", () => {
    // efibootmgr 18 prints the device path after a tab, older releases print only the label.
    // Inactive entries have no "*" and stay listed, since BootNext still boots them.
    const output = [
        "BootCurrent: 0001",
        "Timeout: 1 seconds",
        "BootOrder: 0001,0000,0010",
        "Boot0000* Windows Boot Manager\tHD(1,GPT,c28482eb,0x1000,0x830000)/\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW.EFI",
        "Boot0001* Limine\tHD(1,GPT,c28482eb,0x1000,0x830000)/\\EFI\\LIMINE\\LIMINE_X64.EFI",
        "Boot0010  UEFI OS\tHD(1,GPT,c28482eb,0x1000,0x830000)/\\EFI\\BOOT\\BOOTX64.EFI",
        "Boot001a* Fedora",
        "Boot001B  Ubuntu",
        ""
    ].join("\n");

    const parsed = bootEntries.parseEntries(output);

    assert.equal(parsed.currentId, "0001");
    assert.deepEqual(plain(parsed.entries), [
        { id: "0000", label: "Windows Boot Manager" },
        { id: "0001", label: "Limine" },
        { id: "0010", label: "UEFI OS" },
        { id: "001A", label: "Fedora" },
        { id: "001B", label: "Ubuntu" }
    ]);
});

test("picker skips the running and saved entries and tells duplicate labels apart", () => {
    const entries = [
        { id: "0000", label: "Windows Boot Manager" },
        { id: "0001", label: "Limine" },
        { id: "0002", label: "Fedora" },
        { id: "0003", label: "Fedora" },
        { id: "0004", label: "Arch" },
        { id: "0005", label: "Arch" }
    ];
    const saved = [{ id: "0000", label: "Windows Boot Manager" }, { id: "0004", label: "Arch" }];

    assert.deepEqual(plain(bootEntries.pickerOptions(entries, "0001", saved)), [
        { id: "0002", label: "Fedora", name: "Fedora (0002)" },
        { id: "0003", label: "Fedora", name: "Fedora (0003)" },
        // Its twin is already saved, so the label alone is unambiguous in the picker
        { id: "0005", label: "Arch", name: "Arch" }
    ]);
});
