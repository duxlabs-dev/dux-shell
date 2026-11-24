import QtCore
import QtQuick
import qs.Common
import qs.Services
import "../../../Common/ConfigIncludeResolve.js" as ConfigIncludeResolve

QtObject {
    id: root

    required property string includeKind
    property string procTag: includeKind + "-include"
    property bool autoCheck: true
    property string warningCategory: "hyprland-migration"
    property var status: defaultStatus()
    property bool checking: false
    property bool fixing: false
    property bool disabling: false

    readonly property bool compositorSupported: ConfigIncludeResolve.includeSpec(includeKind, CompositorService.compositor) !== null
    readonly property bool included: status.included === true
    readonly property bool readOnly: CompositorService.isHyprland && !HyprlandService.luaConfigActive
    readonly property string fragmentLabel: "dms/" + includeKind

    signal fixed
    signal disabled

    function defaultStatus() {
        return {
            "exists": false,
            "included": false
        };
    }

    function applyStatus(dmsStatus) {
        if (!dmsStatus)
            return;
        status = {
            "exists": dmsStatus.exists,
            "included": dmsStatus.included
        };
    }

    function configDir() {
        return Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
    }

    function check(done) {
        const args = ConfigIncludeResolve.resolveIncludeArgs(includeKind, CompositorService.compositor);
        if (!args) {
            status = defaultStatus();
            return;
        }
        checking = true;
        Proc.runCommand("check-" + procTag, [Proc.dmsBin, "config", "resolve-include", ...args], (output, exitCode) => {
            checking = false;
            status = defaultStatus();
            if (exitCode === 0) {
                try {
                    status = JSON.parse(output.trim());
                } catch (e) {}
            }
            done?.();
        });
    }

    function showReadOnlyWarning() {
        ToastService.showWarning(I18n.tr("%1 not found").arg("hyprland.lua"), I18n.tr("Run %1 to create it before changing these settings.", "hyprland.lua missing warning, %1 is a command").arg("dms setup"), "dms setup", warningCategory);
    }

    function configPaths() {
        const mango = CompositorService.compositor === "mango";
        return {
            "dir": mango ? MangoService.configDir : configDir(),
            "configName": mango ? MangoService.configName : ""
        };
    }

    function disable() {
        if (readOnly || disabling)
            return;
        const { dir, configName } = configPaths();
        const paths = ConfigIncludeResolve.includePaths(includeKind, CompositorService.compositor, dir, configName);
        if (!paths)
            return;
        const unixTime = Math.floor(Date.now() / 1000);
        const script = ConfigIncludeResolve.disableScriptFor(includeKind, CompositorService.compositor, dir, paths.configFile + ".backup" + unixTime, configName);
        disabling = true;
        Proc.runCommand("disable-" + procTag, ["sh", "-c", script], () => {
            if (CompositorService.isHyprland)
                HyprlandService.reloadConfig();
            else if (CompositorService.isMango)
                MangoService.reloadConfig(false);
            check(() => {
                disabling = false;
                if (included)
                    ToastService.showWarning(I18n.tr("%1 is still included", "stop managing failed, %1 is a dms config file").arg(fragmentLabel), I18n.tr("Remove its include from your compositor config by hand.", "stop managing failed toast body"), "", warningCategory);
                disabled();
            });
        });
    }

    function fix() {
        if (readOnly) {
            showReadOnlyWarning();
            return;
        }
        const compositor = CompositorService.compositor;
        const { dir, configName } = configPaths();
        const paths = ConfigIncludeResolve.includePaths(includeKind, compositor, dir, configName);
        if (!paths)
            return;
        const unixTime = Math.floor(Date.now() / 1000);
        const script = ConfigIncludeResolve.repairScriptFor(includeKind, compositor, dir, paths.configFile + ".backup" + unixTime, configName, Proc.dmsBin);
        fixing = true;
        Proc.runCommand("fix-" + procTag, ["sh", "-c", script], (output, exitCode) => {
            fixing = false;
            if (exitCode !== 0)
                return;
            if (autoCheck)
                check();
            fixed();
        });
    }

    Component.onCompleted: {
        if (autoCheck && compositorSupported)
            check();
    }
}
