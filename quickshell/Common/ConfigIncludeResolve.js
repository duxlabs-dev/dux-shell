function shQuote(value) {
    return "'" + String(value ?? "").replace(/'/g, "'\\''") + "'";
}

function dirname(path) {
    const idx = String(path ?? "").lastIndexOf("/");
    return idx > 0 ? path.substring(0, idx) : ".";
}

function sectionHeaderFor(includeLine) {
    const line = String(includeLine ?? "").trim();
    if (line.startsWith("require"))
        return "-- DMS Include Configs";
    if (line.startsWith("source") || line.startsWith("[global]"))
        return "# DMS Include Configs";
    return "// DMS Include Configs";
}

function managedIncludePatternFor(includeLine) {
    const line = String(includeLine ?? "").trim();
    if (line.startsWith("require"))
        return "require.*dms[.]";
    if (line.startsWith("source"))
        return "source.*dms/";
    return "include.*dms/";
}

function commentTokenFor(includeLine) {
    return sectionHeaderFor(includeLine).split(" ")[0];
}

const commentPattern = "^[[:space:]]*(//|#|--)";

// ok is 0 inside a TOML table other than [global] or [rule], where Mango reads no source.
const tablePrefix = "FNR == 1 { ok = 1 } toml && /^[[:space:]]*\\[/ { ok = ($0 ~ /^[[:space:]]*\\[[[:space:]]*(global|rule)[[:space:]]*\\]/) } ";

function awkVars(token, pattern, toml) {
    return `-v c=${shQuote(token)} -v cm=${shQuote(commentPattern)} -v re=${shQuote(pattern)} -v toml=${toml ? 1 : 0}`;
}

// Writes through cat so a dotfiles symlink stays a link, and keeps a missing final newline missing;
// the group fails when no line changed.
function rewriteCommand(file, awkArgs, program, inputs) {
    return `{ t=$(mktemp) && awk ${awkArgs} ${shQuote(tablePrefix + program)} ${inputs} > "$t" && if [ -n "$(tail -c 1 ${file})" ]; then printf '%s' "$(cat "$t")" > ${file}; else cat "$t" > ${file}; fi; s=$?; rm -f "$t"; [ "$s" -eq 0 ]; }`;
}

function disableCommand(file, token, pattern, toml) {
    const program = "ok && $0 !~ cm && $0 ~ re { $0 = c \" \" $0; n++ } { print } END { exit (n == 0) }";
    return rewriteCommand(file, awkVars(token, pattern, toml), program, file);
}

// Only the last commented copy comes back, so an older note of the same line stays a comment.
function enableCommand(file, token, pattern, toml) {
    const program = "NR == FNR { r = substr($0, length(c) + 2); if (ok && index($0, c \" \") == 1 && r !~ cm && r ~ re) last = FNR; next } FNR == last { $0 = substr($0, length(c) + 2); n++ } { print } END { exit (n == 0) }";
    return rewriteCommand(file, awkVars(token, pattern, toml), program, file + " " + file);
}

// Mango cannot comment out one element of a one-line array, so arrays holding one are split a line per element first.
// An element with a comma in it would split wrong, so that array stays as it is.
function splitArrayCommand(file, pattern) {
    const program = "ok && $0 !~ cm && $0 ~ re && match($0, /^[[:space:]]*source[[:space:]]*=[[:space:]]*\\[/) { head = substr($0, 1, RLENGTH); body = substr($0, RLENGTH + 1); if (body ~ /^[[:space:]]*((\"[^\",]*\"|'[^',]*')[[:space:]]*,[[:space:]]*)*((\"[^\",]*\"|'[^',]*')[[:space:]]*)?\\][[:space:]]*$/) { ind = head; sub(/[^[:space:]].*/, \"\", ind); sub(/[[:space:]]*\\][[:space:]]*$/, \"\", body); print head; k = split(body, parts, \",\"); for (i = 1; i <= k; i++) { e = parts[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, \"\", e); if (e != \"\") print ind \"    \" e \",\" } print ind \"]\"; n++; next } } { print } END { exit (n == 0) }";
    return rewriteCommand(file, awkVars("#", pattern, true), program, file);
}

function activeLinesCommand(file) {
    return `grep -v '^[[:space:]]*\\(//\\|#\\|--\\)' ${file} 2>/dev/null`;
}

// Only core reads TOML the way Mango does, vars and nested sources included.
function tomlIncludedCommand(fragment, dmsBin) {
    return `${shQuote(dmsBin || "dms")} config resolve-include mangowc ${shQuote(fragment)} 2>/dev/null | grep -Fq '"included":true'`;
}

function buildRepairScript(options) {
    const configFile = options.configFile;
    const backupFile = options.backupFile;
    const fragments = options.fragmentFiles || (options.fragmentFile ? [options.fragmentFile] : []);
    const includes = options.includes || [
        {
            grepPattern: options.grepPattern,
            includeLine: options.includeLine
        }
    ];

    const commands = [];
    if (backupFile)
        commands.push(`cp ${shQuote(configFile)} ${shQuote(backupFile)} 2>/dev/null || true`);

    const dirs = {};
    for (const fragment of fragments)
        dirs[dirname(fragment)] = true;
    for (const dir in dirs)
        commands.push(`mkdir -p ${shQuote(dir)}`);
    if (fragments.length > 0)
        commands.push("touch " + fragments.map(shQuote).join(" "));

    for (const include of includes) {
        if (!(include.grepPattern || include.tomlFragment) || !include.includeLine)
            continue;
        const sectionHeader = options.sectionHeader || sectionHeaderFor(include.includeLine);
        const file = shQuote(configFile);
        const active = activeLinesCommand(file);
        const included = include.tomlFragment ? tomlIncludedCommand(include.tomlFragment, options.dmsBin) : `${active} | grep -q ${shQuote(include.grepPattern)}`;
        const enable = include.linePattern ? `if ${enableCommand(file, commentTokenFor(include.includeLine), include.linePattern, include.tomlFragment)}; then :; el` : "";
        const managed = include.tomlFragment ? `grep -Fq 'dms/' ${file} 2>/dev/null` : `${active} | grep -q ${shQuote(managedIncludePatternFor(include.includeLine))}`;
        // The append must start on its own line, or a TOML [global] fuses with the last statement.
        commands.push(`if ! { ${included}; }; then ${enable}if grep -Fqx ${shQuote(sectionHeader)} ${file} 2>/dev/null || ${managed}; then { [ -z "$(tail -c 1 ${file})" ] || printf '\\n'; printf '%s\\n' ${shQuote(include.includeLine)}; } >> ${file}; elif [ -s ${file} ]; then printf '\\n%s\\n%s\\n' ${shQuote(sectionHeader)} ${shQuote(include.includeLine)} >> ${file}; else printf '%s\\n%s\\n' ${shQuote(sectionHeader)} ${shQuote(include.includeLine)} >> ${file}; fi; fi`);
    }

    return commands.join("; ");
}

const compositorDirs = {
    niri: "niri",
    hyprland: "hypr",
    mango: "mango"
};

const configNames = {
    niri: "config.kdl",
    hyprland: "hyprland.lua",
    mango: "config.conf"
};

const fragmentExtensions = {
    niri: "kdl",
    hyprland: "lua",
    mango: "conf"
};

// linePattern is the awk regex for a line that holds only the include, used to comment it out and back in;
// a line with another statement on it is left alone, since commenting it would drop that statement too.
const kdlInclude = name => ({
            grepPattern: `include.*"dms/${name}.kdl"`,
            includeLine: `include "dms/${name}.kdl"`,
            linePattern: `^[[:space:]]*include[[:space:]][^"]*"([^"]*/)?dms/${name}[.]kdl"[^;"{]*$`
        });

const luaInclude = name => ({
            grepPattern: `dms.${name}`,
            includeLine: `require("dms.${name}")`,
            linePattern: `^[[:space:]]*require[[:space:]]*[(]?[[:space:]]*["']dms[.]${name}["'][[:space:]]*[)]?[[:space:]]*;?[[:space:]]*(--.*)?$`
        });

const confInclude = (name, grepPattern, includeLine) => ({
            grepPattern: grepPattern ?? `source.*dms/${name}.conf`,
            includeLine: includeLine ?? `source=./dms/${name}.conf`,
            linePattern: `^[[:space:]]*source[[:space:]]*=[^#]*dms/${name}[.]conf([[:space:]]+#.*)?[[:space:]]*$`
        });

// Each include brings its own [global], so tables appended after it cannot capture it.
// The pattern also takes one element of a multi-line source array, as the shipped config.toml has.
const tomlInclude = fragment => ({
            tomlFragment: fragment,
            includeLine: `[global]\nsource = "./dms/${fragment}"`,
            elementPattern: `["']([^"']*/)?dms/${fragment.replace(".", "[.]")}["']`,
            linePattern: `^[[:space:]]*(source[[:space:]]*=[[:space:]]*)?["']([^"']*/)?dms/${fragment.replace(".", "[.]")}["'][[:space:]]*,?[[:space:]]*(#.*)?$`
        });

const includeTable = {
    outputs: {
        niri: [kdlInclude("outputs")],
        hyprland: [luaInclude("outputs")],
        mango: [confInclude("outputs")]
    },
    layout: {
        niri: [kdlInclude("layout")],
        hyprland: [luaInclude("layout")],
        mango: [confInclude("layout")]
    },
    input: {
        niri: [kdlInclude("input")],
        hyprland: [luaInclude("input")],
        mango: [confInclude("input")]
    },
    windowrules: {
        niri: [kdlInclude("windowrules")],
        hyprland: [luaInclude("windowrules")],
        mango: [confInclude("windowrules", "dms/windowrules.conf")]
    },
    cursor: {
        niri: [kdlInclude("cursor")],
        hyprland: [luaInclude("cursor")],
        mango: [confInclude("cursor")]
    },
    animations: {
        niri: [kdlInclude("animations")],
        hyprland: [luaInclude("animations")],
        mango: [confInclude("animations")]
    },
    binds: {
        niri: [kdlInclude("binds")],
        hyprland: [luaInclude("binds"), luaInclude("binds-user")],
        mango: [confInclude("binds", undefined, "source = ./dms/binds.conf")]
    }
};

const fragmentNameTable = {
    binds: {
        hyprland: ["binds", "binds-user"]
    }
};

function includeSpec(kind, compositor, configName) {
    const includes = includeTable[kind]?.[compositor];
    if (!includes)
        return null;
    const extension = fragmentExtensions[compositor];
    const fragmentNames = (fragmentNameTable[kind]?.[compositor] ?? [kind]).map(name => `${name}.${extension}`);
    const name = configName || configNames[compositor];
    return {
        configName: name,
        fragmentNames: fragmentNames,
        includes: name.endsWith(".toml") ? fragmentNames.map(tomlInclude) : includes
    };
}

function includePaths(kind, compositor, configDir, configName) {
    const spec = includeSpec(kind, compositor, configName);
    if (!spec)
        return null;
    const dir = configDir + "/" + compositorDirs[compositor];
    return {
        configFile: dir + "/" + spec.configName,
        fragmentFiles: spec.fragmentNames.map(name => dir + "/dms/" + name),
        includes: spec.includes
    };
}

function repairScriptFor(kind, compositor, configDir, backupFile, configName, dmsBin) {
    const paths = includePaths(kind, compositor, configDir, configName);
    if (!paths)
        return "";
    return buildRepairScript({
        configFile: paths.configFile,
        backupFile: backupFile,
        fragmentFiles: paths.fragmentFiles,
        includes: paths.includes,
        dmsBin: dmsBin
    });
}

function disableScriptFor(kind, compositor, configDir, backupFile, configName) {
    const paths = includePaths(kind, compositor, configDir, configName);
    if (!paths)
        return "";
    const file = shQuote(paths.configFile);
    const pattern = paths.includes.map(include => "(" + include.linePattern + ")").join("|");
    const elements = paths.includes.filter(include => include.elementPattern).map(include => "(" + include.elementPattern + ")").join("|");
    const split = elements ? splitArrayCommand(file, elements) + "; " : "";
    const disable = split + disableCommand(file, commentTokenFor(paths.includes[0].includeLine), pattern, elements !== "");
    if (!backupFile)
        return disable;
    return `cp ${file} ${shQuote(backupFile)} 2>/dev/null || true; ${disable}`;
}

// Exits 0 when the config still holds an include Stop managing commented out.
function optedOutScriptFor(kind, compositor, configDir, configName) {
    const paths = includePaths(kind, compositor, configDir, configName);
    if (!paths)
        return "false";
    const pattern = paths.includes.map(include => "(" + include.linePattern + ")").join("|");
    const toml = paths.includes.some(include => include.tomlFragment);
    const program = tablePrefix + "{ r = substr($0, length(c) + 2) } ok && index($0, c \" \") == 1 && r !~ cm && r ~ re { found = 1 } END { exit !found }";
    return `awk ${awkVars(commentTokenFor(paths.includes[0].includeLine), pattern, toml)} ${shQuote(program)} ${shQuote(paths.configFile)}`;
}

function resolveIncludeArgs(kind, compositor) {
    const spec = includeSpec(kind, compositor);
    if (!spec)
        return null;
    return [compositor === "mango" ? "mangowc" : compositor, spec.fragmentNames[0]];
}
