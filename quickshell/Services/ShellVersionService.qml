pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string shellVersion: ""
    property string shellCodename: ""
    property string semverVersion: ""

    function getParsedShellVersion() {
        return parseVersion(semverVersion);
    }

    Process {
        id: versionDetection
        running: true
        command: ["sh", "-c", `cd "${Quickshell.shellDir}" || exit 0
semver=$(cat VERSION 2>/dev/null); codename=$(cat CODENAME 2>/dev/null)
if [ -d .git ]; then shell="(git) $(git rev-parse --short HEAD)"; else shell=$semver; fi
printf '%s\\n%s\\n%s\\n' "$shell" "$semver" "$codename"`]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                shellVersion = (lines[0] || "").trim();
                semverVersion = (lines[1] || "").trim();
                shellCodename = (lines[2] || "").trim();
            }
        }
    }

    function parseVersion(versionStr) {
        if (!versionStr || typeof versionStr !== "string") {
            return {
                major: 0,
                minor: 0,
                patch: 0,
                prerelease: ""
            };
        }
        let v = versionStr.trim();
        if (v.startsWith("v")) {
            v = v.substring(1);
        }
        const plusIdx = v.indexOf("+");
        if (plusIdx !== -1) {
            v = v.substring(0, plusIdx);
        }
        let prerelease = "";
        const dashIdx = v.indexOf("-");
        if (dashIdx !== -1) {
            prerelease = v.substring(dashIdx + 1);
            v = v.substring(0, dashIdx);
        }
        const parts = v.split(".");
        return {
            major: parseInt(parts[0], 10) || 0,
            minor: parseInt(parts[1], 10) || 0,
            patch: parseInt(parts[2], 10) || 0,
            prerelease
        };
    }

    // Numeric core only; plugin requirements treat 1.7.0-beta as satisfying >=1.7.0.
    function compareVersions(v1, v2) {
        if (v1.major !== v2.major) {
            return v1.major - v2.major;
        }
        if (v1.minor !== v2.minor) {
            return v1.minor - v2.minor;
        }
        return v1.patch - v2.patch;
    }

    // SemVer ordering for release feeds: 1.7.0-beta.2 < 1.7.0-beta.10 < 1.7.0.
    function compareReleases(v1, v2) {
        const core = compareVersions(v1, v2);
        if (core !== 0)
            return core;
        const p1 = v1.prerelease || "";
        const p2 = v2.prerelease || "";
        if (p1 === p2)
            return 0;
        if (p1 === "")
            return 1;
        if (p2 === "")
            return -1;
        const a = p1.split(".");
        const b = p2.split(".");
        for (let i = 0; i < Math.max(a.length, b.length); i++) {
            if (a[i] === undefined)
                return -1;
            if (b[i] === undefined)
                return 1;
            const na = /^\d+$/.test(a[i]);
            const nb = /^\d+$/.test(b[i]);
            if (na && nb) {
                if (a[i] !== b[i])
                    return parseInt(a[i], 10) - parseInt(b[i], 10);
                continue;
            }
            if (na !== nb)
                return na ? -1 : 1;
            if (a[i] !== b[i])
                return a[i] < b[i] ? -1 : 1;
        }
        return 0;
    }

    function checkVersionRequirement(requirementStr, currentVersion) {
        if (!requirementStr || typeof requirementStr !== "string") {
            return true;
        }
        const req = requirementStr.trim();
        let operator = ">=";
        let versionPart = req;
        switch (true) {
        case req.startsWith(">="):
            operator = ">=";
            versionPart = req.substring(2);
            break;
        case req.startsWith("<="):
            operator = "<=";
            versionPart = req.substring(2);
            break;
        case req.startsWith(">"):
            operator = ">";
            versionPart = req.substring(1);
            break;
        case req.startsWith("<"):
            operator = "<";
            versionPart = req.substring(1);
            break;
        case req.startsWith("="):
            operator = "=";
            versionPart = req.substring(1);
            break;
        }

        const reqVersion = parseVersion(versionPart);
        const cmp = compareVersions(currentVersion, reqVersion);
        switch (operator) {
        case ">=":
            return cmp >= 0;
        case ">":
            return cmp > 0;
        case "<=":
            return cmp <= 0;
        case "<":
            return cmp < 0;
        case "=":
            return cmp === 0;
        default:
            return cmp >= 0;
        }
    }
}
