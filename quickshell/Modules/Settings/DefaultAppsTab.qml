import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root
    readonly property var log: Log.scoped("DefaultAppsTab")

    readonly property var appCategory: ({
            WebBrowser: 0,
            FileManager: 1,
            TextEditor: 2,
            ImageViewer: 3,
            VideoPlayer: 4,
            MusicPlayer: 5,
            PDFReader: 6,
            Mail: 7,
            Terminal: 8,
            Calendar: 9,
            Maps: 10,
            WordProcessor: 11,
            Spreadsheet: 12,
            Presentation: 13,
            ArchiveManager: 14
        })

    // category -> bare desktop id of the current default; category -> [{name, value, icon}]
    property var currentIds: ({})
    property var categoryModels: ({})

    // First MIME type of each category is read; all of them are written on pick.
    readonly property var mimeMapping: ({
            [root.appCategory.WebBrowser]: ["x-scheme-handler/https", "x-scheme-handler/http", "text/html", "application/xhtml+xml"],
            [root.appCategory.FileManager]: ["inode/directory", "x-scheme-handler/file", "x-scheme-handler/sftp"],
            [root.appCategory.TextEditor]: ["text/plain", "text/markdown", "application/x-zerosize", "text/x-c++src", "text/x-csrc", "text/x-python", "text/x-shellscript", "application/json"],
            [root.appCategory.ImageViewer]: ["image/png", "image/jpeg", "image/gif", "image/bmp", "image/webp", "image/avif", "image/svg+xml", "image/tiff", "image/heic", "image/heif", "image/jxl"],
            [root.appCategory.VideoPlayer]: ["video/mp4", "video/x-matroska", "video/webm", "video/avi", "video/mpeg", "video/quicktime", "video/x-msvideo"],
            [root.appCategory.MusicPlayer]: ["audio/mpeg", "audio/x-flac", "audio/wav", "audio/ogg", "audio/aac", "audio/webm"],
            [root.appCategory.PDFReader]: ["application/pdf", "application/x-ext-pdf", "application/x-bzpdf", "application/x-gzpdf", "application/vnd.comicbook-rar", "application/vnd.comicbook+zip"],
            [root.appCategory.Mail]: ["x-scheme-handler/mailto"],
            [root.appCategory.Calendar]: ["text/calendar", "x-scheme-handler/calendar", "x-scheme-handler/webcal", "x-scheme-handler/webcals"],
            [root.appCategory.Maps]: ["x-scheme-handler/geo"],
            [root.appCategory.WordProcessor]: ["application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/msword", "application/vnd.oasis.opendocument.text", "application/rtf"],
            [root.appCategory.Spreadsheet]: ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/vnd.ms-excel", "application/vnd.oasis.opendocument.spreadsheet", "text/csv"],
            [root.appCategory.Presentation]: ["application/vnd.openxmlformats-officedocument.presentationml.presentation", "application/vnd.ms-powerpoint", "application/vnd.oasis.opendocument.presentation"],
            [root.appCategory.ArchiveManager]: ["application/zip", "application/x-tar", "application/x-7z-compressed", "application/x-rar", "application/gzip", "application/x-bzip2", "application/x-xz"],
            [root.appCategory.Terminal]: ["terminal"] // Special
        })

    readonly property string dmsChooserId: "dms-open"
    readonly property string dmsChooserLabel: I18n.tr("DMS chooser")
    readonly property string terminalsListPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/xdg-terminals.list"

    function stripDesktopSuffix(id) {
        return (id || "").replace(/\.desktop$/, "");
    }

    function lookupEntry(appId) {
        const bare = stripDesktopSuffix(appId);
        return DesktopEntries.byId(bare) || DesktopEntries.heuristicLookup(appId) || DesktopEntries.heuristicLookup(bare);
    }

    // NoDisplay handlers stay hidden like in the launcher, except the shell's own (notepad)
    function isShellOwn(appId) {
        return stripDesktopSuffix(appId).startsWith("dev.duxlabs.shell.");
    }

    function getAppDisplayName(appId) {
        if (stripDesktopSuffix(appId) === root.dmsChooserId) {
            return root.dmsChooserLabel;
        }
        return lookupEntry(appId)?.name || appId;
    }

    function getAppIcon(appId) {
        return lookupEntry(appId)?.icon || "";
    }

    function entryFor(id, name, icon) {
        return {
            name: name || getAppDisplayName(id),
            value: stripDesktopSuffix(id),
            icon: icon || getAppIcon(id)
        };
    }

    function withDmsChooser(entries) {
        const filtered = (entries || []).filter(e => e.value !== root.dmsChooserId);
        return [
            {
                name: root.dmsChooserLabel,
                value: root.dmsChooserId,
                icon: "material:apps"
            }
        ].concat(filtered);
    }

    function setModel(category, entries) {
        const models = Object.assign({}, root.categoryModels);
        models[category] = category === root.appCategory.Terminal ? entries : withDmsChooser(entries);
        root.categoryModels = models;
    }

    function mergeEntries(category, entries) {
        const existing = root.categoryModels[category] || [];
        const known = new Set(existing.map(opt => opt.value));
        const extra = entries.filter(e => !known.has(e.value));
        if (extra.length === 0 && existing.length === 0) {
            return;
        }
        setModel(category, existing.concat(extra));
    }

    function setCurrentId(category, id) {
        const ids = Object.assign({}, root.currentIds);
        ids[category] = stripDesktopSuffix(id);
        root.currentIds = ids;
    }

    function categoryEntries(categoryName) {
        const apps = AppSearchService.getVisibleApplications() || [];
        return apps.filter(app => (app.categories || []).includes(categoryName)).map(app => app.id || app.execString || "").filter(id => id).map(id => entryFor(id));
    }

    Component.onCompleted: {
        Object.values(root.appCategory).forEach(category => {
            switch (category) {
            case root.appCategory.Terminal:
                // Terminals have no MIME type; xdg-terminal-exec reads xdg-terminals.list instead
                setModel(category, categoryEntries("TerminalEmulator"));
                return;
            case root.appCategory.WebBrowser:
                // Menu category only: anything that registers an https handler would otherwise qualify
                setModel(category, categoryEntries("WebBrowser"));
                DesktopService.getDefaultApp(root.mimeMapping[category][0], category.toString());
                return;
            case root.appCategory.FileManager:
                // Seed from the menu category so Kate does not lead just because it opens folders
                setModel(category, categoryEntries("FileManager"));
                break;
            }
            DesktopService.getDefaultApp(root.mimeMapping[category][0], category.toString());
            DesktopService.getHandlersForMimeType(root.mimeMapping[category][0], category.toString());
            DesktopService.getAppsForMimeType(root.mimeMapping[category][0], category.toString());
        });
    }

    function setDefaultTerminal(terminalId) {
        const id = stripDesktopSuffix(terminalId) + ".desktop";
        const rest = terminalsList.text().split("\n").map(l => l.trim()).filter(l => l && l !== id);
        terminalsList.setText([id].concat(rest).join("\n") + "\n");
        setCurrentId(root.appCategory.Terminal, id);
    }

    FileView {
        id: terminalsList
        path: root.terminalsListPath
        printErrors: false
        atomicWrites: true
        onLoaded: {
            const first = text().split("\n").map(l => l.trim()).find(l => l && !l.startsWith("#"));
            if (first) {
                root.setCurrentId(root.appCategory.Terminal, first);
            }
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                log.warn("Failed to read xdg-terminals.list:", error);
            }
        }
        onSaveFailed: error => log.error("Failed to write xdg-terminals.list:", error)
    }

    Connections {
        target: DesktopService

        function onGetHandlersForMimeResult(mimeType, apps, callbackId) {
            root.mergeEntries(parseInt(callbackId), (apps || []).filter(app => app.id).map(app => root.entryFor(app.id, app.name, app.icon)));
        }

        function onGetAppsForMimeResult(mimeType, appIds, callbackId) {
            root.mergeEntries(parseInt(callbackId), (appIds || []).filter(id => root.isShellOwn(id)).map(id => root.entryFor(id)));
        }

        function onGetDefaultAppResult(mimeType, desktopFileId, callbackId) {
            if (!desktopFileId) {
                log.info("No default app found for MIME type:", mimeType);
                return;
            }
            root.setCurrentId(parseInt(callbackId), desktopFileId);
        }
    }

    component AppSelector: SettingsDropdownRow {
        property int category: -1
        readonly property var entries: root.categoryModels[category] || []
        options: entries.map(opt => opt.name)
        optionValues: entries.map(opt => opt.value)
        optionImages: entries.map(opt => opt.icon || "")
        enabled: options.length > 0
        emptyText: options.length > 0 ? I18n.tr("Unset", "Unset") : ""
        currentValue: root.currentIds[category] || ""
        onValueChanged: id => {
            if (!id) {
                return;
            }
            if (category === root.appCategory.Terminal) {
                root.setDefaultTerminal(id);
                return;
            }
            DesktopService.setDefaultAppForMimes(root.mimeMapping[category], id, category.toString());
            root.setCurrentId(category, id);
        }
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            settingKey: "defaultAppsInternet"
            tags: ["browser", "mail", "email", "web"]
            title: I18n.tr("Internet", "Internet")
            iconName: "public"

            AppSelector {
                text: I18n.tr("Web browser")
                tags: ["web", "browser", "internet", "links", "html"]
                category: root.appCategory.WebBrowser
            }

            AppSelector {
                text: I18n.tr("Mail", "Mail")
                category: root.appCategory.Mail
                tags: ["mail", "email", "mailto"]
            }

            AppSelector {
                text: I18n.tr("Maps", "Maps")
                category: root.appCategory.Maps
                tags: ["maps", "geo", "location"]
            }
        }

        SettingsCard {
            settingKey: "defaultAppsUtilities"
            tags: ["file", "manager", "terminal", "editor", "archive", "zip"]
            title: I18n.tr("Utilities", "Utilities")
            iconName: "terminal"

            AppSelector {
                text: I18n.tr("File manager")
                tags: ["file", "manager", "directory", "sftp"]
                category: root.appCategory.FileManager
            }
            AppSelector {
                text: I18n.tr("Terminal", "Terminal")
                category: root.appCategory.Terminal
                tags: ["terminal", "console", "xdg-terminal-exec"]
            }
            AppSelector {
                text: I18n.tr("Calendar", "Calendar")
                category: root.appCategory.Calendar
                tags: ["calendar", "events"]
            }
            AppSelector {
                text: I18n.tr("Archive manager", "default app selector label for archive manager program for zip and tar files")
                category: root.appCategory.ArchiveManager
                tags: ["archive", "zip", "tar", "compress"]
            }
        }

        SettingsCard {
            settingKey: "defaultAppsDocuments"
            tags: ["pdf", "text", "reader", "office", "word", "spreadsheet", "presentation"]
            title: I18n.tr("Documents", "Documents")
            iconName: "edit_document"

            AppSelector {
                text: I18n.tr("Text editor")
                category: root.appCategory.TextEditor
                tags: ["text", "editor"]
            }
            AppSelector {
                text: I18n.tr("PDF reader")
                category: root.appCategory.PDFReader
                tags: ["pdf", "reader"]
            }
            AppSelector {
                text: I18n.tr("Word processor", "default app selector label for word processor program")
                category: root.appCategory.WordProcessor
                tags: ["word", "document", "docs", "office", "writer"]
            }
            AppSelector {
                text: I18n.tr("Spreadsheet", "default app selector label for spreadsheet program")
                category: root.appCategory.Spreadsheet
                tags: ["spreadsheet", "excel", "calc", "csv", "office"]
            }
            AppSelector {
                text: I18n.tr("Presentation", "default app selector label for slide presentation program, not presentation mode")
                category: root.appCategory.Presentation
                tags: ["presentation", "powerpoint", "ppt", "slides", "office"]
            }
        }

        SettingsCard {
            settingKey: "defaultAppsMultimedia"
            tags: ["image", "video", "music", "viewer", "player"]
            title: I18n.tr("Multimedia", "Multimedia")
            iconName: "movie"
            AppSelector {
                text: I18n.tr("Image viewer")
                category: root.appCategory.ImageViewer
                tags: ["image", "viewer"]
            }
            AppSelector {
                text: I18n.tr("Video player")
                category: root.appCategory.VideoPlayer
                tags: ["video", "player"]
            }
            AppSelector {
                text: I18n.tr("Music player")
                category: root.appCategory.MusicPlayer
                tags: ["music", "player", "audio"]
            }
        }
    }
}
