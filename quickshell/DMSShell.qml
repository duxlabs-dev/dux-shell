pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals
import qs.Modules
import qs.Modules.Dock
import qs.Modules.Lock
import qs.Widgets
import qs.Modules.Notifications.Popup
import qs.Modules.OSD
import qs.Modules.Settings.DisplayConfig
import qs.Modules.Wellbeing
import qs.Services

Item {
    id: root
    readonly property var log: Log.scoped("DMSShell")
    readonly property var _nightModeServiceRef: NightModeService
    readonly property var _brightnessServiceRef: BrightnessService
    readonly property var _refreshRateServiceRef: RefreshRateService

    property var core: null
    readonly property bool globalShortcutPromptPending: GlobalShortcutsService.prompts.length > 0

    onGlobalShortcutPromptPendingChanged: {
        if (globalShortcutPromptPending)
            globalShortcutsModalLoader.active = true;
    }

    property bool osdSurfacesLoaded: false
    readonly property var notificationPopupScreens: {
        const screens = SettingsData.notificationFocusedMonitor ? ShellLayout.realScreens : SettingsData.getFilteredScreens("notifications");
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

    Variants {
        model: ShellLayout.realScreens

        DPopoutSurface {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        model: ShellLayout.realScreens

        DTooltipSurface {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        model: ShellLayout.realScreens

        DContextMenuSurface {
            required property var modelData
            screen: modelData
        }
    }

    Loader {
        active: SettingsData.desktopWidgetInstances.concat(SettingsData.lockScreenWidgetInstances).some(instance => instance.enabled)
        source: "Modules/DesktopWidgetLayer.qml"
    }

    Loader {
        active: DesktopWidgetRegistry.editing
        source: "Modules/DesktopWidgetEditor.qml"
    }

    LazyLoader {
        id: desktopContextMenuLoader
        active: false
        source: "Modules/DesktopContextMenu.qml"
        Component.onCompleted: PopoutService.desktopContextMenuLoader = desktopContextMenuLoader
        onItemChanged: PopoutService.desktopContextMenu = item
    }

    Lock {
        id: lock
    }

    Variants {
        model: ShellLayout.realScreens

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
        model: ShellLayout.realScreens

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

    Variants {
        model: ShellLayout.realScreens

        // LazyLoader stays unloaded when this binding throws; a Loader defaults to active and would map the surface
        delegate: LazyLoader {
            id: breakOverlayLoader
            required property var modelData
            active: BreakReminderService.breakShown

            BreakOverlay {
                screen: breakOverlayLoader.modelData
            }
        }
    }

    Connections {
        target: root.core

        function on_BarLayoutStateJsonChanged() {
            dockRecreateDebounce.restart();
        }

        function onSurfaceRecoveryPass() {
            dockRecreateDebounce.restart();
        }
    }

    property bool dockEnabled: false

    Timer {
        id: dockRecreateDebounce
        interval: Timing.settleLong
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
        interval: Timing.settleLong
        repeat: false
        onTriggered: {
            AudioService.playLoginSoundIfApplicable();
        }
    }

    Timer {
        id: osdStartupTimer
        interval: Timing.settleSlow
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
        BreakReminderService.enabled;
    }

    Loader {
        id: dockLoader
        active: root.dockEnabled
        asynchronous: false

        sourceComponent: Dock {
            contextMenu: dockContextMenuLoader.item ? dockContextMenuLoader.item : null
            trashContextMenu: dockTrashContextMenuLoader.item ? dockTrashContextMenuLoader.item : null
        }
    }

    Loader {
        id: dankDashPopoutLoader

        active: false
        asynchronous: false
        source: "Modules/DDash/DDashPopout.qml"

        Component.onCompleted: {
            PopoutService.dankDashPopoutLoader = dankDashPopoutLoader;
        }

        onLoaded: {
            if (item) {
                PopoutService.dankDashPopout = item;
                PopoutService._onDankDashPopoutLoaded();
            }
        }

        Connections {
            target: dankDashPopoutLoader.item

            function onPopoutClosed() {
                PopoutService._scheduleUnload("dankDash");
            }
        }
    }

    LazyLoader {
        id: dockContextMenuLoader

        active: false
        source: "Modules/Dock/DockContextMenu.qml"
    }

    LazyLoader {
        id: dockTrashContextMenuLoader

        active: false
        source: "Modules/Dock/DockTrashContextMenu.qml"
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

    LazyLoader {
        id: emptyTrashConfirmLoader
        active: false
        source: "Modals/Common/ConfirmModal.qml"
        readonly property var loadedModal: item
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
                danger: true,
                onConfirm: () => TrashService.emptyTrash()
            });
        }
    }

    LazyLoader {
        id: uninstallAppConfirmLoader
        active: false
        source: "Modals/Common/ConfirmModal.qml"
        readonly property var loadedModal: item
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
                        danger: true,
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
        source: "Modules/Notifications/Center/NotificationCenterPopout.qml"

        Component.onCompleted: {
            PopoutService.notificationCenterLoader = notificationCenterLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.notificationCenterPopout = item;
        }
    }

    Connections {
        target: notificationCenterLoader.item
        function onPopoutClosed() {
            PopoutService.unloadNotificationCenter();
        }
    }

    Variants {
        model: root.notificationPopupScreens

        delegate: NotificationPopupManager {}
    }

    LazyLoader {
        id: controlCenterLoader

        active: false
        source: "Modules/ControlCenter/ControlCenterPopout.qml"

        property var modalRef: colorPickerModal
        property LazyLoader powerModalLoaderRef: powerMenuModalLoader

        Component.onCompleted: {
            PopoutService.controlCenterLoader = controlCenterLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.controlCenterPopout = item;
        }
    }

    Binding {
        target: controlCenterLoader.item
        property: "colorPickerModal"
        value: controlCenterLoader.modalRef
    }

    Binding {
        target: controlCenterLoader.item
        property: "powerMenuModalLoader"
        value: controlCenterLoader.powerModalLoaderRef
    }

    Connections {
        target: controlCenterLoader.item
        function onPopoutClosed() {
            PopoutService.unloadControlCenter();
        }

        function onLockRequested() {
            lock.activate();
        }
    }

    LazyLoader {
        id: wifiPasswordModalLoader
        active: false
        source: "Modals/WifiPasswordModal.qml"
        readonly property var loadedModal: item

        Component.onCompleted: {
            PopoutService.wifiPasswordModalLoader = wifiPasswordModalLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.wifiPasswordModal = item;
        }
    }

    LazyLoader {
        id: wifiQRCodeModalLoader
        active: false
        source: "Modals/WifiQRCodeModal.qml"

        Component.onCompleted: {
            PopoutService.wifiQRCodeModalLoader = wifiQRCodeModalLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.wifiQRCodeModal = item;
        }
    }

    LazyLoader {
        id: qrGeneratorModalLoader
        active: false
        source: "Modals/QRGeneratorModal.qml"

        Component.onCompleted: {
            PopoutService.qrGeneratorModalLoader = qrGeneratorModalLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.qrGeneratorModal = item;
        }
    }

    LazyLoader {
        id: polkitAuthModalLoader
        active: false
        source: "Modals/PolkitAuthModal.qml"
        readonly property var loadedModal: item
        onItemChanged: {
            if (!item)
                return;
            PopoutService.polkitAuthModal = item;
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
        source: "Modals/BluetoothPairingModal.qml"

        Component.onCompleted: PopoutService.bluetoothPairingModalLoader = bluetoothPairingModalLoader
        onItemChanged: {
            if (!item)
                return;
            PopoutService.bluetoothPairingModal = item;
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
        source: "Modals/NetworkInfoModal.qml"
        onItemChanged: {
            if (!item)
                return;
            PopoutService.networkInfoModal = item;
        }
    }

    LazyLoader {
        id: batteryPopoutLoader

        active: false
        source: "Modules/DBar/Popouts/BatteryPopout.qml"

        Component.onCompleted: {
            PopoutService.batteryPopoutLoader = batteryPopoutLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.batteryPopout = item;
        }
    }

    Connections {
        target: batteryPopoutLoader.item
        function onPopoutClosed() {
            PopoutService.unloadBattery();
        }
    }

    LazyLoader {
        id: layoutPopoutLoader

        active: false
        source: "Modules/DBar/Popouts/DWLLayoutPopout.qml"

        Component.onCompleted: {
            PopoutService.layoutPopoutLoader = layoutPopoutLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.layoutPopout = item;
        }
    }

    Connections {
        target: layoutPopoutLoader.item
        function onPopoutClosed() {
            PopoutService.unloadLayoutPopout();
        }
    }

    LazyLoader {
        id: vpnPopoutLoader

        active: false
        source: "Modules/DBar/Popouts/VpnPopout.qml"

        Component.onCompleted: {
            PopoutService.vpnPopoutLoader = vpnPopoutLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.vpnPopout = item;
        }
    }

    Connections {
        target: vpnPopoutLoader.item
        function onPopoutClosed() {
            PopoutService.unloadVpn();
        }
    }

    LazyLoader {
        id: colorPickerPopoutLoader

        active: false
        source: "Modules/DBar/Popouts/ColorPickerPopout.qml"

        Component.onCompleted: {
            PopoutService.colorPickerPopoutLoader = colorPickerPopoutLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.colorPickerPopout = item;
        }
    }

    Connections {
        target: colorPickerPopoutLoader.item
        function onPopoutClosed() {
            PopoutService.unloadColorPicker();
        }
    }

    LazyLoader {
        id: processListPopoutLoader

        active: false
        source: "Modules/ProcessList/ProcessListPopout.qml"

        Component.onCompleted: {
            PopoutService.processListPopoutLoader = processListPopoutLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.processListPopout = item;
        }
    }

    Connections {
        target: processListPopoutLoader.item
        function onPopoutClosed() {
            PopoutService.unloadProcessListPopout();
        }
    }

    LazyLoader {
        id: settingsModalLoader

        property bool wasShown: false

        active: false
        source: "Modals/Settings/SettingsModal.qml"
        readonly property var loadedModal: item
        onItemChanged: wasShown = false

        Component.onCompleted: {
            PopoutService.settingsModalLoader = settingsModalLoader;
        }

        onActiveChanged: {
            if (active && item) {
                PopoutService.settingsModal = item;
                PopoutService._onSettingsModalLoaded();
            }
        }
    }

    Connections {
        target: settingsModalLoader.item

        function onVisibleChanged() {
            if (settingsModalLoader.loadedModal.visible) {
                settingsModalLoader.wasShown = true;
                return;
            }
            if (settingsModalLoader.wasShown)
                Qt.callLater(() => PopoutService.unloadSettingsNow());
        }
    }

    LazyLoader {
        id: appDrawerLoader

        active: false
        source: "Modules/AppDrawer/AppDrawerPopout.qml"

        Component.onCompleted: {
            PopoutService.appDrawerLoader = appDrawerLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.appDrawerPopout = item;
        }
    }

    Connections {
        target: appDrawerLoader.item
        function onPopoutClosed() {
            PopoutService.unloadAppDrawer();
        }
    }

    LazyLoader {
        id: dankLauncherV2ModalLoader

        active: false
        source: "Modals/DLauncherV2/DLauncherV2Modal.qml"

        Component.onCompleted: {
            PopoutService.dankLauncherV2ModalLoader = dankLauncherV2ModalLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.dankLauncherV2Modal = item;
            PopoutService._onDankLauncherV2ModalLoaded();
        }
    }

    LazyLoader {
        id: spotlightBarModalLoader

        active: false
        source: "Modals/DLauncherV2/DLauncherV2ModalHost.qml"

        Component.onCompleted: {
            PopoutService.spotlightBarModalLoader = spotlightBarModalLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.spotlightBarModal = item;
            PopoutService._onSpotlightBarModalLoaded();
        }
    }

    Binding {
        target: spotlightBarModalLoader.item
        property: "connected"
        value: false
    }

    Binding {
        target: spotlightBarModalLoader.item
        property: "spotlight"
        value: true
    }

    LazyLoader {
        id: clipboardHistoryPopoutLoader

        active: false
        source: "Modals/Clipboard/ClipboardHistoryPopout.qml"

        Component.onCompleted: {
            PopoutService.clipboardHistoryPopoutLoader = clipboardHistoryPopoutLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.clipboardHistoryPopout = item;
        }
    }

    Connections {
        target: clipboardHistoryPopoutLoader.item
        function onPopoutClosed() {
            PopoutService.unloadClipboardHistoryPopout();
        }
    }

    LazyLoader {
        id: muxModalLoader
        active: false
        source: "Modals/MuxModal.qml"
    }

    MuxIpc {
        loader: muxModalLoader
    }

    LazyLoader {
        id: clipboardHistoryModalLoader
        active: false
        source: "Modals/Clipboard/ClipboardHistoryModal.qml"
        Component.onCompleted: PopoutService.clipboardHistoryModalLoader = clipboardHistoryModalLoader
        onItemChanged: PopoutService.clipboardHistoryModal = item
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
        source: "Modals/BrowserPickerModal.qml"
        readonly property var loadedModal: item
    }

    LazyLoader {
        id: filePickerModalLoader
        active: false
        source: "Modals/OpenWithModal.qml"
        readonly property var loadedModal: item
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

    ColorPickerModal {
        id: colorPickerModal

        Component.onCompleted: {
            PopoutService.colorPickerModal = colorPickerModal;
        }
    }

    LazyLoader {
        id: workspaceRenameModalLoader

        active: false
        source: "Modals/WorkspaceRenameModal.qml"
    }

    LazyLoader {
        id: globalShortcutsModalLoader

        active: false
        source: "Modals/GlobalShortcutsModal.qml"
    }

    LazyLoader {
        id: windowRuleModalLoader

        active: false
        source: "Modals/WindowRuleModal.qml"

        Component.onCompleted: PopoutService.windowRuleModalLoader = windowRuleModalLoader
    }

    LazyLoader {
        id: processListModalLoader

        property bool wasShown: false

        active: false
        source: "Modals/ProcessListModal.qml"
        readonly property var loadedModal: item

        Component.onCompleted: PopoutService.processListModalLoader = processListModalLoader
        onItemChanged: {
            wasShown = false;
            if (item)
                PopoutService.processListModal = item;
        }
    }

    Connections {
        target: processListModalLoader.item

        function onVisibleChanged() {
            if (processListModalLoader.loadedModal.visible) {
                processListModalLoader.wasShown = true;
                return;
            }
            if (processListModalLoader.wasShown)
                PopoutService.unloadProcessListModal();
        }
    }

    LazyLoader {
        id: systemUpdateModalLoader

        property bool wasShown: false

        active: false
        source: "Modals/SystemUpdateModal.qml"
        readonly property var loadedModal: item

        Component.onCompleted: PopoutService.systemUpdateModalLoader = systemUpdateModalLoader
        onItemChanged: {
            wasShown = false;
            if (item)
                PopoutService.systemUpdateModal = item;
        }
    }

    Connections {
        target: systemUpdateModalLoader.item

        function onVisibleChanged() {
            if (systemUpdateModalLoader.loadedModal.visible) {
                systemUpdateModalLoader.wasShown = true;
                return;
            }
            if (systemUpdateModalLoader.wasShown)
                PopoutService.unloadSystemUpdateModal();
        }
    }

    LazyLoader {
        id: systemUpdateLoader

        active: false
        source: "Modules/DBar/Popouts/SystemUpdatePopout.qml"
        readonly property var loadedPopout: item

        Component.onCompleted: {
            PopoutService.systemUpdateLoader = systemUpdateLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.systemUpdatePopout = item;
        }
    }

    Connections {
        target: systemUpdateLoader.item
        function onPopoutClosed() {
            if (systemUpdateLoader.loadedPopout._reopenAfterUpgrade) {
                return;
            }
            PopoutService.unloadSystemUpdate();
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

            contentSource: Qt.resolvedUrl("Modules/Notepad/NotepadSlideoutContent.qml")
            contentProperties: ({
                    slideout: notepadSlideout
                })

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
        source: "Modules/Notepad/NotepadPopoutWindow.qml"

        Component.onCompleted: {
            PopoutService.notepadPopoutLoader = notepadPopoutLoader;
        }

        onActiveChanged: {
            if (active && item) {
                PopoutService.notepadPopout = item;
                PopoutService._onNotepadPopoutLoaded();
            }
        }
    }

    LazyLoader {
        id: powerMenuModalLoader

        active: false
        source: "Modals/PowerMenuModal.qml"

        Component.onCompleted: {
            PopoutService.powerMenuModalLoader = powerMenuModalLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.powerMenuModal = item;
        }
    }

    Connections {
        target: powerMenuModalLoader.item
        function onPowerActionRequested(action, title, message) {
            root._executePowerAction(action);
        }

        function onLockRequested() {
            root._lockFromPowerMenu();
        }

        function onSwitchUserRequested() {
            root._switchUserFromPowerMenu();
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
        source: "Modules/DBar/Popouts/PowerMenuPopout.qml"

        Component.onCompleted: {
            PopoutService.powerMenuPopoutLoader = powerMenuPopoutLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.powerMenuPopout = item;
        }
    }

    Connections {
        target: powerMenuPopoutLoader.item
        function onPowerActionRequested(action) {
            root._executePowerAction(action);
        }

        function onLockRequested() {
            root._lockFromPowerMenu();
        }

        function onSwitchUserRequested() {
            root._switchUserFromPowerMenu();
        }

        function onPopoutClosed() {
            PopoutService.unloadPowerMenuPopout();
        }
    }

    LazyLoader {
        id: durationPopoutLoader

        active: false
        source: "Modules/DBar/Popouts/DurationPopout.qml"

        Component.onCompleted: {
            PopoutService.durationPopoutLoader = durationPopoutLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.durationPopout = item;
        }
    }

    Connections {
        target: durationPopoutLoader.item
        function onPopoutClosed() {
            PopoutService.unloadDurationPopout();
        }
    }

    LazyLoader {
        id: switchUserModalLoader

        active: false
        source: "Modals/SwitchUserModal.qml"
        readonly property var loadedModal: item

        Component.onCompleted: PopoutService.switchUserModalLoader = switchUserModalLoader
    }

    LazyLoader {
        id: hyprKeybindsModalLoader

        active: false
        source: "Modals/KeybindsModal.qml"

        Component.onCompleted: PopoutService.keybindsModalLoader = hyprKeybindsModalLoader
        onItemChanged: {
            if (!item)
                return;
            PopoutService.keybindsModal = item;
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
        id: shellIpc

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
        annotateOverlayLoaderRef: annotateOverlayLoader
    }

    LazyLoader {
        id: markupOverlayLoader

        active: false
        source: "Modules/Markup/MarkupOverlay.qml"
    }

    Connections {
        target: markupOverlayLoader.item
        function onDismissed() {
            markupOverlayLoader.active = false;
        }
    }

    LazyLoader {
        id: annotateOverlayLoader

        active: false
        source: "Modules/Markup/AnnotateOverlay.qml"
    }

    Connections {
        target: annotateOverlayLoader.item
        function onDismissed() {
            annotateOverlayLoader.active = false;
        }
    }

    Variants {
        model: SettingsData.getFilteredScreens("toast")

        delegate: Toast {}
    }

    LazyLoader {
        active: ConfigProfileService.screenshotPending

        ProfileCaptureBar {}
    }

    LazyLoader {
        id: profilePickerModalLoader

        active: false
        source: "Modals/ProfilePickerModal.qml"

        Component.onCompleted: {
            PopoutService.profilePickerModalLoader = profilePickerModalLoader;
        }
        onItemChanged: {
            if (!item)
                return;
            PopoutService.profilePickerModal = item;
        }
    }

    LazyLoader {
        active: ConfigProfileService.switching

        ProfileSwitchOverlay {}
    }

    Connections {
        target: ConfigProfileService
        function onPickerToggleRequested() {
            if (SettingsData.configProfilePickerView !== "dash")
                PopoutService.toggleProfilePicker();
            else if (PopoutService.dankDashPopout?.dashVisible && PopoutService.dankDashPopout.activeTabId !== "profiles")
                shellIpc.openDash("profiles", "");
            else if (!shellIpc.toggleDash("profiles", ""))
                PopoutService.toggleProfilePicker();
        }

        // The user closed Settings to set up the screen, so bring back the profile being edited.
        function onScreenshotEnded(id) {
            if (PopoutService.settingsModal?.shouldBeVisible ?? false)
                return;
            ConfigProfileService.selectForSettings(id, false);
            PopoutService.openSettingsWithTab("profile_edit");
        }
    }

    Loader {
        id: osdSurfacesLoader
        active: root.osdSurfacesLoaded
        asynchronous: false

        sourceComponent: Component {
            Item {
                Variants {
                    model: SettingsData.getFilteredScreens("osd")

                    DOSDSurface {
                        required property var modelData
                        screen: modelData
                    }
                }

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
                    model: SettingsData.osdDoNotDisturbEnabled ? root.legacySystemLevelOsdScreens : []

                    delegate: DoNotDisturbOSD {}
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
                    model: SettingsData.osdNumLockEnabled ? root.legacySystemLevelOsdScreens : []

                    delegate: NumLockOSD {}
                }

                Variants {
                    model: (SettingsData.osdKeyboardLayoutEnabled && KeyboardLayoutService.available) ? SettingsData.getFilteredScreens("osd") : []

                    delegate: KeyboardLayoutOSD {}
                }

                Variants {
                    model: (SettingsData.osdInputMethodEnabled && Fcitx5Service.available) ? SettingsData.getFilteredScreens("osd") : []

                    delegate: InputMethodOSD {}
                }

                Variants {
                    model: (SettingsData.osdTouchpadEnabled && CompositorService.isNiri) ? root.legacySystemLevelOsdScreens : []

                    delegate: TouchpadOSD {}
                }

                Variants {
                    model: SettingsData.osdAirplaneModeEnabled ? root.legacySystemLevelOsdScreens : []

                    delegate: AirplaneModeOSD {}
                }

                Variants {
                    model: SettingsData.osdAudioOutputEnabled ? SettingsData.getFilteredScreens("osd") : []

                    delegate: AudioOutputOSD {}
                }

                Variants {
                    model: SettingsData.osdWorkspaceEnabled ? SettingsData.getFilteredScreens("osd") : []

                    delegate: WorkspaceOSD {}
                }

                Variants {
                    model: SettingsData.wellbeingBreaksEnabled ? SettingsData.getFilteredScreens("osd") : []

                    delegate: BreakWarningOSD {}
                }
            }
        }
    }

    LazyLoader {
        id: niriOverviewOverlayLoader
        active: CompositorService.isNiri && SettingsData.niriOverviewOverlayEnabled
        source: "Modules/WorkspaceOverlays/NiriOverviewOverlay.qml"
    }

    Loader {
        id: greeterLoader
        active: false
        readonly property var loadedModal: item
        source: "Modals/Greeter/GreeterModal.qml"
        onLoaded: loadedModal.show()

        Connections {
            target: greeterLoader.item

            function onGreeterCompleted() {
                greeterLoader.active = false;
            }
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
        readonly property var loadedModal: item
        source: "Modals/Changelog/ChangelogModal.qml"
        onLoaded: loadedModal.show()

        Connections {
            target: changelogLoader.item

            function onChangelogDismissed() {
                changelogLoader.active = false;
            }
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
