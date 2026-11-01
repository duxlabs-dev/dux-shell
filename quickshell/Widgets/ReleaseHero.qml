import QtQuick
import qs.Services
import qs.DCommon.Widgets

DHeroCard {
    brand: "dms"
    accent: {
        const semver = ShellVersionService.semverVersion.replace(/^v/, "");
        const base = semver.match(/^\d+\.\d+/);
        return base ? base[0] : semver || SystemUpdateService.shellRunning.replace(/^v/, "");
    }
    caption: ShellVersionService.shellCodename
    symbol: "He"
    atomicNumber: 2
    atomicMass: "4.0026"
}
