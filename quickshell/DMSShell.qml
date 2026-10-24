pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals
import qs.Modals.Changelog
import qs.Modals.Clipboard
import qs.Modals.Common
import qs.Modals.Greeter
import qs.Modals.Settings
import qs.Modals.DLauncherV2
import qs.Modules
import qs.Modules.AppDrawer
import qs.Modules.DDash
import qs.Modules.ControlCenter
import qs.Modules.Dock
import qs.Modules.Lock
import qs.Modules.Markup
import qs.Modules.Notepad
import qs.Modules.Notifications.Center
import qs.Widgets
import qs.Modules.Notifications.Popup
import qs.Modules.OSD
import qs.Modules.ProcessList
import qs.Modules.DBar.Popouts
import qs.Modules.WorkspaceOverlays
import qs.Modules.Settings.DisplayConfig
import qs.Services

Item {
    id: root
    readonly property var log: Log.scoped("DMSShell")
    readonly property var _nightModeServiceRef: NightModeService
    readonly property var _brightnessServiceRef: BrightnessService
    readonly property var _refreshRateServiceRef: RefreshRateService

    property var core: null

    property bool osdSurfacesLoaded: false
    property int pendingOsdResumeReloads: 0
    readonly property var notificationPopupScreens: {
        const screens = SettingsData.notificationFocusedMonitor ? Quickshell.screens : SettingsData.getFilteredScreens("notifications");
        if (!SettingsData.dankIslandEnabled)
            return screens;
        return screens.filter(screen => !SettingsData.dankIslandHandlesNotifications(screen));
    }
    readonly property var legacySystemLevelOsdScreens: {
        const screens = SettingsData.getFilteredScreens("osd");
        if (!SettingsData.dankIslandEnabled)
            return screens;
        return screens.filter(screen => !SettingsData.dankIslandHandlesSystemOsd(screen));
    }

    function recreateOsdSurfaces() {
        OSDManager.currentOSDsByScreen = ({});
        osdSurfacesLoaded = false;
        osdSurfaceReloadTimer.restart();
    }

    DesktopWidgetLayer {}

    DesktopWidgetEditor {}

    DesktopContextMenu {
        Component.onCompleted: PopoutService.desktopContextMenu = this
    }

    Lock {
        id: lock
    }

    Variants {
        model: Quickshell.screens

        delegate: Loader {
            id: fadeWindowLoader
            required property var modelData
            readonly property FadeToLockWindow loadedWindow: item as FadeToLockWindow
            active: SettingsData.fadeToLockEnabled
            asynchronous: false

            sourceComponent: FadeToLockWindow {
                screen: fadeWindowLoader.modelData

                onFadeCompleted: {
                    IdleService.lockRequested();
                }

                onFadeCancelled: {
                    root.log.debug("Fade to lock cancelled by user on screen:", fadeWindowLoader.modelData.name);
                }
            }

            Connections {
                target: IdleService
                enabled: fadeWindowLoader.loadedWindow !== null

                function onFadeToLockRequested() {
                    if (fadeWindowLoader.loadedWindow) {
                        fadeWindowLoader.loadedWindow.startFade();
                    }
                }

                function onCancelFadeToLock() {
                    if (fadeWindowLoader.loadedWindow) {
                        fadeWindowLoader.loadedWindow.cancelFade();
                    }
                }

                function onDismissFadeToLock() {
                    if (fadeWindowLoader.loadedWindow) {
                        fadeWindowLoader.loadedWindow.dismiss();
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Loader {
            id: fadeDpmsWindowLoader
            required property var modelData
            readonly property FadeToDpmsWindow loadedWindow: item as FadeToDpmsWindow
            active: SettingsData.fadeToDpmsEnabled
            asynchronous: false

            sourceComponent: FadeToDpmsWindow {
                screen: fadeDpmsWindowLoader.modelData

                onFadeCompleted: {
                    IdleService.requestMonitorOff();
                }

                onFadeCancelled: {
                    root.log.debug("Fade to DPMS cancelled by user on screen:", fadeDpmsWindowLoader.modelData.name);
                }
            }

            Connections {
                target: IdleService
                enabled: fadeDpmsWindowLoader.loadedWindow !== null

                function onFadeToDpmsRequested() {
                    if (fadeDpmsWindowLoader.loadedWindow) {
                        fadeDpmsWindowLoader.loadedWindow.startFade();
                    }
                }

                function onCancelFadeToDpms() {
                    if (fadeDpmsWindowLoader.loadedWindow) {
                        fadeDpmsWindowLoader.loadedWindow.cancelFade();
                    }
                }

                function onRequestMonitorOn() {
                    if (!fadeDpmsWindowLoader.loadedWindow)
                        return;
                    fadeDpmsWindowLoader.loadedWindow.cancelFade();
                }

                function onMonitorsOffChanged() {
                    if (IdleService.monitorsOff)
                        return;
                    if (!fadeDpmsWindowLoader.loadedWindow)
                        return;
                    fadeDpmsWindowLoader.loadedWindow.dismiss();
                }
            }
        }
    }

    Connections {
        target: root.core

        function on_BarLayoutStateJsonChanged() {
            dockRecreateDebounce.restart();
        }

        function onSurfaceRecoveryPass() {
            root.dockEnabled = false;
            Qt.callLater(() => {
                root.dockEnabled = true;
            });
        }
    }

    property bool dockEnabled: false

    Timer {
        id: dockRecreateDebounce
        interval: 500
        repeat: false
        onTriggered: {
            root.dockEnabled = false;
            Qt.callLater(() => {
                root.dockEnabled = true;
            });
        }
    }

    Timer {
        id: loginSoundTimer
        // Half a second delay before playing login sound, otherwise the sound may be cut off
        // 50 is the minimum that seems to work, but 500 is safer
        interval: 500
        repeat: false
        onTriggered: {
            AudioService.playLoginSoundIfApplicable();
        }
    }

    Timer {
        id: osdResumeRecreateTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.recreateOsdSurfaces();
            root.pendingOsdResumeReloads--;

            if (root.pendingOsdResumeReloads <= 0) {
                root.pendingOsdResumeReloads = 0;
                interval = 400;
                return;
            }

            interval = 1400;
            restart();
        }
    }

    Timer {
        id: osdSurfaceReloadTimer
        interval: 120
        repeat: false
        onTriggered: root.osdSurfacesLoaded = true
    }

    Timer {
        id: osdStartupTimer
        interval: 1000
        repeat: false
        onTriggered: root.osdSurfacesLoaded = true
    }

    Component.onCompleted: {
        dockEnabled = true;
        loginSoundTimer.start();
        osdStartupTimer.start();
        if (SettingsData.controlCenterWidgets.some(widget => widget.id === "diskUsage" && widget.enabled !== false))
            DgopService.initializeDiskMounts();
        if (SettingsData.controlCenterWidgets.some(widget => widget.id === "user" && widget.enabled !== false && widget.uptime !== false))
            DgopService.dgopAvailable;

        // These are dummy references just to trigger the singletons onCompleted to trigger
        PolkitService.polkitAvailable;
        DisplayConfigState.hasOutputBackend;
        PortalService.systemColorScheme;
        DesktopService.isSystemd;
        TrashService.count;
        WallpaperCyclingService.cyclingActive;
        ThemeAutoService.active;
        WellbeingService.tracking;
    }

    Loader {
        id: dockLoader
        active: root.dockEnabled
        asynchronous: false

        sourceComponent: Dock {
            contextMenu: dockContextMenuLoader.item ? dockContextMenuLoader.item : null
            trashContextMenu: dockTrashContextMenuLoader.item ? dockTrashContextMenuLoader.item : null
        }

        onLoaded: {
            if (item) {
                dockContextMenuLoader.active = true;
                if (SettingsData.dockConfigs.some(config => config.showTrash)) {
                    dockTrashContextMenuLoader.active = true;
                }
            }
        }
    }

    Loader {
        id: dankDashPopoutLoader

        active: false
        asynchronous: false

        Component.onCompleted: {
            PopoutService.dankDashPopoutLoader = dankDashPopoutLoader;
        }

        onLoaded: {
            if (item) {
                PopoutService.dankDashPopout = item;
                PopoutService._onDankDashPopoutLoaded();
            }
        }

        sourceComponent: Component {
            DDashPopout {
                id: dankDashPopout

                onPopoutClosed: PopoutService._scheduleUnload("dankDash")
            }
        }
    }

    LazyLoader {
        id: dockContextMenuLoader

        active: false

        DockContextMenu {
            id: dockContextMenu
        }
    }

    LazyLoader {
        id: dockTrashContextMenuLoader

        active: false

        DockTrashContextMenu {
            id: dockTrashContextMenu
        }
    }

    Binding {
        target: BarWidgetService
        property: "dockContextMenu"
        value: dockContextMenuLoader.item
    }
    Binding {
        target: BarWidgetService
        property: "dockTrashContextMenu"
        value: dockTrashContextMenuLoader.item
    }

    Connections {
        target: SettingsData
        function onDockConfigsChanged() {
            if (SettingsData.dockConfigs.some(config => config.showTrash)) {
                dockTrashContextMenuLoader.active = true;
            }
        }
    }

    LazyLoader {
        id: emptyTrashConfirmLoader
        active: false
        readonly property ConfirmModal loadedModal: item as ConfirmModal

        ConfirmModal {
            id: emptyTrashConfirm
        }
    }

    Connections {
        target: TrashService
        function onEmptyTrashConfirmRequested(itemCount) {
            emptyTrashConfirmLoader.active = true;
            if (!emptyTrashConfirmLoader.loadedModal)
                return;
            emptyTrashConfirmLoader.loadedModal.showWithOptions({
                title: I18n.tr("Empty Trash"),
                message: I18n.tr("Permanently delete %1 item(s)? This cannot be undone.", "empty trash confirmation message, %1 is a count").arg(itemCount),
                confirmText: I18n.tr("Empty"),
                cancelText: I18n.tr("Cancel"),
                confirmColor: Theme.error,
                onConfirm: () => TrashService.emptyTrash()
            });
        }
    }

    LazyLoader {
        id: uninstallAppConfirmLoader
        active: false
        readonly property ConfirmModal loadedModal: item as ConfirmModal

        ConfirmModal {
            id: uninstallAppConfirm
        }
    }

    Connections {
        target: AppSearchService
        function onUninstallAppConfirmRequested(appId, appName, flatpakId) {
            uninstallAppConfirmLoader.active = true;
            const showDialog = () => {
                if (uninstallAppConfirmLoader.loadedModal) {
                    uninstallAppConfirmLoader.loadedModal.showWithOptions({
                        title: I18n.tr("Uninstall %1?", "modal title for app uninstallation").arg(appName),
                        message: I18n.tr("%1 will be removed from your system.", "modal confirmation text for uninstalling an app").arg(appName),
                        confirmText: I18n.tr("Uninstall", "confirm button label to proceed with uninstallation"),
                        cancelText: I18n.tr("Cancel"),
                        confirmColor: Theme.error,
                        onConfirm: () => AppSearchService.uninstallFlatpak(appId, appName, flatpakId)
                    });
                }
            };
            if (uninstallAppConfirmLoader.loadedModal)
                showDialog();
            else
                Qt.callLater(showDialog);
        }
    }

    LazyLoader {
        id: notificationCenterLoader

        active: false

        Component.onCompleted: {
            PopoutService.notificationCenterLoader = notificationCenterLoader;
        }

        NotificationCenterPopout {
            id: notificationCenter
            onPopoutClosed: PopoutService.unloadNotificationCenter()

            Component.onCompleted: {
                PopoutService.notificationCenterPopout = notificationCenter;
            }
        }
    }

    Variants {
        model: root.notificationPopupScreens

        delegate: NotificationPopupManager {}
    }

    LazyLoader {
        id: controlCenterLoader

        active: false

        property var modalRef: colorPickerModal
        property LazyLoader powerModalLoaderRef: powerMenuModalLoader

        Component.onCompleted: {
            PopoutService.controlCenterLoader = controlCenterLoader;
        }

        ControlCenterPopout {
            id: controlCenterPopout
            colorPickerModal: controlCenterLoader.modalRef
            powerMenuModalLoader: controlCenterLoader.powerModalLoaderRef
            onPopoutClosed: PopoutService.unloadControlCenter()

            onLockRequested: {
                lock.activate();
            }

            Component.onCompleted: {
                PopoutService.controlCenterPopout = controlCenterPopout;
            }
        }
    }

    LazyLoader {
        id: wifiPasswordModalLoader
        active: false
        readonly property WifiPasswordModal loadedModal: item as WifiPasswordModal

        Component.onCompleted: {
            PopoutService.wifiPasswordModalLoader = wifiPasswordModalLoader;
        }

        WifiPasswordModal {
            id: wifiPasswordModalItem

            Component.onCompleted: {
                PopoutService.wifiPasswordModal = wifiPasswordModalItem;
            }
        }
    }

    LazyLoader {
        id: wifiQRCodeModalLoader
        active: false

        Component.onCompleted: {
            PopoutService.wifiQRCodeModalLoader = wifiQRCodeModalLoader;
        }

        WifiQRCodeModal {
            id: wifiQRCodeModalItem

            Component.onCompleted: {
                PopoutService.wifiQRCodeModal = wifiQRCodeModalItem;
            }
        }
    }

    LazyLoader {
        id: qrGeneratorModalLoader
        active: false

        Component.onCompleted: {
            PopoutService.qrGeneratorModalLoader = qrGeneratorModalLoader;
        }

        QRGeneratorModal {
            id: qrGeneratorModalItem

            Component.onCompleted: {
                PopoutService.qrGeneratorModal = qrGeneratorModalItem;
            }
        }
    }

    LazyLoader {
        id: polkitAuthModalLoader
        active: false
        readonly property PolkitAuthModal loadedModal: item as PolkitAuthModal

        PolkitAuthModal {
            id: polkitAuthModal

            Component.onCompleted: {
                PopoutService.polkitAuthModal = polkitAuthModal;
            }
        }
    }

    Connections {
        target: PolkitService.agent
        enabled: PolkitService.polkitAvailable

        function onAuthenticationRequestStarted() {
            if (PopoutService.systemUpdatePopout?.shouldBeVisible)
                return;
            polkitAuthModalLoader.active = true;
            if (polkitAuthModalLoader.loadedModal)
                polkitAuthModalLoader.loadedModal.show();
        }
    }

    LazyLoader {
        id: bluetoothPairingModalLoader
        active: false

        Component.onCompleted: PopoutService.bluetoothPairingModalLoader = bluetoothPairingModalLoader

        BluetoothPairingModal {
            id: bluetoothPairingModal

            Component.onCompleted: {
                PopoutService.bluetoothPairingModal = bluetoothPairingModal;
            }
        }
    }

    property string lastCredentialsToken: ""
    property var lastCredentialsTime: 0

    Connections {
        target: NetworkService

        function onCredentialsNeeded(token, ssid, setting, fields, hints, reason, connType, connName, vpnService, fieldsInfo) {
            const alreadyShown = wifiPasswordModalLoader.loadedModal && wifiPasswordModalLoader.loadedModal.shouldBeVisible;
            if (alreadyShown && token === root.lastCredentialsToken)
                return;

            wifiPasswordModalLoader.active = true;
            if (!wifiPasswordModalLoader.loadedModal)
                return;

            if (alreadyShown && root.lastCredentialsToken !== "" && root.lastCredentialsToken !== token)
                NetworkService.cancelCredentials(root.lastCredentialsToken);

            root.lastCredentialsToken = token;
            root.lastCredentialsTime = Date.now();
            wifiPasswordModalLoader.loadedModal.showFromPrompt(token, ssid, setting, fields, hints, reason, connType, connName, vpnService, fieldsInfo);
        }
    }

    LazyLoader {
        id: networkInfoModalLoader

        active: false

        NetworkInfoModal {
            id: networkInfoModal

            Component.onCompleted: {
                PopoutService.networkInfoModal = networkInfoModal;
            }
        }
    }

    LazyLoader {
        id: batteryPopoutLoader

        active: false

        Component.onCompleted: {
            PopoutService.batteryPopoutLoader = batteryPopoutLoader;
        }

        BatteryPopout {
            id: batteryPopout
            onPopoutClosed: PopoutService.unloadBattery()

            Component.onCompleted: {
                PopoutService.batteryPopout = batteryPopout;
            }
        }
    }

    LazyLoader {
        id: layoutPopoutLoader

        active: false

        Component.onCompleted: {
            PopoutService.layoutPopoutLoader = layoutPopoutLoader;
        }

        DWLLayoutPopout {
            id: layoutPopout
            onPopoutClosed: PopoutService.unloadLayoutPopout()

            Component.onCompleted: {
                PopoutService.layoutPopout = layoutPopout;
            }
        }
    }

    LazyLoader {
        id: vpnPopoutLoader

        active: false

        Component.onCompleted: {
            PopoutService.vpnPopoutLoader = vpnPopoutLoader;
        }

        VpnPopout {
            id: vpnPopout
            onPopoutClosed: PopoutService.unloadVpn()

            Component.onCompleted: {
                PopoutService.vpnPopout = vpnPopout;
            }
        }
    }

    LazyLoader {
        id: colorPickerPopoutLoader

        active: false

        Component.onCompleted: {
            PopoutService.colorPickerPopoutLoader = colorPickerPopoutLoader;
        }

        ColorPickerPopout {
            id: colorPickerPopout
            onPopoutClosed: PopoutService.unloadColorPicker()

            Component.onCompleted: {
                PopoutService.colorPickerPopout = colorPickerPopout;
            }
        }
    }

    LazyLoader {
        id: processListPopoutLoader

        active: false

        Component.onCompleted: {
            PopoutService.processListPopoutLoader = processListPopoutLoader;
        }

        ProcessListPopout {
            id: processListPopout
            onPopoutClosed: PopoutService.unloadProcessListPopout()

            Component.onCompleted: {
                PopoutService.processListPopout = processListPopout;
            }
        }
    }

    LazyLoader {
        id: settingsModalLoader

        active: false

        Component.onCompleted: {
            PopoutService.settingsModalLoader = settingsModalLoader;
        }

        onActiveChanged: {
            if (active && item) {
                PopoutService.settingsModal = item;
                PopoutService._onSettingsModalLoaded();
            }
        }

        SettingsModal {
            id: settingsModal
            property bool wasShown: false

            onVisibleChanged: {
                if (visible) {
                    wasShown = true;
                } else if (wasShown) {
                    Qt.callLater(() => PopoutService.unloadSettingsNow());
                }
            }
        }
    }

    LazyLoader {
        id: appDrawerLoader

        active: false

        Component.onCompleted: {
            PopoutService.appDrawerLoader = appDrawerLoader;
        }

        AppDrawerPopout {
            id: appDrawerPopout
            onPopoutClosed: PopoutService.unloadAppDrawer()

            Component.onCompleted: {
                PopoutService.appDrawerPopout = appDrawerPopout;
            }
        }
    }

    LazyLoader {
        id: dankLauncherV2ModalLoader

        active: false

        Component.onCompleted: {
            PopoutService.dankLauncherV2ModalLoader = dankLauncherV2ModalLoader;
        }

        DLauncherV2Modal {
            id: dankLauncherV2Modal

            Component.onCompleted: {
                PopoutService.dankLauncherV2Modal = dankLauncherV2Modal;
                PopoutService._onDankLauncherV2ModalLoaded();
            }
        }
    }

    LazyLoader {
        id: spotlightBarModalLoader

        active: false

        Component.onCompleted: {
            PopoutService.spotlightBarModalLoader = spotlightBarModalLoader;
        }

        DLauncherV2ModalHost {
            id: spotlightBarModal
            connected: false
            spotlight: true

            Component.onCompleted: {
                PopoutService.spotlightBarModal = spotlightBarModal;
                PopoutService._onSpotlightBarModalLoaded();
            }
        }
    }

    LazyLoader {
        id: clipboardHistoryPopoutLoader

        active: false

        Component.onCompleted: {
            PopoutService.clipboardHistoryPopoutLoader = clipboardHistoryPopoutLoader;
        }

        ClipboardHistoryPopout {
            id: clipboardHistoryPopout
            onPopoutClosed: PopoutService.unloadClipboardHistoryPopout()

            Component.onCompleted: {
                PopoutService.clipboardHistoryPopout = clipboardHistoryPopout;
            }
        }
    }

    MuxModal {
        id: muxModal
    }

    ClipboardHistoryModal {
        id: clipboardHistoryModalPopup

        Component.onCompleted: {
            PopoutService.clipboardHistoryModal = clipboardHistoryModalPopup;
        }
    }

    NotificationModal {
        id: notificationModal

        Component.onCompleted: {
            PopoutService.notificationModal = notificationModal;
        }
    }

    LazyLoader {
        id: browserPickerModalLoader
        active: false
        readonly property BrowserPickerModal loadedModal: item as BrowserPickerModal

        BrowserPickerModal {
            id: browserPickerModal
        }
    }

    LazyLoader {
        id: filePickerModalLoader
        active: false
        readonly property AppPickerModal loadedModal: item as AppPickerModal

        AppPickerModal {
            id: filePickerModal
            title: I18n.tr("Open with", "app picker title, followed by a list of apps") + "…"
            viewMode: SettingsData.appPickerViewMode || "grid"

            onViewModeChanged: {
                SettingsData.set("appPickerViewMode", viewMode);
            }

            function shellEscape(str) {
                return "'" + str.replace(/'/g, "'\\''") + "'";
            }

            onApplicationSelected: (app, filePath) => {
                if (!app)
                    return;
                const entry = SessionService.resolveDesktopId(app.appId);
                if (entry) {
                    SessionService.launchDesktopEntry(entry, false, [filePath]);
                    return;
                }
                let cmd = app.exec || "";
                const escapedPath = shellEscape(filePath);
                const escapedUri = shellEscape("file://" + filePath);

                let hasField = false;
                if (cmd.includes("%f")) {
                    cmd = cmd.replace("%f", escapedPath);
                    hasField = true;
                } else if (cmd.includes("%F")) {
                    cmd = cmd.replace("%F", escapedPath);
                    hasField = true;
                } else if (cmd.includes("%u")) {
                    cmd = cmd.replace("%u", escapedUri);
                    hasField = true;
                } else if (cmd.includes("%U")) {
                    cmd = cmd.replace("%U", escapedUri);
                    hasField = true;
                }

                cmd = cmd.replace(/%[ikc]/g, "");

                if (!hasField) {
                    cmd += " " + escapedPath;
                }

                log.debug("FilePicker: Launching", cmd);

                Quickshell.execDetached({
                    command: ["sh", "-c", cmd]
                });
            }
        }
    }

    Connections {
        target: DMSService
        function onOpenUrlRequested(url) {
            if (url.startsWith("dms://theme/install/")) {
                const themeId = url.replace("dms://theme/install/", "").split(/[?#]/)[0];
                if (themeId) {
                    PopoutService.pendingThemeInstall = themeId;
                    PopoutService.openSettingsWithTab("theme");
                }
                return;
            }
            if (url.startsWith("dms://plugin/install/")) {
                const pluginId = url.replace("dms://plugin/install/", "").split(/[?#]/)[0];
                if (pluginId) {
                    PopoutService.pendingPluginInstall = pluginId;
                    PopoutService.openSettingsWithTab("plugins");
                }
                return;
            }
            if (url.startsWith("dms://wallpaper/install/")) {
                const payload = url.replace("dms://wallpaper/install/", "").split(/[?#]/)[0];
                if (payload) {
                    PopoutService.pendingWallpaperInstall = payload;
                    PopoutService.openSettingsWithTab("wallpaper");
                }
                return;
            }
            browserPickerModalLoader.active = true;
            const picker = browserPickerModalLoader.loadedModal;
            if (!picker)
                return;
            picker.url = url;
            picker.open();
        }

        function onAppPickerRequested(data) {
            root.log.debug("App picker requested with data:", JSON.stringify(data));

            if (!data || !data.target) {
                root.log.warn("Invalid app picker request data");
                return;
            }

            filePickerModalLoader.active = true;
            const picker = filePickerModalLoader.loadedModal;
            if (!picker)
                return;
            picker.targetData = data.target;
            picker.targetDataLabel = data.requestType || "file";
            picker.mimeType = data.mimeType || "";
            picker.rememberMimeTypes = [];
            picker.categoryFilter = data.categories?.length > 0 ? data.categories : [];
            picker.usageHistoryKey = "filePickerUsageHistory";
            picker.open();
        }
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            root.pendingOsdResumeReloads = 2;
            osdResumeRecreateTimer.interval = 400;
            osdResumeRecreateTimer.restart();
        }
    }

    ColorPickerModal {
        id: colorPickerModal

        Component.onCompleted: {
            PopoutService.colorPickerModal = colorPickerModal;
        }
    }

    LazyLoader {
        id: workspaceRenameModalLoader

        active: false

        WorkspaceRenameModal {
            id: workspaceRenameModal
        }
    }

    LazyLoader {
        id: windowRuleModalLoader

        active: false

        Component.onCompleted: PopoutService.windowRuleModalLoader = windowRuleModalLoader

        WindowRuleModal {
            id: windowRuleModal
        }
    }

    LazyLoader {
        id: processListModalLoader

        active: false

        Component.onCompleted: PopoutService.processListModalLoader = processListModalLoader

        ProcessListModal {
            id: processListModal
            property bool wasShown: false

            Component.onCompleted: {
                PopoutService.processListModal = processListModal;
            }

            onVisibleChanged: {
                if (visible) {
                    wasShown = true;
                } else if (wasShown) {
                    PopoutService.unloadProcessListModal();
                }
            }
        }
    }

    LazyLoader {
        id: systemUpdateModalLoader

        active: false

        Component.onCompleted: PopoutService.systemUpdateModalLoader = systemUpdateModalLoader

        SystemUpdateModal {
            id: systemUpdateModal
            property bool wasShown: false

            Component.onCompleted: PopoutService.systemUpdateModal = systemUpdateModal

            onVisibleChanged: {
                if (systemUpdateModal.visible) {
                    wasShown = true;
                } else if (wasShown) {
                    PopoutService.unloadSystemUpdateModal();
                }
            }
        }
    }

    LazyLoader {
        id: systemUpdateLoader

        active: false

        Component.onCompleted: {
            PopoutService.systemUpdateLoader = systemUpdateLoader;
        }

        SystemUpdatePopout {
            id: systemUpdatePopout
            onPopoutClosed: {
                if (systemUpdatePopout._reopenAfterUpgrade) {
                    return;
                }
                PopoutService.unloadSystemUpdate();
            }

            Component.onCompleted: {
                PopoutService.systemUpdatePopout = systemUpdatePopout;
            }
        }
    }

    Variants {
        id: notepadSlideoutVariants
        model: SettingsData.getFilteredScreens("notepad")

        delegate: DSlideout {
            id: notepadSlideout
            title: I18n.tr("Notepad")
            slideoutWidth: 480
            expandable: true
            expandedWidthValue: 960
            edgeGap: SettingsData.notepadEffectiveEdgeGap
            frameSurfaceEnabled: true
            slideEdge: SettingsData.notepadSlideoutSide
            customTransparency: Theme.notepadTransparency

            onIsVisibleChanged: {
                if (isVisible)
                    PopoutService.notepadPopout?.hide();
            }

            content: Component {
                Notepad {
                    slideout: notepadSlideout
                    onHideRequested: notepadSlideout.hide()
                    onPopoutRequested: {
                        notepadSlideout.hide();
                        PopoutService.openNotepadPopout();
                    }
                }
            }

            function toggle() {
                if (isVisible) {
                    hide();
                } else {
                    show();
                }
            }
        }

        onInstancesChanged: PopoutService.notepadSlideouts = instances
        Component.onCompleted: PopoutService.notepadSlideouts = instances
    }

    LazyLoader {
        id: notepadPopoutLoader
        active: false

        Component.onCompleted: {
            PopoutService.notepadPopoutLoader = notepadPopoutLoader;
        }

        onActiveChanged: {
            if (active && item) {
                PopoutService.notepadPopout = item;
                PopoutService._onNotepadPopoutLoaded();
            }
        }

        NotepadPopoutWindow {}
    }

    LazyLoader {
        id: powerMenuModalLoader

        active: false

        Component.onCompleted: {
            PopoutService.powerMenuModalLoader = powerMenuModalLoader;
        }

        PowerMenuModal {
            id: powerMenuModal

            onPowerActionRequested: (action, title, message) => root._executePowerAction(action)
            onLockRequested: root._lockFromPowerMenu()
            onSwitchUserRequested: root._switchUserFromPowerMenu()

            Component.onCompleted: {
                PopoutService.powerMenuModal = powerMenuModal;
            }
        }
    }

    function _executePowerAction(action) {
        PopoutService.closeControlCenter();
        SessionService.executePowerAction(action);
    }

    function _lockFromPowerMenu() {
        PopoutService.closeControlCenter();
        lock.activate();
    }

    function _switchUserFromPowerMenu() {
        PopoutService.openSwitchUser();
    }

    LazyLoader {
        id: powerMenuPopoutLoader

        active: false

        Component.onCompleted: {
            PopoutService.powerMenuPopoutLoader = powerMenuPopoutLoader;
        }

        PowerMenuPopout {
            id: powerMenuPopout

            onPowerActionRequested: action => root._executePowerAction(action)
            onLockRequested: root._lockFromPowerMenu()
            onSwitchUserRequested: root._switchUserFromPowerMenu()
            onPopoutClosed: PopoutService.unloadPowerMenuPopout()

            Component.onCompleted: {
                PopoutService.powerMenuPopout = powerMenuPopout;
            }
        }
    }

    LazyLoader {
        id: durationPopoutLoader

        active: false

        Component.onCompleted: {
            PopoutService.durationPopoutLoader = durationPopoutLoader;
        }

        DurationPopout {
            id: durationPopout
            onPopoutClosed: PopoutService.unloadDurationPopout()

            Component.onCompleted: {
                PopoutService.durationPopout = durationPopout;
            }
        }
    }

    LazyLoader {
        id: switchUserModalLoader

        active: false
        readonly property SwitchUserModal loadedModal: item as SwitchUserModal

        Component.onCompleted: PopoutService.switchUserModalLoader = switchUserModalLoader

        SwitchUserModal {
            id: switchUserModal
        }
    }

    LazyLoader {
        id: hyprKeybindsModalLoader

        active: false

        Component.onCompleted: PopoutService.keybindsModalLoader = hyprKeybindsModalLoader

        KeybindsModal {
            id: keybindsModal

            Component.onCompleted: PopoutService.keybindsModal = keybindsModal
        }
    }

    LazyLoader {
        id: powerProfileModalLoader

        active: false

        PowerProfileModal {
            id: powerProfileModal

            Component.onCompleted: {
                PopoutService.powerProfileModal = powerProfileModal;
            }
        }

        Component.onCompleted: {
            PopoutService.powerProfileModalLoader = powerProfileModalLoader;
        }
    }

    DMSShellIPC {
        processListModalLoaderRef: processListModalLoader
        controlCenterLoaderRef: controlCenterLoader
        dankDashPopoutLoaderRef: dankDashPopoutLoader
        notepadSlideoutVariantsRef: notepadSlideoutVariants
        hyprKeybindsModalLoaderRef: hyprKeybindsModalLoader
        dankBarRepeater: root.core?.dankBarRepeater ?? null
        hyprlandOverviewLoader: root.core?.hyprlandOverviewLoader ?? null
        workspaceRenameModalLoaderRef: workspaceRenameModalLoader
        windowRuleModalLoaderRef: windowRuleModalLoader
        markupOverlayLoaderRef: markupOverlayLoader
    }

    LazyLoader {
        id: markupOverlayLoader

        active: false

        MarkupOverlay {
            onDismissed: markupOverlayLoader.active = false
        }
    }

    Variants {
        model: SettingsData.getFilteredScreens("toast")

        delegate: Toast {}
    }

    Loader {
        id: osdSurfacesLoader
        active: root.osdSurfacesLoaded
        asynchronous: false

        sourceComponent: Component {
            Item {
                Variants {
                    model: SettingsData.osdVolumeEnabled ? root.legacySystemLevelOsdScreens : []

                    delegate: VolumeOSD {}
                }

                Variants {
                    model: SettingsData.osdMediaVolumeEnabled ? SettingsData.getFilteredScreens("osd") : []

                    delegate: MediaVolumeOSD {}
                }

                Variants {
                    model: SettingsData.osdMediaPlaybackEnabled ? SettingsData.getFilteredScreens("osd") : []

                    delegate: MediaPlaybackOSD {}
                }

                Variants {
                    model: (SettingsData.osdMicMuteEnabled || SettingsData.osdMicVolumeEnabled) ? root.legacySystemLevelOsdScreens : []

                    delegate: MicVolumeOSD {}
                }

                Variants {
                    model: SettingsData.osdBrightnessEnabled ? root.legacySystemLevelOsdScreens : []

                    delegate: BrightnessOSD {}
                }

                Variants {
                    model: SettingsData.osdIdleInhibitorEnabled ? root.legacySystemLevelOsdScreens : []

                    delegate: IdleInhibitorOSD {}
                }

                Variants {
                    model: SettingsData.osdPowerProfileEnabled ? root.legacySystemLevelOsdScreens : []

                    delegate: PowerProfileOSD {}
                }

                Variants {
                    model: SettingsData.osdCapsLockEnabled ? root.legacySystemLevelOsdScreens : []

                    delegate: CapsLockOSD {}
                }

                Variants {
                    model: (SettingsData.osdTouchpadEnabled && CompositorService.isNiri) ? root.legacySystemLevelOsdScreens : []

                    delegate: TouchpadOSD {}
                }

                Variants {
                    model: SettingsData.osdAudioOutputEnabled ? SettingsData.getFilteredScreens("osd") : []

                    delegate: AudioOutputOSD {}
                }

                Variants {
                    model: SettingsData.osdWorkspaceEnabled ? SettingsData.getFilteredScreens("osd") : []

                    delegate: WorkspaceOSD {}
                }
            }
        }
    }

    LazyLoader {
        id: niriOverviewOverlayLoader
        active: CompositorService.isNiri && SettingsData.niriOverviewOverlayEnabled
        component: NiriOverviewOverlay {
            id: niriOverviewOverlay
        }
    }

    Loader {
        id: greeterLoader
        active: false
        readonly property GreeterModal loadedModal: item as GreeterModal
        sourceComponent: GreeterModal {
            onGreeterCompleted: greeterLoader.active = false
            Component.onCompleted: show()
        }

        Component.onCompleted: {
            if (FirstLaunchService.shouldShowGreeter)
                active = true;
        }

        Connections {
            target: FirstLaunchService
            function onGreeterRequested() {
                if (greeterLoader.active && greeterLoader.loadedModal) {
                    greeterLoader.loadedModal.show();
                    return;
                }
                greeterLoader.active = true;
            }
        }
    }

    Loader {
        id: changelogLoader
        active: false
        readonly property ChangelogModal loadedModal: item as ChangelogModal
        sourceComponent: ChangelogModal {
            onChangelogDismissed: changelogLoader.active = false
            Component.onCompleted: show()
        }

        Component.onCompleted: {
            if (ChangelogService.shouldShowChangelog)
                active = true;
        }

        Connections {
            target: ChangelogService
            function onChangelogRequested() {
                if (changelogLoader.active && changelogLoader.loadedModal) {
                    changelogLoader.loadedModal.show();
                    return;
                }
                changelogLoader.active = true;
            }
        }
    }
}
