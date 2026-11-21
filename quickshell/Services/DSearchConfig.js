.pragma library

// dsearch reads [semantic].enabled once at start, so turning semantic search on or
// off means editing this key in config.toml and restarting the service. Only that
// key is touched; comments, other tables and the rest of the file stay as written.

var SECTION = /^\s*\[([^\[\]]+)\]\s*(#.*)?$/;
var ANY_HEADER = /^\s*\[/;
var ENABLED = /^\s*enabled\s*=/;

function configPath(env) {
    var base = env.configHome || (env.home ? env.home + "/.config" : "");
    return base ? base + "/dsearch/config.toml" : "";
}

function _inSemantic(lines, visit) {
    var inside = false;
    for (var i = 0; i < lines.length; i++) {
        var header = SECTION.exec(lines[i]);
        if (header)
            inside = header[1].trim() === "semantic";
        else if (ANY_HEADER.test(lines[i]))
            inside = false;
        visit(i, inside, !!header);
    }
}

function readSemanticEnabled(text) {
    var enabled = false;
    var lines = String(text || "").split("\n");
    _inSemantic(lines, function (i, inside, isHeader) {
        if (inside && !isHeader && ENABLED.test(lines[i]))
            enabled = /=\s*true\b/.test(lines[i]);
    });
    return enabled;
}

// Returns {text} or {error} when the file defines semantic in a form a line edit cannot follow.
function setSemanticEnabled(text, enabled) {
    var source = String(text || "");
    var lines = source.split("\n");
    var value = enabled ? "true" : "false";
    for (var k = 0; k < lines.length; k++) {
        if (/^\s*semantic\s*=/.test(lines[k]) || /^\s*semantic\.enabled\s*=/.test(lines[k]))
            return {
                error: "semantic is written inline in the config"
            };
    }
    var keyAt = -1;
    var headerAt = -1;
    _inSemantic(lines, function (i, inside, isHeader) {
        if (isHeader && inside && headerAt === -1)
            headerAt = i;
        if (inside && !isHeader && keyAt === -1 && ENABLED.test(lines[i]))
            keyAt = i;
    });
    if (keyAt !== -1) {
        lines[keyAt] = lines[keyAt].replace(/=.*$/, "= " + value);
        return {
            text: lines.join("\n")
        };
    }
    if (headerAt !== -1) {
        lines.splice(headerAt + 1, 0, "enabled = " + value);
        return {
            text: lines.join("\n")
        };
    }
    var body = source.length > 0 && !source.endsWith("\n") ? source + "\n" : source;
    return {
        text: body + (body.length > 0 ? "\n" : "") + "[semantic]\nenabled = " + value + "\n"
    };
}
