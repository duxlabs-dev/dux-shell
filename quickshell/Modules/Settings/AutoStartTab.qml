import QtCore
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    readonly property var log: Log.scoped("AutoStartTab")
    property var parentModal: null
    property var entries: []
    property var desktopApps: []
    property string newEntryType: "desktop"
    property string newEntryName: ""
    property string newEntryExec: ""
    property string newEntryDesktopId: ""
    property string newEntryCommandWrapper: "%command%"
    readonly property bool autostartTargetInactive: DesktopService.isSystemd && DesktopService.systemdAutostartTargetChecked && !DesktopService.systemdAutostartTargetActive

    readonly property string autostartDir: {
        const configHome = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        return configHome + "/autostart";
    }

    function lookupDesktopIcon(name, exec, fileName) {
        const appId = fileName ? fileName.replace(/\.desktop$/, "") : "";
        let entry = appId ? DesktopEntries.heuristicLookup(appId) : null;
        if (entry && entry.icon)
            return entry.icon;
        if (exec) {
            const cmdBase = exec.split(" ")[0].split("/").pop();
            for (let i = 0; i < root.desktopApps.length; i++) {
                const app = root.desktopApps[i];
                if (app.icon) {
                    const appExec = (app.exec || app.execString || "").split(" ")[0].split("/").pop();
                    if (appExec === cmdBase)
                        return app.icon;
                }
            }
        }
        return "";
    }

    function parseDesktopFile(content, filePath) {
        if (!content || content.length === 0)
            return null;
        const lines = content.split("\n");
        let name = "";
        let execCmd = "";
        let icon = "";
        let hidden = false;
        let isDesktopEntry = false;
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (line === "[Desktop Entry]") {
                isDesktopEntry = true;
            } else if (isDesktopEntry) {
                if (line.startsWith("["))
                    break;
                const nameMatch = line.match(/^Name=(.+)$/);
                if (nameMatch)
                    name = nameMatch[1];
                const execMatch = line.match(/^Exec=(.+)$/);
                if (execMatch)
                    execCmd = execMatch[1];
                const iconMatch = line.match(/^Icon=(.+)$/);
                if (iconMatch)
                    icon = iconMatch[1];
                const hiddenMatch = line.match(/^Hidden=(true|false)$/);
                if (hiddenMatch)
                    hidden = hiddenMatch[1] === "true";
            }
        }
        if (!isDesktopEntry || !name || !execCmd)
            return null;
        const fileName = filePath.split("/").pop();
        if (!icon)
            icon = root.lookupDesktopIcon(name, execCmd, fileName);
        return {
            name: name,
            exec: execCmd,
            icon: icon,
            hidden: hidden,
            filePath: filePath,
            fileName: fileName,
            content: content
        };
    }

    function addEntry() {
        if (newEntryType === "desktop") {
            if (!newEntryDesktopId)
                return;
            const app = desktopApps.find(a => (a.id || a.execString) === newEntryDesktopId);
            if (!app)
                return;
            const entryName = app.name || newEntryDesktopId;
            const appExec = app.exec || app.execString || "";
            const execCmd = root.newEntryCommandWrapper.replace("%command%", appExec);
            const appIcon = app.icon || "";
            const fileName = entryName.toLowerCase().replace(/[^a-z0-9]/g, "-") + ".desktop";
            writeDesktopFile(fileName, entryName, execCmd, appIcon);
        } else {
            if (!newEntryName || !newEntryExec)
                return;
            const fileName = newEntryName.toLowerCase().replace(/[^a-z0-9]/g, "-") + ".desktop";
            writeDesktopFile(fileName, newEntryName, newEntryExec, "");
        }
    }

    function writeDesktopFile(fileName, name, execCmd, icon) {
        let content = "[Desktop Entry]\nType=Application\nName=" + name + "\nExec=" + execCmd + "\n";
        if (icon)
            content += "Icon=" + icon + "\n";
        writerFileView.path = root.autostartDir + "/" + fileName;
        writerFileView.setText(content);
        root.resetNewEntry();
    }

    function setHidden(entry, hidden) {
        if (!entry || !entry.content)
            return;
        const lines = entry.content.split("\n");
        const hiddenValue = hidden ? "true" : "false";
        let found = false;
        const merged = lines.map(line => {
            const m = line.match(/^Hidden=(true|false)\s*$/);
            if (m) {
                found = true;
                return "Hidden=" + hiddenValue;
            }
            return line;
        });
        if (!found) {
            const idx = merged.findIndex(l => l.trim() === "[Desktop Entry]");
            if (idx >= 0)
                merged.splice(idx + 1, 0, "Hidden=" + hiddenValue);
            else
                merged.unshift("Hidden=" + hiddenValue);
        }
        writerFileView.path = entry.filePath;
        writerFileView.setText(merged.join("\n"));
    }

    function removeEntry(filePath) {
        const proc = removeFileComponent.createObject(root, {
            targetPath: filePath,
            running: true
        });
    }

    function resetNewEntry() {
        newEntryType = "desktop";
        newEntryName = "";
        newEntryExec = "";
        newEntryDesktopId = "";
        newEntryCommandWrapper = "%command%";
    }

    function addOrUpdateEntry(entry) {
        var list = root.entries.slice();
        for (var i = 0; i < list.length; i++) {
            if (list[i].filePath === entry.filePath) {
                list[i] = entry;
                root.entries = list;
                return;
            }
        }
        list.push(entry);
        list.sort((a, b) => a.fileName.localeCompare(b.fileName));
        root.entries = list;
    }

    function removeEntryByPath(filePath) {
        var list = root.entries.filter(e => e.filePath !== filePath);
        root.entries = list;
    }

    FileView {
        id: writerFileView
        blockLoading: true
        atomicWrites: true
        onSaveFailed: error => {
            ToastService.showError(I18n.tr("Failed to write autostart entry"));
            log.warn("Failed to write autostart entry to " + writerFileView.path + ": " + error);
        }
    }

    FolderListModel {
        id: folderModel
        nameFilters: ["*.desktop"]
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name

        onStatusChanged: {
            if (status !== FolderListModel.Ready)
                return;
            // rebuild entries
            const validPaths = new Set();
            for (let i = 0; i < folderModel.count; i++) {
                const fp = folderModel.get(i, "filePath") || "";
                validPaths.add(fp.startsWith("file://") ? fp.substring(7) : fp);
            }
            const filtered = root.entries.filter(e => validPaths.has(e.filePath));
            if (filtered.length !== root.entries.length) {
                root.entries = filtered;
            }
        }

        onCountChanged: {
            fileReaderRepeater.model = count;
        }
    }

    Repeater {
        id: fileReaderRepeater
        model: 0

        Item {
            required property int index

            readonly property string filePath: {
                const fp = folderModel.get(index, "filePath") || "";
                return fp.startsWith("file://") ? fp.substring(7) : fp;
            }

            FileView {
                id: fileView
                path: filePath ? "file://" + filePath : ""
                watchChanges: true

                onLoaded: {
                    const entry = root.parseDesktopFile(fileView.text(), filePath);
                    if (entry) {
                        root.addOrUpdateEntry(entry);
                    } else {
                        root.removeEntryByPath(filePath);
                    }
                }

                onFileChanged: reload()

                onLoadFailed: {
                    root.removeEntryByPath(filePath);
                }
            }
        }
    }

    Component {
        id: removeFileComponent
        Process {
            property string targetPath: ""
            command: ["rm", "-f", targetPath]
            onExited: (exitCode, exitStatus) => {
                root.removeEntryByPath(targetPath);
                destroy();
            }
        }
    }

    function generateTrayIconFixSystemdOverride() {
        const configHome = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const dir = configHome + "/systemd/user/app-@autostart.service.d";
        const proc = systemdOverrideMkDirComp.createObject(root, {
            targetPath: dir,
            running: true
        });
    }

    FileView {
        id: systemdOverrideWriter
        atomicWrites: true

        // make sure we don't overwrite an existing override with a default one, in case the user has already customized it
        function buildOverrideContent(existing) {
            if (!existing)
                return "[Unit]\nAfter=dms.service\n";
            const lines = existing.split("\n");
            const hasAfter = lines.some(l => l.trim() === "After=dms.service");
            if (hasAfter)
                return existing;
            const unitIdx = lines.findIndex(l => l.trim() === "[Unit]");
            if (unitIdx >= 0) {
                lines.splice(unitIdx + 1, 0, "After=dms.service");
            } else {
                lines.push("[Unit]", "After=dms.service");
            }
            return lines.join("\n");
        }

        onLoaded: {
            const merged = buildOverrideContent(text());
            if (merged !== text())
                setText(merged);
            ToastService.showInfo(I18n.tr("Systemd override generated"));
        }

        onLoadFailed: {
            setText("[Unit]\nAfter=dms.service\n");
            ToastService.showInfo(I18n.tr("Systemd override generated"));
        }

        onSaveFailed: error => {
            ToastService.showError(I18n.tr("Failed to generate systemd override"));
            log.warn("Failed to write systemd override to " + systemdOverrideWriter.path + ": " + error);
        }
    }

    Component {
        id: systemdOverrideMkDirComp
        Process {
            property string targetPath: ""
            command: ["mkdir", "-p", targetPath]
            onExited: exitCode => {
                if (exitCode === 0) {
                    systemdOverrideWriter.path = targetPath + "/override.conf";
                } else {
                    ToastService.showError(I18n.tr("Failed to generate systemd override"));
                }
                destroy();
            }
        }
    }

    Component {
        id: autostartInitMkDirComp
        Process {
            command: ["mkdir", "-p", root.autostartDir]
            onExited: exitCode => {
                if (exitCode === 0) {
                    folderModel.folder = "file://" + root.autostartDir;
                }
                destroy();
            }
        }
    }

    Component.onCompleted: {
        DesktopService.ensureProbed();
        desktopApps = AppSearchService.getVisibleApplications() || [];
        autostartInitMkDirComp.createObject(root, {
            running: true
        });
    }

    Component.onDestruction: {
        desktopApps = [];
    }

    DFlickable {
        anchors.fill: parent
        clip: true
        contentHeight: mainColumn.height + Theme.spacingXL
        contentWidth: width

        AppBrowserPopup {
            id: appBrowserPopup
            appsModel: root.desktopApps
            parentModal: root.parentModal
            onAppSelected: appId => root.newEntryDesktopId = appId
        }

        Column {
            id: mainColumn
            topPadding: Theme.spacingXS
            width: Math.min(SettingsMetrics.contentMaxWidth, parent.width - Theme.spacingL * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingXL

            SettingsNoteRow {
                width: parent.width
                paintBackground: false
                visible: root.autostartTargetInactive
                text: I18n.tr("Autostart entries will not run at login because %1 is not active.", "autostart settings warning, %1 is a systemd target").arg("xdg-desktop-autostart.target")
            }

            SettingsLinkRow {
                width: parent.width
                visible: root.autostartTargetInactive
                iconName: "menu_book"
                title: I18n.tr("Docs")
                subtitle: Site.domain
                url: Site.docs + "/dms/autostart#target-not-active"
            }

            SettingsCard {
                settingKey: "autostartAddEntry"
                tags: ["autostart", "add", "entry", "command", "startup"]
                width: parent.width
                visible: DesktopService.autostartAvailable
                iconName: "add_circle"
                title: I18n.tr("Add entry")

                SettingsDropdownRow {
                    width: parent.width
                    text: I18n.tr("Type", "noun, dropdown label for the kind of entry")
                    currentValue: root.newEntryType === "desktop" ? I18n.tr("Desktop app") : I18n.tr("Command line")
                    options: [I18n.tr("Desktop app"), I18n.tr("Command line")]
                    onValueChanged: val => {
                        root.newEntryType = val === I18n.tr("Desktop app") ? "desktop" : "command";
                    }
                }

                SettingsRow {
                    id: appPickerRow

                    readonly property var selectedApp: root.desktopApps.find(a => (a.id || a.execString) === root.newEntryDesktopId) ?? null

                    visible: root.newEntryType === "desktop"
                    title: I18n.tr("App", "noun, application picker label in autostart add entry")
                    subtitle: root.newEntryDesktopId ? (selectedApp?.name || selectedApp?.id || root.newEntryDesktopId) : I18n.tr("No application selected")
                    clickable: true
                    showChevron: true
                    onClicked: appBrowserPopup.show()
                    leading: AppIconRenderer {
                        width: Theme.iconSize
                        height: Theme.iconSize
                        iconValue: appPickerRow.selectedApp?.icon || "application-x-executable"
                        iconSize: Theme.iconSize
                        fallbackText: (appPickerRow.selectedApp?.name || "?").charAt(0).toUpperCase()
                    }
                }

                SettingsRow {
                    visible: root.newEntryType === "desktop"
                    body: DTextField {
                        outlined: true
                        leftIconName: "terminal"
                        labelText: I18n.tr("Command")
                        supportingText: I18n.tr("Wrap the app command. %command% is replaced with the actual executable", "autostart command field hint, keep %command% verbatim")
                        width: parent.width
                        placeholderText: "%command%"
                        text: root.newEntryCommandWrapper
                        onTextChanged: root.newEntryCommandWrapper = text
                    }
                }

                SettingsRow {
                    visible: root.newEntryType === "command"
                    body: Column {
                        width: parent.width
                        spacing: Theme.spacingM

                        DTextField {
                            outlined: true
                            leftIconName: "badge"
                            labelText: I18n.tr("Name")
                            width: parent.width
                            placeholderText: I18n.tr("e.g. My Script")
                            text: root.newEntryName
                            onTextChanged: root.newEntryName = text
                        }

                        DTextField {
                            outlined: true
                            leftIconName: "terminal"
                            labelText: I18n.tr("Command", "noun, text field label for a shell command")
                            width: parent.width
                            placeholderText: I18n.tr("e.g. /usr/bin/my-script --flag")
                            text: root.newEntryExec
                            onTextChanged: root.newEntryExec = text
                        }
                    }
                }

                SettingsRow {
                    body: StyledText {
                        width: parent.width
                        text: I18n.tr("These add entries to the XDG autostart directory (%1)", "autostart note, %1 is a path").arg("~/.config/autostart/*.desktop")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                DButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Add to autostart")
                    iconName: "add"
                    enabled: {
                        if (root.newEntryType === "desktop")
                            return root.newEntryDesktopId !== "";
                        return root.newEntryName !== "" && root.newEntryExec !== "";
                    }
                    onClicked: root.addEntry()
                }
            }

            SettingsCard {
                id: entriesCard
                width: parent.width
                iconName: "line_start"
                title: I18n.tr("Entries", "card title listing autostart entries")
                settingKey: "autostartEntries"
                visible: DesktopService.autostartAvailable
                collapsible: true
                expanded: true

                SettingsRow {
                    body: Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledText {
                            width: parent.width - clearAllButton.width - Theme.spacingM
                            text: I18n.tr("Applications and commands to start automatically when you log in")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DActionButton {
                            id: clearAllButton
                            iconName: "delete_sweep"
                            tooltipText: I18n.tr("Clear All")
                            iconSize: Theme.iconSizeMedium
                            iconColor: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                for (let i = 0; i < root.entries.length; i++) {
                                    root.removeEntry(root.entries[i].filePath);
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: root.entries

                    delegate: SettingsRow {
                        id: entryRow

                        required property var modelData

                        title: modelData.name
                        titleColor: modelData.hidden ? Theme.surfaceVariantText : Theme.surfaceText
                        subtitle: modelData.hidden ? I18n.tr("Disabled") : modelData.exec
                        singleLineTitle: true
                        leading: AppIconRenderer {
                            width: Theme.iconSize
                            height: Theme.iconSize
                            iconValue: entryRow.modelData.icon || "application-x-executable"
                            iconSize: Theme.iconSize
                            fallbackText: (entryRow.modelData.name || "?").charAt(0).toUpperCase()
                        }

                        DToggle {
                            hideText: true
                            text: entryRow.title
                            checked: !entryRow.modelData.hidden
                            onToggled: checked => root.setHidden(entryRow.modelData, !checked)
                        }

                        DActionButton {
                            iconName: "delete"
                            iconColor: Theme.error
                            tooltipText: I18n.tr("Remove")
                            onClicked: root.removeEntry(entryRow.modelData.filePath)
                        }
                    }
                }

                SettingsRow {
                    visible: root.entries.length === 0
                    subtitle: I18n.tr("No autostart entries")
                }
            }

            SettingsCard {
                settingKey: "autostartTrayIconFix"
                tags: ["tray", "icons", "fix", "systemd"]
                width: parent.width
                iconName: "handyman"
                title: I18n.tr("Tray icon fix")
                visible: DesktopService.isSystemd && DesktopService.autostartAvailable

                SettingsRow {
                    body: Column {
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledText {
                            width: parent.width
                            text: I18n.tr("If autostart app icons don't appear in the system tray, generate a systemd override to ensure DMS starts before autostart apps")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }

                        DButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.tr("Generate override")
                            iconName: "build"
                            onClicked: root.generateTrayIconFixSystemdOverride()
                        }
                    }
                }
            }
        }
    }
}
