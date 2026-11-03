.pragma library
.import "./SessionSpec.js" as SpecModule
.import "../../DCommon/Common/settings/SpecUtil.js" as Util

function parse(root, jsonObj) {
    var SPEC = SpecModule.SPEC;

    if (!jsonObj)
        return;

    for (var k in SPEC) {
        if (!(k in jsonObj)) {
            root[k] = Util.cloneDef(SPEC[k].def);
        }
    }

    for (var k in jsonObj) {
        if (!SPEC[k])
            continue;
        var raw = jsonObj[k];
        var spec = SPEC[k];
        var coerce = spec.coerce;
        root[k] = coerce ? (coerce(raw) !== undefined ? coerce(raw) : root[k]) : raw;
    }
}

function toJson(root) {
    var SPEC = SpecModule.SPEC;
    var out = {};
    for (var k in SPEC) {
        if (SPEC[k].persist === false)
            continue;
        if (Util.isDefault(root[k], SPEC[k].def))
            continue;
        out[k] = root[k];
    }
    out.configVersion = root.sessionConfigVersion;
    return out;
}

function migrateToVersion(obj, targetVersion, settingsData) {
    if (!obj)
        return null;

    var session = JSON.parse(JSON.stringify(obj));
    var currentVersion = session.configVersion || 0;

    if (currentVersion >= targetVersion) {
        return null;
    }

    if (currentVersion < 2) {
        console.info("SessionData: Migrating session from version", currentVersion, "to version 2");
        console.info("SessionData: Importing weather location and coordinates from settings");

        if (settingsData && typeof settingsData !== "undefined") {
            if (session.weatherLocation === undefined || session.weatherLocation === "New York, NY") {
                var settingsWeatherLocation = settingsData._legacyWeatherLocation;
                if (settingsWeatherLocation && settingsWeatherLocation !== "New York, NY") {
                    session.weatherLocation = settingsWeatherLocation;
                    console.info("SessionData: Migrated weatherLocation:", settingsWeatherLocation);
                }
            }

            if (session.weatherCoordinates === undefined || session.weatherCoordinates === "40.7128,-74.0060") {
                var settingsWeatherCoordinates = settingsData._legacyWeatherCoordinates;
                if (settingsWeatherCoordinates && settingsWeatherCoordinates !== "40.7128,-74.0060") {
                    session.weatherCoordinates = settingsWeatherCoordinates;
                    console.info("SessionData: Migrated weatherCoordinates:", settingsWeatherCoordinates);
                }
            }
        }

        session.configVersion = 2;
    }

    if (currentVersion < 3) {
        console.info("SessionData: Migrating session to version 3");
        session.configVersion = 3;
    }

    if (currentVersion < 4) {
        console.info("SessionData: Migrating session to version 4");
        console.info("SessionData: Dropping keys that match defaults; session.json now stores only changed values");

        Util.stripDefaults(session, SpecModule.SPEC);
        session.configVersion = 4;
    }

    if (currentVersion < 5) {
        console.info("SessionData: Migrating session to version 5");
        console.info("SessionData: Dropping keys that no longer have a consumer");
        delete session.nightModeLocationProvider;
        delete session.settingsSidebarExpandedIds;
        delete session.settingsSidebarCollapsedIds;
        session.configVersion = 5;
    }

    if (currentVersion < 6) {
        session.dockPins = session.dockPins || {
            dock: session.pinnedApps || []
        };
        delete session.pinnedApps;
        delete session.dockLauncherPosition;
        session.configVersion = 6;
    }

    if (currentVersion < 7) {
        console.info("SessionData: Migrating session to version 7");
        console.info("SessionData: Tray keys now use a stable id (or id::instance) instead of id::tooltipTitle");

        function stripTrayKeys(list) {
            if (!list || list.constructor !== Array)
                return list;
            var out = [];
            for (var i = 0; i < list.length; i++) {
                var raw = list[i];
                if (typeof raw !== "string")
                    continue;
                var key = raw.includes("::") ? raw.split("::")[0] : raw;
                var hasDup = false;
                for (var j = 0; j < out.length; j++) {
                    if (out[j] === key) {
                        hasDup = true;
                        break;
                    }
                }
                if (key && !hasDup)
                    out.push(key);
            }
            return out;
        }

        if (session.hiddenTrayIds !== undefined)
            session.hiddenTrayIds = stripTrayKeys(session.hiddenTrayIds);
        if (session.trayItemOrder !== undefined)
            session.trayItemOrder = stripTrayKeys(session.trayItemOrder);
        session.configVersion = 7;
    }
    return session;
}
