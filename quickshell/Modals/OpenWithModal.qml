import QtQuick
import Quickshell
import qs.Common
import qs.Services

AppPickerModal {
    id: root

    title: I18n.tr("Open with", "app picker title, followed by a list of apps") + "…"
    viewMode: SettingsData.appPickerViewMode || "grid"

    onViewModeChanged: {
        SettingsData.set("appPickerViewMode", viewMode);
    }

    function shellEscape(str) {
        return "'" + str.replace(/'/g, "'\\''") + "'";
    }

    onApplicationSelected: (app, filePath) => {
        if (!app)
            return;
        const entry = SessionService.resolveDesktopId(app.appId);
        if (entry) {
            SessionService.launchDesktopEntry(entry, false, [filePath]);
            return;
        }
        let cmd = app.exec || "";
        const escapedPath = shellEscape(filePath);
        const escapedUri = shellEscape("file://" + filePath);

        let hasField = false;
        if (cmd.includes("%f")) {
            cmd = cmd.replace("%f", escapedPath);
            hasField = true;
        } else if (cmd.includes("%F")) {
            cmd = cmd.replace("%F", escapedPath);
            hasField = true;
        } else if (cmd.includes("%u")) {
            cmd = cmd.replace("%u", escapedUri);
            hasField = true;
        } else if (cmd.includes("%U")) {
            cmd = cmd.replace("%U", escapedUri);
            hasField = true;
        }

        cmd = cmd.replace(/%[ikc]/g, "");

        if (!hasField) {
            cmd += " " + escapedPath;
        }

        log.debug("FilePicker: Launching", cmd);

        Quickshell.execDetached({
            command: ["sh", "-c", cmd]
        });
    }
}
