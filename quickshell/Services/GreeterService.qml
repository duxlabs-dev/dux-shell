pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Singleton {
    id: root

    property bool available: false
    property bool binaryExists: false
    property bool configured: false
    property bool enabled: false
    property bool inGroup: false
    // "live" when the greeter slot symlinks this user's DMS files, "snapshot" for a copied slot, "" when absent
    property string slotState: ""
    property bool syncing: false
    property string syncStatus: ""
    property bool fallbackFromPrecheck: false
    property bool _detected: false

    readonly property bool linked: slotState === "live"
    readonly property bool profileSyncSufficient: configured && inGroup

    signal syncFinished

    function refresh() {
        _detected = true;
        detectProcess.running = true;
    }

    function ensureDetected() {
        if (_detected)
            return;
        refresh();
    }

    function sync() {
        if (!binaryExists || syncing)
            return;
        fallbackFromPrecheck = false;
        syncStatus = I18n.tr("Checking whether sudo authentication is needed...");
        syncing = true;
        sudoProbeProcess.running = true;
    }

    // Links this user's slot without touching system config when the greeter is already installed.
    function link() {
        if (!profileSyncSufficient) {
            sync();
            return;
        }
        if (!binaryExists || syncing)
            return;
        syncStatus = "";
        syncing = true;
        profileSyncProcess.running = true;
    }

    function launchTerminalFallback(fromPrecheck, statusText) {
        fallbackFromPrecheck = fromPrecheck;
        if (statusText)
            syncStatus = statusText;
        terminalFallbackProcess.running = true;
    }

    function unlink() {
        if (!binaryExists || syncing)
            return;
        syncStatus = "";
        syncing = true;
        unlinkProcess.running = true;
    }

    function withOutput(message, out, err) {
        let text = message;
        if (out !== "")
            text += "\n\n" + out;
        if (err !== "")
            text += "\n\nstderr:\n" + err;
        return text;
    }

    function finishSync() {
        syncing = false;
        refresh();
        syncFinished();
    }

    Process {
        id: detectProcess

        command: ["sh", "-c", `command -v dms-greeter >/dev/null 2>&1 && echo binary
grep -qs dms-greeter /etc/greetd/config.toml && echo config
[ "$(systemctl is-enabled greetd 2>/dev/null)" = enabled ] && echo enabled
id -nG | tr ' ' '\n' | grep -qxE 'greeter|greetd|_greeter' && echo group
own=$(readlink -f "$HOME/.config/dms/settings.json")
for f in "/var/cache/dms-greeter/users/$USER/settings.json" /var/cache/dms-greeter/settings.json; do
    [ -L "$f" ] && [ "$(readlink -f "$f")" = "$own" ] && echo live && break
done
[ -f "/var/cache/dms-greeter/users/$USER/settings.json" ] && echo slot
exit 0`]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.split("\n");
                root.binaryExists = found.includes("binary");
                root.configured = found.includes("config");
                root.enabled = found.includes("enabled");
                root.inGroup = found.includes("group");
                root.slotState = found.includes("live") ? "live" : (found.includes("slot") ? "snapshot" : "");
                root.available = root.binaryExists || root.configured;
            }
        }
    }

    Process {
        id: profileSyncProcess

        command: ["dms-greeter", "sync", "--profile", "--yes"]

        stdout: StdioCollector {
            id: profileOut
        }

        stderr: StdioCollector {
            id: profileErr
        }

        onExited: exitCode => {
            const out = profileOut.text.trim();
            const err = profileErr.text.trim();
            if (exitCode !== 0) {
                root.syncStatus = root.withOutput(I18n.tr("Profile sync failed.") + " " + I18n.tr("(exit %1)", "process exit code").arg(exitCode), out, err);
                root.finishSync();
                return;
            }
            root.syncStatus = root.withOutput(I18n.tr("Sync completed successfully."), out, err);
            ToastService.showInfo(I18n.tr("Greeter sync complete"));
            root.finishSync();
        }
    }

    Process {
        id: sudoProbeProcess

        command: ["sudo", "-n", "true"]

        stderr: StdioCollector {
            id: sudoProbeErr
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                root.syncStatus = I18n.tr("Running greeter sync...");
                syncProcess.running = true;
                return;
            }
            let authNeeded = I18n.tr("Sync needs sudo authentication. Opening terminal so you can use password or fingerprint.");
            const err = sudoProbeErr.text.trim();
            if (err !== "")
                authNeeded += "\n\n" + err;
            root.launchTerminalFallback(true, authNeeded);
        }
    }

    Process {
        id: syncProcess

        command: ["dms-greeter", "sync", "--yes"]

        stdout: StdioCollector {
            id: syncOut
        }

        stderr: StdioCollector {
            id: syncErr
        }

        onExited: exitCode => {
            const out = syncOut.text.trim();
            const err = syncErr.text.trim();
            if (exitCode !== 0) {
                root.syncStatus = root.withOutput(I18n.tr("Sync failed in background mode. Trying terminal mode so you can authenticate interactively.") + " " + I18n.tr("(exit %1)", "process exit code").arg(exitCode), out, err);
                root.launchTerminalFallback(false, "");
                return;
            }
            root.syncStatus = root.withOutput(I18n.tr("Sync completed successfully."), out, err);
            SettingsData.clearGreeterSyncPending();
            ToastService.showInfo(I18n.tr("Greeter sync complete"));
            root.finishSync();
        }
    }

    Process {
        id: unlinkProcess

        command: ["dms-greeter", "unlink", "--yes"]

        stdout: StdioCollector {
            id: unlinkOut
        }

        stderr: StdioCollector {
            id: unlinkErr
        }

        onExited: exitCode => {
            const out = unlinkOut.text.trim();
            const err = unlinkErr.text.trim();
            if (exitCode === 0) {
                root.syncStatus = root.withOutput(I18n.tr("Login screen unlinked.", "greeter unlink status"), out, err);
                root.finishSync();
                return;
            }
            root.syncStatus = root.withOutput(I18n.tr("Unlink needs sudo authentication. Opening terminal so you can use password or fingerprint.", "greeter unlink status"), out, err);
            unlinkTerminalProcess.running = true;
        }
    }

    Process {
        id: unlinkTerminalProcess

        command: ["dms-greeter", "unlink", "--terminal", "--yes"]

        onExited: exitCode => {
            if (exitCode !== 0)
                root.syncStatus += "\n\n" + I18n.tr("Terminal fallback failed. Install one of the supported terminal emulators or run '%1' manually.", "terminal fallback status, %1 is a command").arg("dms-greeter unlink") + " " + I18n.tr("(exit %1)", "process exit code").arg(exitCode);
            root.finishSync();
        }
    }

    Process {
        id: terminalFallbackProcess

        command: ["dms-greeter", "sync", "--terminal", "--yes"]

        stderr: StdioCollector {
            id: terminalFallbackErr
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                const launched = root.fallbackFromPrecheck ? I18n.tr("Terminal opened. Complete authentication there; it will close automatically when done.") : I18n.tr("Terminal fallback opened. Complete authentication there; it will close automatically when done.");
                root.syncStatus = root.syncStatus ? root.syncStatus + "\n\n" + launched : launched;
                SettingsData.clearGreeterSyncPending();
                root.finishSync();
                return;
            }
            let fallback = I18n.tr("Terminal fallback failed. Install one of the supported terminal emulators or run '%1' manually.", "terminal fallback status, %1 is a command").arg("dms-greeter sync") + " " + I18n.tr("(exit %1)", "process exit code").arg(exitCode);
            const err = terminalFallbackErr.text.trim();
            if (err !== "")
                fallback += "\n\nstderr:\n" + err;
            root.syncStatus = root.syncStatus ? root.syncStatus + "\n\n" + fallback : fallback;
            root.finishSync();
        }
    }
}
