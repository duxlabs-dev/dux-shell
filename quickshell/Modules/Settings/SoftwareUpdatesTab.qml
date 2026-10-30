pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modals.Common
import qs.Modules.Settings.Widgets
import qs.Modules.SystemUpdate
import qs.Widgets
import "../../Common/Format.js" as Format

Item {
    id: root

    property var parentModal: null

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Ref {
        service: SystemUpdateService
        modules: ["releases"]
    }

    readonly property var intervalOptions: [
        {
            label: I18n.tr("Every %1", "update check interval option, %1 is a duration such as 30 minutes").arg(I18n.duration(900)),
            seconds: 900
        },
        {
            label: I18n.tr("Every %1", "update check interval option, %1 is a duration such as 30 minutes").arg(I18n.duration(1800)),
            seconds: 1800
        },
        {
            label: I18n.tr("Every hour"),
            seconds: 3600
        },
        {
            label: I18n.tr("Every %1", "update check interval option, %1 is a duration such as 30 minutes").arg(I18n.duration(14400)),
            seconds: 14400
        },
        {
            label: I18n.tr("Once a day"),
            seconds: 86400
        },
        {
            label: I18n.tr("Never"),
            seconds: 0
        }
    ]

    readonly property string customIntervalLabel: I18n.tr("Custom")
    property bool customIntervalSelected: false
    property bool packagesExpanded: false
    property int nowUnix: Math.floor(Date.now() / 1000)

    readonly property int packageListCap: 60
    readonly property int logTailLines: 20
    readonly property real logViewHeight: Theme.listItemHeight * 5
    readonly property bool upgradeRunsInTerminal: SystemUpdateService.useCustomCommand || (SystemUpdateService.backends || []).some(b => b.runsInTerminal === true)
    readonly property bool upgradeInWindow: SettingsData.updaterUpgradeInWindow && !upgradeRunsInTerminal
    readonly property int systemCount: SystemUpdateService.systemUpdates.length
    readonly property int flatpakCount: SystemUpdateService.systemUpdates.filter(p => p.repo === "flatpak").length
    readonly property bool busy: SystemUpdateService.isChecking || SystemUpdateService.isUpgrading
    // A refresh clears the log, so a log next to an error means the upgrade itself failed.
    readonly property bool upgradeFailed: SystemUpdateService.hasError && !busy && (SystemUpdateService.recentLog || []).length > 0
    readonly property var installablePackages: SystemUpdateService.availableUpdates
    readonly property bool anythingToInstall: installablePackages.length > 0 && SystemUpdateService.helperAvailable
    readonly property var notesRelease: SystemUpdateService.notesRelease
    readonly property int serviceLastCheckUnix: SystemUpdateService.lastCheckUnix

    onServiceLastCheckUnixChanged: nowUnix = Math.floor(Date.now() / 1000)

    Component.onCompleted: {
        customIntervalSelected = !intervalOptions.some(o => o.seconds === SettingsData.updaterIntervalSeconds);
        nowUnix = Math.floor(Date.now() / 1000);
    }

    readonly property var notifyOptions: [
        {
            label: I18n.tr("Every check", "update notification frequency option, notify on every check"),
            seconds: 0
        },
        {
            label: I18n.tr("Every hour"),
            seconds: 3600
        },
        {
            label: I18n.tr("Every %1", "update check interval option, %1 is a duration such as 30 minutes").arg(I18n.duration(4 * 3600)),
            seconds: 4 * 3600
        },
        {
            label: I18n.tr("Once a day"),
            seconds: 86400
        },
        {
            label: I18n.tr("Once a week", "update notification frequency option"),
            seconds: 7 * 86400
        }
    ]

    function intervalLabelFor(seconds) {
        for (const opt of intervalOptions) {
            if (opt.seconds === seconds)
                return opt.label;
        }
        return customIntervalLabel;
    }

    function intervalSecondsFor(label) {
        for (const opt of intervalOptions) {
            if (opt.label === label)
                return opt.seconds;
        }
        return 86400;
    }

    function lastCheckedText() {
        const last = SystemUpdateService.lastCheckUnix;
        if (!last)
            return "";
        const delta = Math.max(0, nowUnix - last);
        if (delta < 90)
            return I18n.tr("checked just now");
        if (delta < 3600)
            return I18n.tr("checked %1m ago", "system update last check time, %1 is minutes").arg(Math.round(delta / 60));
        if (delta < 86400)
            return I18n.tr("checked %1h ago", "system update last check time, %1 is hours").arg(Math.round(delta / 3600));
        return I18n.tr("checked %1d ago", "system update last check time, %1 is days").arg(Math.round(delta / 86400));
    }

    function countText(count) {
        return count === 1 ? I18n.tr("%1 update", "singular, %1 is 1, available system update count").arg(count) : I18n.tr("%1 updates", "plural, %1 is a count of available system updates").arg(count);
    }

    function installMethodLabel() {
        switch (SystemUpdateService.shellInstallMethod) {
        case "pacman":
        case "rpm":
        case "dpkg":
        case "xbps":
            return SystemUpdateService.shellPackageName || SystemUpdateService.shellInstallMethod;
        case "nix":
            return "Nix";
        default:
            return "";
        }
    }

    function channelLabel() {
        switch (SystemUpdateService.shellChannel) {
        case "stable":
            return I18n.tr("Stable", "release channel");
        case "git":
            return I18n.tr("Git", "release channel that follows the master branch");
        default:
            return I18n.tr("Unknown");
        }
    }

    function statusTitle() {
        switch (true) {
        case !SystemUpdateService.sysupdateAvailable:
            return I18n.tr("Unavailable");
        case SystemUpdateService.isUpgrading:
            return I18n.tr("Upgrading...", "system update popout status while packages upgrade");
        case SystemUpdateService.isChecking:
            return I18n.tr("Checking for updates...");
        case SystemUpdateService.hasError:
            return I18n.tr("Failed: %1", "system update error status, %1 is the error message").arg(SystemUpdateService.errorMessage);
        case !SystemUpdateService.helperAvailable:
            return I18n.tr("No supported package manager found.");
        case SystemUpdateService.shellUpdateAvailable:
            {
                const shell = I18n.tr("DMS %1 available", "software updates hero, %1 is the new DMS version").arg(SystemUpdateService.shellUpdateVersion);
                return root.systemCount > 0 ? shell + " · " + root.countText(root.systemCount) : shell;
            }
        case root.systemCount > 0:
            return root.countText(root.systemCount);
        default:
            return I18n.tr("Up to date");
        }
    }

    function statusSubtitle() {
        if (SystemUpdateService.rebootRecommended)
            return I18n.tr("Reboot recommended", "chip shown after a kernel or systemd upgrade") + " · " + SystemUpdateService.rebootPackages.join(", ");
        if (SystemUpdateService.restartPending)
            return I18n.tr("Requires restart");
        return root.lastCheckedText();
    }

    readonly property bool offerReboot: SystemUpdateService.rebootRecommended && !SystemUpdateService.isUpgrading && !root.anythingToInstall
    readonly property bool needsRestart: SystemUpdateService.restartPending || SystemUpdateService.rebootRecommended
    readonly property bool primaryIsCheck: !SystemUpdateService.isUpgrading && !root.anythingToInstall && !root.needsRestart

    function primaryLabel() {
        switch (true) {
        case SystemUpdateService.isUpgrading:
            return I18n.tr("Cancel");
        case root.anythingToInstall:
            return I18n.tr("Install", "install action button");
        case root.offerReboot:
            return I18n.tr("Reboot", "verb, power menu action");
        case SystemUpdateService.restartPending:
            return I18n.tr("Restart DMS");
        default:
            return I18n.tr("Check for updates");
        }
    }

    function primaryIcon() {
        switch (true) {
        case SystemUpdateService.isUpgrading:
            return "stop";
        case root.anythingToInstall:
            return "system_update_alt";
        case root.offerReboot:
        case SystemUpdateService.restartPending:
            return "restart_alt";
        default:
            return "refresh";
        }
    }

    function primaryAction() {
        switch (true) {
        case SystemUpdateService.isUpgrading:
            SystemUpdateService.cancelUpdates();
            return;
        case root.anythingToInstall:
            installConfirm.showWithOptions({
                title: I18n.tr("Install system updates?", "confirmation dialog title before running the system upgrade"),
                message: root.installSummary(),
                confirmText: I18n.tr("Install", "install action button"),
                confirmByDefault: true,
                onConfirm: () => root.runUpdateAll()
            });
            return;
        case root.offerReboot:
            installConfirm.showWithOptions({
                title: I18n.tr("Reboot now?", "confirmation dialog title, reboot to finish a system update"),
                message: I18n.tr("Save your work first. Open apps will close.", "reboot confirmation after a system update"),
                confirmText: I18n.tr("Reboot", "verb, power menu action"),
                onConfirm: () => SessionService.reboot()
            });
            return;
        case SystemUpdateService.restartPending:
            SystemUpdateService.restartShell();
            return;
        default:
            SystemUpdateService.checkForUpdates();
        }
    }

    function installSummary() {
        const pkgs = root.installablePackages;
        const bytes = pkgs.reduce((sum, p) => sum + (p.sizeBytes || 0), 0);
        const via = SystemUpdateService.useCustomCommand ? SettingsData.updaterCustomCommand.trim().split(/\s+/)[0] : (SystemUpdateService.backends || []).filter(b => pkgs.some(p => p.backend === b.id)).map(b => b.displayName).join(", ");
        let text;
        if (bytes > 0)
            text = I18n.tr("%1 will be downloaded and installed via %2.", "system update confirmation, %1 is a download size, %2 the package managers").arg(Format.formatBytes(bytes)).arg(via);
        else if (pkgs.length === 1)
            text = I18n.tr("%1 package will be installed via %2.", "singular, %1 is 1, %2 the package managers").arg(1).arg(via);
        else
            text = I18n.tr("%1 packages will be installed via %2.", "plural, %1 is a package count, %2 the package managers").arg(pkgs.length).arg(via);
        if (!root.upgradeRunsInTerminal)
            return text;
        return text + " " + I18n.tr("Runs in a terminal.", "system update confirmation, the upgrade opens a terminal window");
    }

    function runUpdateAll(interactive) {
        SystemUpdateService.runUpdates({
            includeFlatpak: SettingsData.updaterIncludeFlatpak,
            includeAUR: SettingsData.updaterAllowAUR,
            terminal: SessionData.terminalOverride,
            interactive: interactive === true
        });
        packagesExpanded = false;
        followUpgradeLog = true;
        if (upgradeInWindow && interactive !== true)
            PopoutService.showSystemUpdateModal();
    }

    property bool followUpgradeLog: false
    readonly property bool upgrading: SystemUpdateService.isUpgrading

    onUpgradingChanged: {
        if (!upgrading)
            followUpgradeLog = false;
    }

    function revealUpgradeLog() {
        if (!followUpgradeLog || !upgradeLogRow.visible)
            return;
        const top = upgradeLogRow.mapToItem(mainColumn.contentItem, 0, 0).y;
        mainColumn.revealRange(top, top + upgradeLogRow.height);
    }

    SettingsPage {
        id: mainColumn

        onContentHeightChanged: root.revealUpgradeLog()

        ReleaseHero {
            M3WaveProgress {
                width: parent.width
                height: Theme.spacingM
                visible: SystemUpdateService.isUpgrading
                isPlaying: visible
                value: 1
                trackColor: "transparent"
                playheadColor: "transparent"
            }
        }

        SettingsCard {
            width: parent.width
            title: "Dux Shell"
            iconName: "deployed_code"
            settingKey: "softwareUpdatesShell"
            tags: ["dms", "shell", "version", "channel", "restart"]

            SettingsRow {
                readonly property bool failed: SystemUpdateService.hasError && !root.busy

                title: root.statusTitle()
                titleColor: failed ? Theme.error : contentColor
                subtitle: root.statusSubtitle()
                iconName: failed ? "error_outline" : root.needsRestart ? "restart_alt" : "system_update_alt"
                iconColor: failed ? Theme.error : root.needsRestart ? Theme.warning : Theme.primary

                DActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: SystemUpdateService.sysupdateAvailable && !root.primaryIsCheck
                    enabled: !root.busy
                    buttonSize: Theme.buttonHeightS
                    iconName: "refresh"
                    iconColor: Theme.surfaceText
                    backgroundColor: SettingsMetrics.controlSurface
                    tooltipText: I18n.tr("Check for updates")
                    onClicked: SystemUpdateService.checkForUpdates()
                }

                DButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: SystemUpdateService.sysupdateAvailable
                    buttonHeight: Theme.buttonHeightS
                    text: root.primaryLabel()
                    iconName: root.primaryIcon()
                    busy: SystemUpdateService.isChecking
                    enabled: !SystemUpdateService.isChecking
                    backgroundColor: Theme.primary
                    textColor: Theme.onPrimary
                    onClicked: root.primaryAction()
                }
            }

            SettingsRow {
                title: I18n.tr("Version")
                iconName: "tag"
                subtitle: {
                    const running = SystemUpdateService.shellRunning || ShellVersionService.shellVersion;
                    const to = SystemUpdateService.shellUpdateVersion;
                    if (to)
                        return running + " → " + to;
                    return running;
                }
                trailingBadge: root.installMethodLabel()
            }

            SettingsRow {
                title: I18n.tr("Channel")
                iconName: "alt_route"
                subtitle: root.channelLabel()
                trailingBadge: SystemUpdateService.shellManagedExternally ? I18n.tr("Managed by Nix", "badge on the DMS update row when the shell is installed through Nix") : ""
            }

            SettingsRow {
                readonly property var master: SystemUpdateService.releases?.master ?? null

                visible: SystemUpdateService.shellChannel === "git" && SystemUpdateService.commitsBehind >= 0
                title: I18n.tr("Master branch", "git channel row, the branch the build tracks")
                subtitle: {
                    const date = new Date(master?.date ?? NaN);
                    return isNaN(date) ? "" : I18n.tr("Last commit %1", "git channel row, %1 is a localized date").arg(date.toLocaleDateString(Qt.locale(), Locale.ShortFormat));
                }
                iconName: "commit"

                // Drawn in the slot so it precedes the button; trailingBadge would land after it
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: SystemUpdateService.commitsBehind === 0 ? I18n.tr("Up to date") : I18n.tr("%1 behind", "git channel badge, %1 is the number of commits master is ahead").arg(SystemUpdateService.commitsBehind)
                    font.pixelSize: Theme.fontSizeSmall
                    color: SystemUpdateService.commitsBehind === 0 ? Theme.surfaceVariantText : Theme.primary
                }

                DActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: Theme.buttonHeightS
                    iconName: "open_in_browser"
                    iconColor: Theme.primary
                    backgroundColor: SettingsMetrics.controlSurface
                    tooltipText: I18n.tr("View on GitHub", "link to the release on GitHub")
                    onClicked: Qt.openUrlExternally("https://github.com/duxlabs-dev/dux-shell/commits/master")
                }
            }

            SettingsNavRow {
                visible: root.notesRelease !== null
                title: I18n.tr("Release notes", "settings page and card title, notes for a DMS release")
                iconName: "article"
                hint: root.notesRelease?.codename ? "v" + root.notesRelease.version + " · " + root.notesRelease.codename : "v" + (root.notesRelease?.version ?? "")
                onClicked: keyboard => root.parentModal?.navigateTo("updater_changelog", keyboard)
            }

            SettingsRow {
                visible: SystemUpdateService.restartPending
                title: I18n.tr("Requires restart")
                iconName: "restart_alt"
                iconColor: Theme.warning
                subtitle: SystemUpdateService.shellInstalled ? I18n.tr("Installed %1, still running %2", "%1 is the installed version, %2 the running one").arg(SystemUpdateService.shellInstalled).arg(SystemUpdateService.shellRunning) : I18n.tr("A newer dms binary is installed.", "software updates row subtitle, the running shell is older than the installed binary")
            }

            SettingsRow {
                visible: SystemUpdateService.legacyRepos.length > 0
                title: I18n.tr("Package repositories moved", "notification title, the DMS package repositories moved to a new owner")
                subtitle: I18n.tr("Run %1 in a terminal.", "%1 is a shell command").arg(SystemUpdateService.migrateCommand)
                iconName: "swap_horiz"
                iconColor: Theme.warning

                DActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: Theme.buttonHeightS
                    iconName: "content_copy"
                    iconColor: Theme.surfaceText
                    backgroundColor: SettingsMetrics.controlSurface
                    tooltipText: I18n.tr("Copy")
                    onClicked: {
                        Quickshell.execDetached(["dms", "cl", "copy", SystemUpdateService.migrateCommand]);
                        ToastService.showInfo(I18n.tr("Copied to clipboard"));
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: SystemUpdateService.sysupdateAvailable
            title: I18n.tr("System packages", "software updates card title, package manager updates")
            iconName: "inventory_2"
            settingKey: "softwareUpdatesSystem"
            tags: ["system", "packages", "flatpak", "aur"]

            SettingsRow {
                title: {
                    if (!SystemUpdateService.helperAvailable)
                        return I18n.tr("No supported package manager found.");
                    if (root.systemCount === 0)
                        return I18n.tr("Up to date");
                    const base = root.countText(root.systemCount);
                    return root.flatpakCount > 0 ? base + " · " + I18n.tr("%1 Flatpak", "count of flatpak updates, %1 is a number").arg(root.flatpakCount) : base;
                }
                subtitle: {
                    const distro = SystemUpdateService.distributionPretty || SystemUpdateService.distribution;
                    const names = (SystemUpdateService.backends || []).map(b => b.displayName).join(", ");
                    return distro && names ? distro + " · " + names : distro || names;
                }
                iconName: !SystemUpdateService.helperAvailable ? "error_outline" : root.systemCount === 0 ? "check_circle" : "package_2"
                iconColor: SystemUpdateService.helperAvailable ? Theme.primary : Theme.error
                clickable: root.systemCount > 0
                onClicked: root.packagesExpanded = !root.packagesExpanded

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.systemCount > 0
                    name: "expand_more"
                    size: Theme.iconSize
                    color: Theme.surfaceVariantText
                    rotation: root.packagesExpanded ? 180 : 0

                    Behavior on rotation {
                        enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                        }
                    }
                }
            }

            Column {
                width: parent?.width ?? 0
                spacing: SettingsMetrics.groupGap

                Repeater {
                    model: root.packagesExpanded && !SystemUpdateService.isUpgrading ? SystemUpdateService.systemUpdates.slice(0, root.packageListCap) : []

                    delegate: SettingsRow {
                        id: packageRow
                        required property var modelData

                        title: modelData.name || ""
                        subtitle: {
                            const from = modelData.fromVersion || "";
                            const to = modelData.toVersion || "";
                            const version = from && to ? from + " → " + to : to || from;
                            const repo = modelData.repo || "";
                            return repo && version ? repo + " · " + version : repo || version;
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "visibility_off"
                            visible: SystemUpdateService.canIgnorePackage(packageRow.modelData)
                            tooltipText: I18n.tr("Ignore package", "tooltip, exclude a package from system updates")
                            onClicked: SystemUpdateService.ignorePackage(packageRow.modelData.name)
                        }
                    }
                }
            }

            SettingsRow {
                visible: root.packagesExpanded && !SystemUpdateService.isUpgrading && root.systemCount > root.packageListCap
                title: I18n.tr("and %1 more", "%1 is the number of update rows not shown").arg(root.systemCount - root.packageListCap)
                titleColor: Theme.surfaceVariantText
            }

            SettingsRow {
                visible: root.upgradeInWindow && SystemUpdateService.isUpgrading
                title: I18n.tr("Upgrading...", "system update popout status while packages upgrade")
                iconName: "open_in_new"

                DButton {
                    anchors.verticalCenter: parent.verticalCenter
                    buttonHeight: Theme.buttonHeightS
                    text: I18n.tr("Show window", "button, brings back the floating system update window")
                    iconName: "open_in_new"
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: PopoutService.showSystemUpdateModal()
                }
            }

            SettingsRow {
                id: upgradeLogRow
                visible: (SystemUpdateService.isUpgrading && !root.upgradeInWindow) || (root.upgradeFailed && !root.upgradeRunsInTerminal)
                body: Item {
                    readonly property real lineHeight: logText.implicitHeight / Math.max(1, logText.lineCount)

                    width: parent.width
                    height: Math.min(logText.implicitHeight, Math.floor(root.logViewHeight / lineHeight) * lineHeight)
                    clip: true

                    UpgradeLogText {
                        id: logText
                        anchors.bottom: parent.bottom
                        width: parent.width
                        placeholder: root.upgradeRunsInTerminal ? I18n.tr("Running in terminal") : ""
                        lines: (SystemUpdateService.recentLog || []).slice(-root.logTailLines)
                    }
                }
            }

            SettingsRow {
                visible: SystemUpdateService.hasError && !root.busy
                title: I18n.tr("Failed: %1", "system update error status, %1 is the error message").arg(SystemUpdateService.errorMessage)
                titleColor: Theme.error
                subtitle: SystemUpdateService.errorHint
                iconName: "error_outline"
                iconColor: Theme.error

                DButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.upgradeFailed && !root.upgradeRunsInTerminal
                    text: I18n.tr("Open in terminal")
                    iconName: "terminal"
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: root.runUpdateAll(true)
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Options")
            iconName: "tune"
            settingKey: "systemUpdater"
            collapsible: true
            expanded: false

            SettingsDropdownRow {
                settingKey: "systemUpdaterCheckInterval"
                resetKeys: ["updaterIntervalSeconds"]
                resetByKeys: false
                onResetRequested: {
                    root.customIntervalSelected = false;
                    SettingsData.resetToDefault(["updaterIntervalSeconds"]);
                    SystemUpdateService.setInterval(SettingsData.updaterIntervalSeconds);
                }
                tags: ["interval", "poll", "frequency"]
                text: I18n.tr("Check interval")
                options: root.intervalOptions.map(o => o.label).concat([root.customIntervalLabel])
                currentValue: root.customIntervalSelected ? root.customIntervalLabel : root.intervalLabelFor(SettingsData.updaterIntervalSeconds)
                onValueChanged: label => {
                    if (label === root.customIntervalLabel) {
                        root.customIntervalSelected = true;
                        return;
                    }
                    root.customIntervalSelected = false;
                    const secs = root.intervalSecondsFor(label);
                    SettingsData.set("updaterIntervalSeconds", secs);
                    SystemUpdateService.setInterval(secs);
                }
            }

            SettingsTextFieldRow {
                id: customIntervalField
                leftIconName: "timer"
                visible: root.customIntervalSelected
                text: I18n.tr("Custom interval in minutes (minimum 5)")
                placeholderText: "1440"
                value: Math.round(SettingsData.updaterIntervalSeconds / 60).toString()
                validator: IntValidator {
                    bottom: 5
                }
                onValueEdited: value => {
                    const minutes = parseInt(value, 10);
                    if (isNaN(minutes) || minutes < 5)
                        return;
                    const seconds = minutes * 60;
                    SettingsData.set("updaterIntervalSeconds", seconds);
                    SystemUpdateService.setInterval(seconds);
                }
            }

            SettingsToggleRow {
                settingKey: "systemUpdaterCheckOnStart"
                tags: ["startup", "check", "boot"]
                text: I18n.tr("Check on startup")
                checked: SettingsData.updaterCheckOnStart
                onToggled: checked => SettingsData.set("updaterCheckOnStart", checked)
            }

            SettingsToggleRow {
                settingKey: "systemUpdaterPauseOnBattery"
                tags: ["battery", "power", "pause"]
                visible: BatteryService.batteryAvailable
                text: I18n.tr("Pause checks on battery", "software updates toggle, skip background checks on battery power")
                checked: SettingsData.updaterPauseOnBattery
                onToggled: checked => SettingsData.set("updaterPauseOnBattery", checked)
            }

            SettingsToggleRow {
                settingKey: "systemUpdaterNotify"
                tags: ["notify", "notification", "alert"]
                text: I18n.tr("Notify me on new updates", "software updates toggle")
                description: I18n.tr("Checks in the background at the check interval. Notifies only when the count grows.", "notify on new updates toggle description")
                checked: SettingsData.updaterNotify
                onToggled: checked => SettingsData.set("updaterNotify", checked)
            }

            SettingsDropdownRow {
                settingKey: "systemUpdaterNotifyMin"
                tags: ["notify", "notification", "frequency", "throttle"]
                resetKeys: ["updaterNotifyMinSeconds"]
                visible: SettingsData.updaterNotify
                text: I18n.tr("Notify at most", "software updates dropdown label, how often update notifications may repeat")
                options: root.notifyOptions.map(o => o.label)
                currentValue: (root.notifyOptions.find(o => o.seconds === SettingsData.updaterNotifyMinSeconds) ?? root.notifyOptions[root.notifyOptions.length - 1]).label
                onValueChanged: label => {
                    const opt = root.notifyOptions.find(o => o.label === label);
                    if (opt)
                        SettingsData.set("updaterNotifyMinSeconds", opt.seconds);
                }
            }

            SettingsToggleRow {
                settingKey: "systemUpdaterFlatpak"
                tags: ["flatpak", "include"]
                text: I18n.tr("Include Flatpak updates")
                visible: (SystemUpdateService.backends || []).some(b => b.repo === "flatpak")
                checked: SettingsData.updaterIncludeFlatpak
                onToggled: checked => SettingsData.set("updaterIncludeFlatpak", checked)
            }

            SettingsToggleRow {
                settingKey: "systemUpdaterAUR"
                tags: ["aur", "paru", "yay", "shelly"]
                text: I18n.tr("Include AUR updates")
                visible: (SystemUpdateService.backends || []).some(b => ["paru", "yay", "shelly"].includes(b.id))
                checked: SettingsData.updaterAllowAUR
                onToggled: checked => SettingsData.set("updaterAllowAUR", checked)
            }

            SettingsToggleRow {
                settingKey: "systemUpdaterReopenAfterUpgrade"
                tags: ["reopen", "popout", "terminal", "upgrade"]
                text: I18n.tr("Reopen panel after update")
                visible: root.upgradeRunsInTerminal
                checked: SettingsData.updaterReopenAfterUpgrade
                onToggled: checked => SettingsData.set("updaterReopenAfterUpgrade", checked)
            }

            SettingsToggleRow {
                settingKey: "systemUpdaterUpgradeInWindow"
                tags: ["window", "popout", "floating", "log", "output"]
                text: I18n.tr("Show upgrade in a window", "software updates toggle")
                description: I18n.tr("Opens a floating window with the live output", "show upgrade in a window toggle description")
                visible: !root.upgradeRunsInTerminal
                checked: SettingsData.updaterUpgradeInWindow
                onToggled: checked => SettingsData.set("updaterUpgradeInWindow", checked)
            }

            TerminalPickerRow {}
        }

        SettingsCard {
            id: ignoredPackagesCard
            width: parent.width
            iconName: "visibility_off"
            title: I18n.tr("Ignored packages")
            settingKey: "systemUpdaterIgnoredPackages"
            tags: ["system", "update", "package", "ignore"]
            collapsible: true
            expanded: false

            property bool errorIsInvalidName: false

            function addIgnoredPackage() {
                const name = newIgnoredPackageField.value.trim();
                if (name === "")
                    return;
                errorIsInvalidName = !SystemUpdateService.isValidIgnoredName(name);
                if (errorIsInvalidName) {
                    ignoredPackageError.visible = true;
                    return;
                }
                ignoredPackageError.visible = !SystemUpdateService.ignorePackage(name);
                if (ignoredPackageError.visible)
                    return;
                newIgnoredPackageField.value = "";
            }

            SettingsTextFieldRow {
                id: newIgnoredPackageField
                leftIconName: "inventory_2"
                text: I18n.tr("Name")
                description: {
                    if (SettingsData.updaterUseCustomCommand)
                        return I18n.tr("Ignored packages only apply to the built-in updater. Your custom command controls its own exclusions.");
                    if (SystemUpdateService.pkgManager === "shelly")
                        return I18n.tr("With Shelly, only Flatpak packages in the current update list can be ignored.");
                    return (SettingsData.updaterIgnoredPackages || []).length > 0 ? I18n.tr("Ignored packages are hidden from the updater and skipped by 'Update All'.") : I18n.tr("No packages ignored. Add one here or hover an update in the popout and click the hide button.");
                }
                placeholderText: I18n.tr("Package name (e.g., docker)")
                onAccepted: ignoredPackagesCard.addIgnoredPackage()
                onValueEdited: ignoredPackageError.visible = false

                actions: DIconButton {
                    variant: "filled"
                    iconName: "add"
                    tooltipText: I18n.tr("Ignore package", "tooltip, exclude a package from system updates")
                    enabled: newIgnoredPackageField.value.trim() !== ""
                    onClicked: ignoredPackagesCard.addIgnoredPackage()
                }
            }

            SettingsRow {
                id: ignoredPackageError
                visible: false
                title: ignoredPackagesCard.errorIsInvalidName ? I18n.tr("Invalid package name — letters, digits and @._+:/- only.", "ignored packages validation error") : I18n.tr("With Shelly, only Flatpak packages in the current update list can be ignored.")
                titleColor: Theme.error
            }

            Repeater {
                model: SettingsData.updaterIgnoredPackages

                delegate: SettingsRow {
                    id: ignoredRow
                    required property string modelData
                    required property int index

                    title: modelData
                    iconName: "visibility_off"

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "delete"
                        iconColor: Theme.error
                        tooltipText: I18n.tr("Stop ignoring %1", "system updater button tooltip, %1 is the package name").arg(ignoredRow.modelData)
                        onClicked: SystemUpdateService.unignorePackage(ignoredRow.modelData)
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "terminal"
            title: I18n.tr("Advanced")
            settingKey: "systemUpdaterAdvanced"
            collapsible: true
            expanded: false

            SettingsToggleRow {
                settingKey: "systemUpdaterCustomCommand"
                tags: ["custom", "command", "terminal"]
                text: I18n.tr("Use custom command")
                checked: SettingsData.updaterUseCustomCommand
                onToggled: checked => {
                    if (!checked) {
                        updaterCustomCommand.value = "";
                        updaterTerminalCustomClass.value = "";
                        SettingsData.set("updaterCustomCommand", "");
                        SettingsData.set("updaterTerminalAdditionalParams", "");
                    }
                    SettingsData.set("updaterUseCustomCommand", checked);
                }
            }

            SettingsNoteRow {
                enabled: SettingsData.updaterUseCustomCommand
                text: I18n.tr("Custom command and terminal params are split on whitespace; paths with spaces will break.")
            }

            SettingsTextFieldRow {
                id: updaterCustomCommand
                leftIconName: "terminal"
                visible: SettingsData.updaterUseCustomCommand
                resetKeys: ["updaterCustomCommand"]
                text: I18n.tr("Custom update command")
                placeholderText: "topgrade --no-retry"
                value: SettingsData.updaterCustomCommand
                onValueEdited: value => SettingsData.set("updaterCustomCommand", value.trim())
            }

            SettingsTextFieldRow {
                id: updaterTerminalCustomClass
                leftIconName: "terminal"
                visible: SettingsData.updaterUseCustomCommand
                resetKeys: ["updaterTerminalAdditionalParams"]
                text: I18n.tr("Terminal additional parameters")
                placeholderText: "-T updater"
                value: SettingsData.updaterTerminalAdditionalParams
                onValueEdited: value => SettingsData.set("updaterTerminalAdditionalParams", value.trim())
            }
        }
    }

    ConfirmDialogOverlay {
        id: installConfirm
        parent: root.parentModal?.modalFocusScope ?? root
    }
}
