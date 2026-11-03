.pragma library

function getFileIcon(filename) {
    var ext = filename.lastIndexOf(".") > 0 ? filename.substring(filename.lastIndexOf(".") + 1).toLowerCase() : "";

    switch (ext) {
    case "pdf":
        return "picture_as_pdf";
    case "doc":
    case "docx":
    case "odt":
        return "description";
    case "xls":
    case "xlsx":
    case "ods":
        return "table_chart";
    case "ppt":
    case "pptx":
    case "odp":
        return "slideshow";
    case "txt":
    case "md":
    case "rst":
        return "article";
    case "jpg":
    case "jpeg":
    case "png":
    case "gif":
    case "svg":
    case "webp":
        return "image";
    case "mp3":
    case "wav":
    case "flac":
    case "ogg":
        return "audio_file";
    case "mp4":
    case "mkv":
    case "avi":
    case "webm":
        return "video_file";
    case "zip":
    case "tar":
    case "gz":
    case "7z":
    case "rar":
        return "folder_zip";
    case "js":
    case "ts":
    case "py":
    case "rs":
    case "go":
    case "java":
    case "c":
    case "cpp":
    case "h":
        return "code";
    case "html":
    case "css":
    case "htm":
        return "web";
    case "json":
    case "xml":
    case "yaml":
    case "yml":
        return "data_object";
    case "sh":
    case "bash":
    case "zsh":
        return "terminal";
    default:
        return "insert_drive_file";
    }
}

function stripIconPrefix(iconName) {
    if (!iconName)
        return "extension";
    if (iconName.startsWith("unicode:"))
        return iconName.substring(8);
    if (iconName.startsWith("material:"))
        return iconName.substring(9);
    if (iconName.startsWith("image:"))
        return iconName.substring(6);
    return iconName;
}

function detectIconType(iconName) {
    if (!iconName)
        return "material";
    if (iconName.startsWith("unicode:"))
        return "unicode";
    if (iconName.startsWith("material:"))
        return "material";
    if (iconName.startsWith("image:"))
        return "image";
    if (iconName.indexOf("/") >= 0 || iconName.indexOf(".") >= 0)
        return "image";
    if (/^[a-z]+-[a-z]/.test(iconName.toLowerCase()))
        return "image";
    return "material";
}

function classifyAppSource(app) {
    if (!app)
        return "";

    var execRaw = app.execString || app.exec || "";
    if (!execRaw && !app.id)
        return "";

    var exec = execRaw.toLowerCase();
    var cmd0 = (app.command && app.command.length > 0) ? String(app.command[0]).toLowerCase() : "";
    var id = (app.id || "").toLowerCase();

    if (cmd0 === "flatpak" || exec.indexOf("flatpak run ") !== -1)
        return "flatpak";

    if (cmd0 === "snap" || exec.indexOf("/snap/bin/") !== -1 || exec.indexOf("/snap/core") !== -1 || exec.indexOf("snap run ") === 0)
        return "snap";

    if (/\.appimage(\s|$|")/i.test(execRaw) || id.indexOf("appimagekit_") === 0)
        return "appimage";

    if (exec.indexOf("/nix/store/") !== -1 || exec.indexOf("/run/current-system/sw/") !== -1 || exec.indexOf("/etc/profiles/per-user/") !== -1)
        return "nix";

    return "system";
}

function extractFlatpakAppId(app) {
    if (!app)
        return "";

    var execRaw = app.execString || app.exec || "";
    if (app.command && app.command.length > 0) {
        var isRun = false;
        for (var i = 0; i < app.command.length; i++) {
            var arg = String(app.command[i]);
            if (arg === "run") {
                isRun = true;
                continue;
            }
            if (isRun && !arg.startsWith("-")) {
                return arg;
            }
        }
    }

    if (execRaw) {
        var match = execRaw.match(/\bflatpak\s+run\s+(?:--?[^\s]+\s+)*([a-zA-Z0-9_\-\.]+)/);
        if (match && match[1])
            return match[1];
    }

    var id = app.id || "";
    if (id.endsWith(".desktop"))
        return id.slice(0, -8);
    return id;
}

function sortPluginIdsByOrder(pluginIds, order) {
    if (!order || order.length === 0)
        return pluginIds;
    var orderMap = {};
    for (var i = 0; i < order.length; i++)
        orderMap[order[i]] = i;
    return pluginIds.slice().sort(function (a, b) {
        var aOrder = orderMap[a] !== undefined ? orderMap[a] : 9999;
        var bOrder = orderMap[b] !== undefined ? orderMap[b] : 9999;
        if (aOrder !== bOrder)
            return aOrder - bOrder;
        return a.localeCompare(b);
    });
}

function sortPluginsOrdered(plugins, order) {
    if (!order || order.length === 0)
        return plugins;
    var orderMap = {};
    for (var i = 0; i < order.length; i++)
        orderMap[order[i]] = i;
    return plugins.sort(function (a, b) {
        var aOrder = orderMap[a.id] !== undefined ? orderMap[a.id] : 9999;
        var bOrder = orderMap[b.id] !== undefined ? orderMap[b.id] : 9999;
        if (aOrder !== bOrder)
            return aOrder - bOrder;
        return a.id.localeCompare(b.id);
    });
}

function parseFileSearchPrefix(query) {
    if (!query || !query.startsWith("/"))
        return null;
    var rest = query.substring(1);
    if (rest === "d" || rest.startsWith("d ") || rest.startsWith("d\t"))
        return {
            type: "dir",
            query: rest.substring(1).trim()
        };
    if (rest === "f" || rest.startsWith("f ") || rest.startsWith("f\t"))
        return {
            type: "file",
            query: rest.substring(1).trim()
        };
    return {
        type: null,
        query: rest.trim()
    };
}
