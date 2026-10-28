import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/KeyUtils.js" as KeyUtils

Item {
    id: root

    property var parentModal: null

    readonly property bool lockFprintToggleAvailable: SettingsData.lockFingerprintCanEnable || SettingsData.enableFprint
    readonly property bool lockU2fToggleAvailable: SettingsData.lockU2fCanEnable || SettingsData.enableU2f
    readonly property bool primaryPamHasFprint: SettingsData.lockPamPath !== "" && SettingsData.lockPamInlineFprint
    readonly property bool primaryPamHasU2f: SettingsData.lockPamPath !== "" && SettingsData.lockPamInlineU2f
    readonly property bool lockFprintControlledByPrimary: SettingsData.lockPamExternallyManaged || primaryPamHasFprint
    readonly property bool lockU2fControlledByPrimary: SettingsData.lockPamExternallyManaged || primaryPamHasU2f

    property var authServices: []
    property bool authValidateRunning: false
    property bool authValidateOk: false
    property bool authValidateWarn: false
    property string authValidateMessage: ""
    property string authPendingApplyPath: ""
    property bool authShowCustom: false
    property bool u2fValidateRunning: false
    property bool u2fValidateOk: false
    property bool u2fValidateWarn: false
    property string u2fValidateMessage: ""
    property string u2fPendingApplyPath: ""
    property bool u2fShowCustom: false

    readonly property string managedNote: I18n.tr("Managed by administrator policy", "settings note: the administrator lock policy sets this value")
    readonly property string authAutoLabel: I18n.tr("Auto", "automatic PAM authentication source option")
    readonly property string authCustomLabel: I18n.tr("Custom", "custom PAM authentication source option") + "…"

    function authServiceLabel(service) {
        const label = service.name.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join("-");
        return service.dir === "/etc/pam.d" ? label : label + " (" + service.dir + ")";
    }

    readonly property var authOptions: [authAutoLabel, ...authServices.map(s => authServiceLabel(s)), authCustomLabel]

    readonly property string authCurrentValue: {
        if (SettingsData.lockPamPath === "")
            return authAutoLabel;
        const svc = authServices.find(s => s.path === SettingsData.lockPamPath);
        return svc ? authServiceLabel(svc) : authCustomLabel;
    }

    readonly property string u2fAuthCurrentValue: SettingsData.lockU2fPamPath === "" ? authAutoLabel : authCustomLabel

    function refreshAuthServices() {
        authListServicesProcess.running = true;
    }

    function applyAutoAuthSource() {
        SettingsData.set("lockPamPath", "");
        SettingsData.set("lockPamInlineFprint", false);
        SettingsData.set("lockPamInlineU2f", false);
        root.authValidateOk = false;
        root.authValidateWarn = false;
        root.authValidateMessage = "";
    }

    function validateAndApplyAuthSource(path) {
        if (!path)
            return;
        root.authPendingApplyPath = path;
        root.authValidateMessage = "";
        root.authValidateOk = false;
        root.authValidateWarn = false;
        root.authValidateRunning = true;
        authValidateProcess.command = ["dms", "auth", "validate", "--path", path, "--json"];
        authValidateProcess.running = true;
    }

    function applyAutoU2fSource() {
        SettingsData.set("lockU2fPamPath", "");
        root.u2fValidateOk = false;
        root.u2fValidateWarn = false;
        root.u2fValidateMessage = "";
    }

    function validateAndApplyU2fSource(path) {
        if (!path)
            return;
        root.u2fPendingApplyPath = path;
        root.u2fValidateMessage = "";
        root.u2fValidateOk = false;
        root.u2fValidateWarn = false;
        root.u2fValidateRunning = true;
        u2fValidateProcess.command = ["dms", "auth", "validate", "--purpose", "u2f", "--path", path, "--json"];
        u2fValidateProcess.running = true;
    }

    function lockFingerprintDescription() {
        switch (SettingsData.lockFingerprintReason) {
        case "ready":
            return I18n.tr("Use fingerprint authentication for the lock screen", "lock screen fingerprint setting");
        case "missing_enrollment":
            return I18n.tr("Fingerprint reader detected, but no prints are enrolled yet. You can enable this now and enroll later.", "lock screen fingerprint setting");
        case "missing_reader":
            return I18n.tr("No fingerprint reader detected", "fingerprint setting status");
        case "missing_pam_support":
            return I18n.tr("Not available - install %1 and %2", "lock screen fingerprint setting, %1 and %2 are package names").arg("fprintd").arg("pam_fprintd");
        default:
            return I18n.tr("Fingerprint availability could not be confirmed", "fingerprint setting status");
        }
    }

    function lockU2fDescription() {
        switch (SettingsData.lockU2fReason) {
        case "ready":
            return I18n.tr("Use a security key for lock screen authentication", "lock screen U2F security key setting");
        case "missing_key_registration":
            return I18n.tr("Security-key support was detected, but no registered key was found yet. You can enable this now and register one later.", "security key setting status");
        case "missing_pam_support":
            return I18n.tr("Not available - install or configure %1", "lock screen security key setting, %1 is a PAM module").arg("pam_u2f");
        default:
            return I18n.tr("Security-key availability could not be confirmed", "security key setting status");
        }
    }

    function refreshAuthDetection() {
        SettingsData.refreshAuthAvailability();
    }

    Component.onCompleted: {
        MultimediaService.ensureProbed();
        refreshAuthDetection();
        refreshAuthServices();
    }
    onVisibleChanged: {
        if (visible) {
            refreshAuthDetection();
            refreshAuthServices();
        }
    }

    LazyLoader {
        id: wallpaperBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            browserTitle: I18n.tr("Select lock screen background image")
            bucket: "wallpaper"
            showHiddenFiles: true
            startPath: SettingsData.lockScreenWallpaperPath || Theme.wallpaperPath
            filters: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.svg"]
            onAccepted: paths => SettingsData.set("lockScreenWallpaperPath", paths[0])
        }
    }

    FileBrowserModal {
        id: videoBrowserModal
        browserTitle: I18n.tr("Select Video or Folder")
        bucket: "video"
        filters: ["*.mp4", "*.mkv", "*.webm", "*.mov", "*.avi", "*.m4v"]
        onAccepted: paths => SettingsData.set("lockScreenVideoPath", paths[0])
    }

    Process {
        id: authListServicesProcess
        command: ["dms", "auth", "list-services", "--json"]
        running: false

        property string collected: ""

        stdout: StdioCollector {
            onStreamFinished: authListServicesProcess.collected = text || ""
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.authServices = [];
                return;
            }
            try {
                const data = JSON.parse(authListServicesProcess.collected);
                root.authServices = (data && Array.isArray(data.services)) ? data.services.filter(s => s.hasAuth) : [];
            } catch (e) {
                root.authServices = [];
            }
        }
    }

    Process {
        id: authValidateProcess
        running: false

        property string collected: ""

        stdout: StdioCollector {
            onStreamFinished: authValidateProcess.collected = text || ""
        }

        onExited: exitCode => {
            root.authValidateRunning = false;
            root.authValidateOk = false;
            root.authValidateWarn = false;

            let data = null;
            try {
                data = JSON.parse(authValidateProcess.collected);
            } catch (e) {}

            if (!data) {
                root.authValidateMessage = I18n.tr("Config validation failed");
                return;
            }
            if (!data.valid) {
                const errs = Array.isArray(data.errors) ? data.errors : [];
                root.authValidateMessage = [I18n.tr("Config validation failed"), ...errs].join("\n");
                return;
            }

            SettingsData.set("lockPamPath", root.authPendingApplyPath);
            SettingsData.set("lockPamInlineFprint", data.inlineFingerprint === true);
            SettingsData.set("lockPamInlineU2f", data.inlineU2f === true);
            const warns = Array.isArray(data.warnings) ? data.warnings : [];
            root.authValidateOk = true;
            root.authValidateWarn = warns.length > 0;
            root.authValidateMessage = [I18n.tr("Authentication changes applied"), ...warns].join("\n");
        }
    }

    Process {
        id: u2fValidateProcess
        running: false

        property string collected: ""

        stdout: StdioCollector {
            onStreamFinished: u2fValidateProcess.collected = text || ""
        }

        onExited: exitCode => {
            root.u2fValidateRunning = false;
            root.u2fValidateOk = false;
            root.u2fValidateWarn = false;

            let data = null;
            try {
                data = JSON.parse(u2fValidateProcess.collected);
            } catch (e) {}

            if (!data) {
                root.u2fValidateMessage = I18n.tr("Config validation failed");
                return;
            }
            if (!data.valid) {
                const errs = Array.isArray(data.errors) ? data.errors : [];
                root.u2fValidateMessage = [I18n.tr("Config validation failed"), ...errs].join("\n");
                return;
            }

            SettingsData.set("lockU2fPamPath", root.u2fPendingApplyPath);
            const warns = Array.isArray(data.warnings) ? data.warnings : [];
            root.u2fValidateOk = true;
            root.u2fValidateWarn = warns.length > 0;
            root.u2fValidateMessage = [I18n.tr("Authentication changes applied"), ...warns].join("\n");
            root.refreshAuthDetection();
        }
    }

    function showWidgetBrowser() {
        lockWidgetBrowserLoader.active = true;
        lockWidgetBrowserLoader.item?.show();
    }

    function showPluginBrowser() {
        lockPluginBrowserLoader.active = true;
        lockPluginBrowserLoader.item?.show();
    }

    LazyLoader {
        id: lockWidgetBrowserLoader
        active: false

        DesktopWidgetBrowser {
            parentModal: root.parentModal
            listKey: "lockScreenWidgetInstances"
            title: I18n.tr("Add widget")
            onWidgetAdded: ToastService.showInfo(I18n.tr("Widget added"))
        }
    }

    LazyLoader {
        id: lockPluginBrowserLoader
        active: false

        PluginBrowser {
            parentModal: root.parentModal
            typeFilter: "desktop-widget"
        }
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width
            iconName: "widgets"
            title: I18n.tr("Widgets")
            settingKey: "lockScreenWidgets"
            tags: ["lock", "screen", "widgets", "clock", "plugins"]

            SettingsReorderList {
                id: lockWidgetList

                model: SettingsData.lockScreenWidgetInstances || []

                delegate: DesktopWidgetInstanceCard {
                    required property var modelData

                    reorderList: lockWidgetList
                    reorderEnabled: false
                    instanceData: modelData
                    fixed: modelData.widgetType === "lockAuth"

                    onConfigureRequested: {
                        SettingsUiState.selectedDesktopWidgetId = instanceId;
                        SettingsUiState.selectedWidgetTitle = widgetName;
                        root.parentModal?.navigateTo("desktop_widget");
                    }
                    onDuplicateRequested: SettingsData.duplicateDesktopWidgetInstance(instanceId)
                    onDeleteRequested: {
                        SettingsData.removeDesktopWidgetInstance(instanceId);
                        ToastService.showInfo(I18n.tr("Widget removed"));
                    }
                }
            }

            SettingsRow {
                iconName: "restart_alt"
                title: I18n.tr("Reset to default")
                clickable: true
                onClicked: SettingsData.resetLockScreenWidgets()
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "palette"
            title: I18n.tr("Appearance")
            settingKey: "lockAppearance"

            SettingsFontDropdownRow {
                settingKey: "lockScreenFontFamily"
                tags: ["lock", "screen", "font", "typography"]
                text: I18n.tr("Font")
                currentFont: SettingsData.lockScreenFontFamily || ""
                onFontSelected: family => SettingsData.set("lockScreenFontFamily", family)
            }

            SettingsRow {
                settingKey: "lockScreenWallpaperPath"
                tags: ["lock", "screen", "wallpaper", "background", "image"]
                title: I18n.tr("Background")
                resetKeys: ["lockScreenWallpaperPath"]
                body: SettingsWallpaperThumb {
                    width: (parent.width - Theme.spacingL) / 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    placeholderIcon: "lock"
                    emptyText: I18n.tr("Use desktop wallpaper")
                    allowColor: false
                    path: SettingsData.lockScreenWallpaperPath
                    onBrowse: {
                        wallpaperBrowserLoader.active = true;
                        if (wallpaperBrowserLoader.item)
                            wallpaperBrowserLoader.item.open();
                    }
                    onClear: SettingsData.set("lockScreenWallpaperPath", "")
                }
            }

            SettingsDropdownRow {
                readonly property var fillModes: ["Stretch", "Fit", "Fill", "Tile", "TileVertically", "TileHorizontally", "Pad"]
                readonly property var fillModeLabels: fillModes.map(mode => I18n.tr(mode, "wallpaper fill mode"))

                settingKey: "lockScreenWallpaperFillMode"
                tags: ["lock", "screen", "wallpaper", "background", "fill"]
                text: I18n.tr("Wallpaper fill mode")
                options: fillModeLabels
                currentValue: {
                    const idx = fillModes.indexOf(SettingsData.lockScreenWallpaperFillMode || "Fill");
                    return fillModeLabels[idx >= 0 ? idx : fillModes.indexOf("Fill")];
                }
                onValueChanged: value => {
                    const idx = fillModeLabels.indexOf(value);
                    if (idx >= 0)
                        SettingsData.set("lockScreenWallpaperFillMode", fillModes[idx]);
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "lock"
            title: I18n.tr("Behavior")
            settingKey: "lockBehavior"
            SettingsToggleRow {
                settingKey: "lockScreenPowerOffMonitorsOnLock"
                tags: ["lock", "screen", "monitor", "display", "dpms", "power"]
                text: I18n.tr("Power off displays on lock")
                checked: SettingsData.lockScreenPowerOffMonitorsOnLock
                onToggled: checked => SettingsData.set("lockScreenPowerOffMonitorsOnLock", checked)
            }

            SettingsToggleRow {
                settingKey: "lockAtStartup"
                tags: ["lock", "screen", "startup", "start", "boot", "login", "automatic"]
                text: I18n.tr("Lock at startup")
                description: SettingsData.isManaged("lockAtStartup") ? root.managedNote : ""
                enabled: !SettingsData.isManaged("lockAtStartup")
                checked: SettingsData.lockAtStartup
                onToggled: checked => SettingsData.set("lockAtStartup", checked)
            }

            SettingsToggleRow {
                settingKey: "lockBeforeSuspend"
                tags: ["lock", "screen", "suspend", "hibernate", "sleep", "automatic"]
                text: I18n.tr("Lock before suspend")
                description: SettingsData.isManaged("lockBeforeSuspend") ? root.managedNote : ""
                enabled: !SettingsData.isManaged("lockBeforeSuspend")
                checked: SettingsData.lockBeforeSuspend
                visible: SessionService.loginctlAvailable && SettingsData.loginctlLockIntegration
                onToggled: checked => SettingsData.set("lockBeforeSuspend", checked)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "movie"
            title: I18n.tr("Video screensaver")
            settingKey: "videoScreensaver"

            SettingsRow {
                visible: !MultimediaService.available
                body: StyledText {
                    text: I18n.tr("QtMultimedia is not available - video screensaver requires qt multimedia services")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
            }

            SettingsToggleRow {
                settingKey: "lockScreenVideoEnabled"
                tags: ["lock", "screen", "video", "screensaver", "animation", "movie"]
                text: I18n.tr("Play video on lock")
                enabled: MultimediaService.available
                checked: SettingsData.lockScreenVideoEnabled
                onToggled: checked => SettingsData.set("lockScreenVideoEnabled", checked)
            }

            SettingsTextFieldRow {
                leftIconName: "folder"
                visible: SettingsData.lockScreenVideoEnabled && MultimediaService.available
                text: I18n.tr("Path")
                resetKeys: ["lockScreenVideoPath"]
                value: SettingsData.lockScreenVideoPath
                placeholderText: "/path/to/videos"
                onValueEdited: value => SettingsData.set("lockScreenVideoPath", value)

                actions: DButton {
                    text: I18n.tr("Browse")
                    onClicked: videoBrowserModal.open()
                }
            }

            SettingsToggleRow {
                settingKey: "lockScreenVideoCycling"
                tags: ["lock", "screen", "video", "screensaver", "cycling", "random", "shuffle"]
                text: I18n.tr("Automatic cycling")
                visible: SettingsData.lockScreenVideoEnabled && MultimediaService.available
                enabled: MultimediaService.available
                checked: SettingsData.lockScreenVideoCycling
                onToggled: checked => SettingsData.set("lockScreenVideoCycling", checked)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "key"
            title: I18n.tr("Authentication")
            settingKey: "lockAuthSource"
            SettingsToggleRow {
                settingKey: "lockPamExternallyManaged"
                tags: ["lock", "screen", "pam", "managed", "external", "authentication", "policy"]
                text: I18n.tr("Use system PAM authentication", "system PAM policy toggle")
                checked: SettingsData.lockPamExternallyManaged
                onToggled: checked => SettingsData.set("lockPamExternallyManaged", checked)
            }

            SettingsToggleRow {
                settingKey: "enableFprint"
                tags: ["lock", "screen", "fingerprint", "authentication", "biometric", "fprint"]
                text: I18n.tr("Fingerprint", "lock screen fingerprint authentication toggle")
                description: SettingsData.isManaged("enableFprint") ? root.managedNote : root.lockFprintControlledByPrimary ? I18n.tr("Managed by the primary PAM source", "factor managed by PAM source status") : root.lockFingerprintDescription()
                descriptionColor: SettingsData.isManaged("enableFprint") || root.lockFprintControlledByPrimary || SettingsData.lockFingerprintReason === "ready" ? Theme.surfaceVariantText : Theme.warning
                checked: SettingsData.enableFprint || root.primaryPamHasFprint
                enabled: root.lockFprintToggleAvailable && !root.lockFprintControlledByPrimary && !SettingsData.isManaged("enableFprint")
                onToggled: checked => SettingsData.set("enableFprint", checked)
            }

            SettingsToggleRow {
                settingKey: "enableU2f"
                tags: ["lock", "screen", "u2f", "yubikey", "security", "key", "fido", "authentication", "hardware"]
                text: I18n.tr("Security key")
                description: SettingsData.isManaged("enableU2f") ? root.managedNote : root.lockU2fControlledByPrimary ? I18n.tr("Managed by the primary PAM source", "factor managed by PAM source status") : root.lockU2fDescription()
                descriptionColor: SettingsData.isManaged("enableU2f") || root.lockU2fControlledByPrimary || SettingsData.lockU2fReason === "ready" ? Theme.surfaceVariantText : Theme.warning
                checked: SettingsData.enableU2f || root.primaryPamHasU2f
                enabled: root.lockU2fToggleAvailable && !root.lockU2fControlledByPrimary && !SettingsData.isManaged("enableU2f")
                onToggled: checked => SettingsData.set("enableU2f", checked)
            }

            SettingsDropdownRow {
                settingKey: "u2fMode"
                tags: ["lock", "screen", "u2f", "yubikey", "security", "key", "mode", "factor", "second"]
                text: I18n.tr("Security key mode", "lock screen U2F security key mode setting")
                description: SettingsData.isManaged("u2fMode") ? root.managedNote : I18n.tr("'Alternative' lets the key unlock on its own. 'Second factor' requires password or fingerprint first, then the key.", "lock screen U2F security key mode setting")
                enabled: !SettingsData.isManaged("u2fMode")
                visible: SettingsData.enableU2f && !root.lockU2fControlledByPrimary
                options: [I18n.tr("Alternative (OR)", "U2F mode option: key works as standalone unlock method"), I18n.tr("Second factor (AND)", "U2F mode option: key required after password or fingerprint")]
                currentValue: SettingsData.u2fMode === "and" ? I18n.tr("Second factor (AND)", "U2F mode option: key required after password or fingerprint") : I18n.tr("Alternative (OR)", "U2F mode option: key works as standalone unlock method")
                onValueChanged: value => {
                    if (value === I18n.tr("Second factor (AND)", "U2F mode option: key required after password or fingerprint"))
                        SettingsData.set("u2fMode", "and");
                    else
                        SettingsData.set("u2fMode", "or");
                }
            }

            SettingsToggleRow {
                settingKey: "lockScreenSecurityKeyShortcutEnabled"
                tags: ["lock", "screen", "u2f", "yubikey", "security", "key", "shortcut", "keybind", "authentication"]
                text: I18n.tr("Security key shortcut", "lock screen security key shortcut toggle")
                checked: SettingsData.lockScreenSecurityKeyShortcutEnabled
                visible: SettingsData.enableU2f && SettingsData.u2fMode === "or" && !root.lockU2fControlledByPrimary
                onToggled: checked => SettingsData.set("lockScreenSecurityKeyShortcutEnabled", checked)
            }

            SettingsRow {
                visible: SettingsData.lockScreenSecurityKeyShortcutEnabled && SettingsData.enableU2f && SettingsData.u2fMode === "or" && !root.lockU2fControlledByPrimary
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    Column {
                        width: parent.width - securityKeyCapture.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            text: I18n.tr("Key combination", "lock screen security key shortcut key combination setting")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                            width: parent.width
                            horizontalAlignment: Text.AlignLeft
                        }

                        StyledText {
                            text: securityKeyCapture.captureError !== "" ? securityKeyCapture.captureError : I18n.tr("Press Ctrl+key to set. Esc cancels.", "lock screen security key shortcut key combination capture hint")
                            font.pixelSize: Theme.fontSizeSmall
                            color: securityKeyCapture.captureError !== "" ? Theme.warning : Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            width: parent.width
                            horizontalAlignment: Text.AlignLeft
                        }
                    }

                    DButton {
                        id: securityKeyCapture
                        width: 200
                        anchors.verticalCenter: parent.verticalCenter
                        text: capturing ? I18n.tr("Press key...", "lock screen security key shortcut key combination capture prompt") : SettingsData.lockScreenSecurityKeyShortcut
                        backgroundColor: capturing ? Theme.selectedContainer : SettingsMetrics.controlColor
                        textColor: Theme.surfaceText

                        property bool capturing: false
                        property string captureError: ""
                        readonly property var reservedKeys: ["A", "E", "B", "F", "U", "K", "W", "H", "D"]

                        function startCapture() {
                            captureError = "";
                            capturing = true;
                            securityKeyCapture.forceActiveFocus();
                        }

                        function stopCapture() {
                            capturing = false;
                        }

                        onClicked: {
                            if (capturing)
                                stopCapture();
                            else
                                startCapture();
                        }

                        Keys.onPressed: event => captureKey(event)
                        // Specific Tab handlers stop Qt focus traversal while capturing.
                        Keys.onTabPressed: event => captureKey(event)
                        Keys.onBacktabPressed: event => captureKey(event)

                        function captureKey(event) {
                            event.accepted = capturing;
                            if (!capturing)
                                return;

                            if (KeyUtils.isModifierKey(event.key))
                                return;

                            if (event.key === Qt.Key_Escape) {
                                securityKeyCapture.stopCapture();
                                return;
                            }

                            const mods = KeyUtils.modsFromEvent(event.modifiers);
                            const hasCtrl = mods.includes("Ctrl");
                            const hasAlt = mods.includes("Alt") || mods.includes("Super");
                            if (!hasCtrl || hasAlt)
                                return;

                            const hasShift = mods.includes("Shift");
                            const key = KeyUtils.xkbKeyFromQtKey(event.key, !!(event.modifiers & Qt.KeypadModifier), hasShift);
                            if (!key)
                                return;

                            if (!KeyUtils.qtKeyFromName(key))
                                return;

                            if (!hasShift && securityKeyCapture.reservedKeys.indexOf(key.toUpperCase()) !== -1) {
                                securityKeyCapture.captureError = I18n.tr("Ctrl+%1 is used for password editing", "lock screen security key shortcut reserved key warning").arg(key.toUpperCase());
                                event.accepted = true;
                                return;
                            }

                            SettingsData.set("lockScreenSecurityKeyShortcut", KeyUtils.formatToken(mods, key));
                            securityKeyCapture.captureError = "";
                            securityKeyCapture.stopCapture();
                            event.accepted = true;
                        }
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "monitor"
            title: I18n.tr("Displays")
            settingKey: "lockDisplay"
            SettingsRow {
                body: StyledText {
                    text: I18n.tr("Other displays show a solid color for OLED burn-in protection")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    width: parent.width
                    wrapMode: Text.Wrap
                }
            }

            SettingsDisplayPicker {
                width: parent.width
                displayPreferences: SettingsData.screenPreferences?.lockScreen || ["all"]
                preferencesHandler: prefs => {
                    var p = SettingsData.screenPreferences || {};
                    var updated = Object.assign({}, p);
                    updated["lockScreen"] = prefs;
                    SettingsData.set("screenPreferences", updated);
                }
            }

            SettingsRow {
                title: I18n.tr("Inactive display color")
                tags: ["lock", "screen", "inactive", "display", "color", "oled"]
                resetKeys: ["lockScreenInactiveColor"]
                visible: {
                    const prefs = SettingsData.screenPreferences?.lockScreen;
                    return Array.isArray(prefs) && !prefs.includes("all") && prefs.length > 0;
                }
                clickable: true
                onClicked: {
                    if (!PopoutService.colorPickerModal)
                        return;
                    PopoutService.colorPickerModal.selectedColor = SettingsData.lockScreenInactiveColor;
                    PopoutService.colorPickerModal.pickerTitle = I18n.tr("Inactive display color");
                    PopoutService.colorPickerModal.onColorSelectedCallback = function (selectedColor) {
                        SettingsData.set("lockScreenInactiveColor", selectedColor);
                    };
                    PopoutService.colorPickerModal.show();
                }

                DColorSwatch {
                    width: Theme.iconSizeMedium
                    height: width
                    swatchColor: SettingsData.lockScreenInactiveColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "tune"
            title: I18n.tr("Advanced")
            settingKey: "lockScreenAdvanced"
            tags: ["pam", "authentication", "source", "loginctl", "u2f"]
            collapsible: true
            expanded: false

            SettingsRow {
                body: StyledText {
                    text: I18n.tr("Authentication changes apply automatically")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    width: parent.width
                    wrapMode: Text.Wrap
                }
            }

            SettingsDropdownRow {
                settingKey: "lockPamPath"
                resetKeys: []
                tags: ["lock", "screen", "pam", "authentication", "source", "service"]
                text: I18n.tr("Authentication source", "lock screen PAM source setting")
                description: SettingsData.lockPamPath !== "" ? SettingsData.lockPamPath : I18n.tr("Which PAM service the lock screen uses to authenticate", "lock screen PAM source setting")
                options: root.authOptions
                currentValue: root.authCurrentValue
                onValueChanged: value => {
                    if (value === root.authAutoLabel) {
                        root.authShowCustom = false;
                        root.applyAutoAuthSource();
                        return;
                    }
                    if (value === root.authCustomLabel) {
                        root.authShowCustom = true;
                        return;
                    }
                    root.authShowCustom = false;
                    const svc = root.authServices.find(s => root.authServiceLabel(s) === value);
                    if (svc)
                        root.validateAndApplyAuthSource(svc.path);
                }
            }

            SettingsRow {
                visible: root.authShowCustom || root.authCurrentValue === root.authCustomLabel
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DTextField {
                        id: customPamField
                        outlined: true
                        leftIconName: "lock"
                        labelText: I18n.tr("Path")
                        width: parent.width - validatePamButton.width - Theme.spacingS
                        placeholderText: "/etc/pam.d/my-service"
                        text: SettingsData.lockPamPath
                    }

                    DButton {
                        id: validatePamButton
                        text: I18n.tr("Apply changes")
                        enabled: !root.authValidateRunning && customPamField.text.trim() !== ""
                        onClicked: root.validateAndApplyAuthSource(customPamField.text.trim())
                    }
                }
            }

            SettingsNoteRow {
                visible: root.authValidateMessage !== ""
                noteIconName: ""
                monospace: true
                maxHeight: SettingsMetrics.noteMaxHeight
                text: root.authValidateMessage
                tint: !root.authValidateOk ? Theme.error : (root.authValidateWarn ? Theme.warning : Theme.surfaceVariantText)
                tintBackground: SettingsMetrics.controlColor
            }

            SettingsDropdownRow {
                settingKey: "lockU2fPamPath"
                resetKeys: []
                tags: ["lock", "screen", "pam", "u2f", "security", "key", "source", "service"]
                text: I18n.tr("Security key PAM source", "lock screen dedicated U2F PAM source setting")
                description: SettingsData.lockU2fPamPath !== "" ? SettingsData.lockU2fPamPath : I18n.tr("Auto uses an installed or bundled key-only service.", "lock screen dedicated U2F PAM source setting")
                visible: !root.lockU2fControlledByPrimary
                options: [root.authAutoLabel, root.authCustomLabel]
                currentValue: root.u2fAuthCurrentValue
                onValueChanged: value => {
                    if (value === root.authAutoLabel) {
                        root.u2fShowCustom = false;
                        root.applyAutoU2fSource();
                        return;
                    }
                    root.u2fShowCustom = true;
                }
            }

            SettingsRow {
                visible: !root.lockU2fControlledByPrimary && (root.u2fShowCustom || root.u2fAuthCurrentValue === root.authCustomLabel)
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DTextField {
                        id: customU2fPamField
                        outlined: true
                        leftIconName: "key"
                        labelText: I18n.tr("Path")
                        width: parent.width - validateU2fPamButton.width - Theme.spacingS
                        placeholderText: "/etc/pam.d/dankshell-u2f"
                        text: SettingsData.lockU2fPamPath
                    }

                    DButton {
                        id: validateU2fPamButton
                        text: I18n.tr("Apply changes")
                        enabled: !root.u2fValidateRunning && customU2fPamField.text.trim() !== ""
                        onClicked: root.validateAndApplyU2fSource(customU2fPamField.text.trim())
                    }
                }
            }

            SettingsNoteRow {
                visible: !root.lockU2fControlledByPrimary && root.u2fValidateMessage !== ""
                noteIconName: ""
                monospace: true
                maxHeight: SettingsMetrics.noteMaxHeight
                text: root.u2fValidateMessage
                tint: !root.u2fValidateOk ? Theme.error : (root.u2fValidateWarn ? Theme.warning : Theme.surfaceVariantText)
                tintBackground: SettingsMetrics.controlColor
            }

            SettingsRow {
                visible: !SessionService.loginctlAvailable
                body: StyledText {
                    text: I18n.tr("%1 not available - lock integration requires the DMS socket connection", "lock screen warning, %1 is the loginctl binary").arg("loginctl")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                    width: parent.width
                    wrapMode: Text.Wrap
                }
            }

            SettingsToggleRow {
                settingKey: "loginctlLockIntegration"
                tags: ["lock", "screen", "loginctl", "dbus", "integration", "external"]
                text: I18n.tr("loginctl integration")
                description: SettingsData.isManaged("loginctlLockIntegration") ? root.managedNote : I18n.tr("Disable when using an external lock screen")
                checked: SessionService.loginctlAvailable && SettingsData.loginctlLockIntegration
                enabled: SessionService.loginctlAvailable && !SettingsData.isManaged("loginctlLockIntegration")
                onToggled: checked => {
                    if (!SessionService.loginctlAvailable)
                        return;
                    SettingsData.set("loginctlLockIntegration", checked);
                }
            }
        }

        SettingsFabBar {
            DFab {
                text: I18n.tr("Browse plugins")
                iconName: "store"
                colorRole: "secondaryContainer"
                onClicked: root.showPluginBrowser()
            }

            DFab {
                text: I18n.tr("Edit widgets")
                iconName: "edit"
                colorRole: "secondaryContainer"
                onClicked: SessionService.lockEditorRequested()
            }

            DFab {
                text: I18n.tr("Add widget")
                iconName: "add"
                onClicked: root.showWidgetBrowser()
            }
        }
    }
}
