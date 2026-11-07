.pragma library

var COLLECTION_ACTIONS = "shell.actions";
var COLLECTION_SETTINGS = "shell.settings";
var COLLECTION_APPS = "shell.apps";

// Hits come back as ids, so the id has to be enough to open the setting again:
// the same action string the launcher's settings results already use. A page
// entry shares its page with its siblings, hence the section suffix.
function settingId(entry) {
    if (entry.page)
        return "settings_page:" + entry.page + "#" + entry.section;
    return "settings_nav:" + entry.tabIndex + ":" + entry.section;
}

function settingAction(id) {
    if (id.indexOf("settings_page:") !== 0)
        return id;
    var hash = id.indexOf("#");
    return hash === -1 ? id : id.substring(0, hash);
}

function settingSection(id) {
    if (id.indexOf("settings_page:") === 0) {
        var hash = id.indexOf("#");
        return hash === -1 ? "" : id.substring(hash + 1);
    }
    return id.split(":").slice(2).join(":");
}

function compact(parts, separator) {
    var seen = {};
    var out = [];
    for (var i = 0; i < parts.length; i++) {
        var part = typeof parts[i] === "string" ? parts[i].trim() : "";
        if (part && !seen[part]) {
            seen[part] = true;
            out.push(part);
        }
    }
    return out.join(separator);
}

// The shell's own English source strings go in, not the translations: the model
// is multilingual, and a language switch must not re-embed the whole index.
function settingsItems(index) {
    var items = [];
    var seen = {};
    for (var i = 0; i < index.length; i++) {
        var entry = index[i];
        if (!entry || entry.runtimeType || !entry.label || !entry.section)
            continue;
        var id = settingId(entry);
        if (seen[id])
            continue;
        seen[id] = true;
        var where = compact([entry.parentLabel, entry.category], " > ");
        items.push({
            id: id,
            title: entry.label,
            text: compact([entry.description, where ? "Setting in " + where : ""], ". "),
            keywords: entry.keywords || []
        });
    }
    return items;
}

// "WebBrowser" -> "Web Browser"; the freedesktop ids are language neutral.
function categoryWords(categories) {
    var words = [];
    for (var i = 0; i < categories.length; i++) {
        if (categories[i] && String(categories[i]).indexOf("X-") !== 0)
            words.push(String(categories[i]).replace(/([a-z])([A-Z])/g, "$1 $2"));
    }
    return words;
}

function appItems(apps) {
    var items = [];
    var seen = {};
    for (var i = 0; i < apps.length; i++) {
        var app = apps[i];
        if (!app || !app.id || !app.name || seen[app.id])
            continue;
        seen[app.id] = true;
        items.push({
            id: app.id,
            title: app.name,
            text: compact([app.genericName, app.comment, categoryWords(app.categories || []).join(", ")], ". "),
            keywords: app.keywords || []
        });
    }
    return items;
}

function fnv1a(text) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < text.length; i++) {
        hash ^= text.charCodeAt(i);
        hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash.toString(16);
}

// What dsearch already holds for a collection is identified by this value, so an
// unchanged catalog is never sent again.
function signature(items) {
    var json = JSON.stringify(items);
    return items.length + ":" + json.length + ":" + fnv1a(json);
}
