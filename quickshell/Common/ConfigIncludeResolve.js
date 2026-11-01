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
        const managed = include.tomlFragment ? `grep -Fq 'dms/' ${file} 2>/dev/null` : `${active} | grep -q ${shQuote(managedIncludePatternFor(include.includeLine))}`;
        // The append must start on its own line, or a TOML [global] fuses with the last statement.
        commands.push(`if ! { ${included}; }; then if grep -Fqx ${shQuote(sectionHeader)} ${file} 2>/dev/null || ${managed}; then { [ -z "$(tail -c 1 ${file})" ] || printf '\\n'; printf '%s\\n' ${shQuote(include.includeLine)}; } >> ${file}; elif [ -s ${file} ]; then printf '\\n%s\\n%s\\n' ${shQuote(sectionHeader)} ${shQuote(include.includeLine)} >> ${file}; else printf '%s\\n%s\\n' ${shQuote(sectionHeader)} ${shQuote(include.includeLine)} >> ${file}; fi; fi`);
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

const kdlInclude = name => ({
            grepPattern: `include.*"dms/${name}.kdl"`,
            includeLine: `include "dms/${name}.kdl"`
        });

const luaInclude = name => ({
            grepPattern: `dms.${name}`,
            includeLine: `require("dms.${name}")`
        });

const confInclude = (name, grepPattern, includeLine) => ({
            grepPattern: grepPattern ?? `source.*dms/${name}.conf`,
            includeLine: includeLine ?? `source=./dms/${name}.conf`
        });

// Each include brings its own [global], so tables appended after it cannot capture it.
const tomlInclude = fragment => ({
            tomlFragment: fragment,
            includeLine: `[global]\nsource = "./dms/${fragment}"`
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

function resolveIncludeArgs(kind, compositor) {
    const spec = includeSpec(kind, compositor);
    if (!spec)
        return null;
    return [compositor === "mango" ? "mangowc" : compositor, spec.fragmentNames[0]];
}
