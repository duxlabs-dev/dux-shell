pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "BootEntries.js" as BootEntries

// Lists EFI boot entries and reboots into one of them once, through the firmware's BootNext.
//
// rebootTo() runs in three steps: list the entries again so a stale saved entry is caught,
// set BootNext through pkexec, then hand the reboot itself to SessionService.
Singleton {
    id: root
    readonly property var log: Log.scoped("BootEntryService")

    // "unknown" until the first refresh, then "ready", "noEfi", "noTool" or "error"
    property string status: "unknown"
    // efibootmgr's stderr when status is "error"
    property string errorText: ""
    // Entries as [{id, label}], where id is the hex Boot#### number
    property var entries: []
    property string currentId: ""

    // Why entries cannot be listed, for display. Empty when status is "ready" or "unknown".
    readonly property string unavailableReason: {
        switch (status) {
        case "noEfi":
            return I18n.tr("This system was not started in UEFI mode", "reason EFI boot entries cannot be listed");
        case "noTool":
            return I18n.tr("Requires %1", "missing program", true).arg("efibootmgr");
        case "error":
            return errorText || I18n.tr("efibootmgr failed", "error, efibootmgr is a program name and stays untranslated");
        default:
            return "";
        }
    }

    // The saved entry waiting for the fresh listing before BootNext is set
    property var _pendingEntry: null

    function refresh() {
        listProcess.running = true;
    }

    function rebootTo(entry) {
        if (_pendingEntry || setProcess.running)
            return;
        _pendingEntry = entry;
        listProcess.running = true;
    }

    function _applyListing(exitCode) {
        if (exitCode === 0) {
            const parsed = BootEntries.parseEntries(listOutput.text);
            entries = parsed.entries;
            currentId = parsed.currentId;
            errorText = "";
            status = "ready";
        } else if (exitCode === listProcess.exitNoEfi) {
            status = "noEfi";
        } else if (exitCode === listProcess.exitNoTool) {
            status = "noTool";
        } else {
            errorText = listErrors.text.trim();
            log.warn("efibootmgr failed with exit code", exitCode, errorText);
            status = "error";
        }
    }

    function _setPendingBootNext() {
        const wanted = _pendingEntry;
        _pendingEntry = null;
        if (!wanted)
            return;
        if (status !== "ready") {
            ToastService.showError(I18n.tr("Failed to set next boot entry", "error toast, the one-time EFI BootNext entry could not be set"), unavailableReason);
            return;
        }
        const found = entries.find(e => e.id === wanted.id);
        if (!found || found.label !== wanted.label) {
            ToastService.showError(I18n.tr("Boot entry changed. Remove it and add it again.", "error toast, the firmware renumbered a saved EFI boot entry"), wanted.label);
            return;
        }
        setProcess.command = ["pkexec", "efibootmgr", "--bootnext", wanted.id];
        setProcess.running = true;
    }

    Process {
        id: listProcess

        // Exit codes of the command's own checks, before efibootmgr runs
        readonly property int exitNoEfi: 3
        readonly property int exitNoTool: 4

        running: false
        command: ["sh", "-c", "[ -d /sys/firmware/efi ] || exit " + exitNoEfi + "; command -v efibootmgr > /dev/null || exit " + exitNoTool + "; exec efibootmgr"]

        stdout: StdioCollector {
            id: listOutput
        }

        stderr: StdioCollector {
            id: listErrors
        }

        onExited: exitCode => {
            root._applyListing(exitCode);
            root._setPendingBootNext();
        }
    }

    Process {
        id: setProcess
        running: false

        stderr: StdioCollector {
            id: setErrors
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                // SessionService owns the reboot so custom reboot commands still apply
                SessionService.reboot();
                return;
            }
            // pkexec exits 126 when the user dismisses the auth dialog
            if (exitCode === 126) {
                root.log.info("BootNext cancelled at the auth prompt");
                return;
            }
            ToastService.showError(I18n.tr("Failed to set next boot entry", "error toast, the one-time EFI BootNext entry could not be set"), setErrors.text.trim());
        }
    }
}
