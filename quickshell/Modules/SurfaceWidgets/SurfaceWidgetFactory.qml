pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.Common
import qs.Services
import qs.Modules.DBar.Widgets
import qs.Modules.DDash
import "../DBar/WidgetModel.js" as WidgetModel

Item {
    id: root
    required property var surfaceContext
    readonly property var barConfig: surfaceContext.config
    readonly property var effectiveBarConfig: barConfig
    readonly property string _barScreenName: surfaceContext.screen?.name ?? ""
    property bool spacingTight: false
    property bool overlapping: false
    function getWidgetSection(item) {
        for (let current = item; current; current = current.parent) {
            if (typeof current.section === "string")
                return current.section;
            if (current.objectName === "leftSection")
                return "left";
            if (current.objectName === "centerSection")
                return "center";
            if (current.objectName === "rightSection")
                return "right";
        }
        return "center";
    }
    function _dashTriggerSource(section, tabId) {
        return surfaceContext.configId + "-" + section + "-" + tabId;
    }
    function getBarPosition() {
        return surfaceContext.axis?.edge === "left" ? 2 : (surfaceContext.axis?.edge === "right" ? 3 : (surfaceContext.axis?.edge === "top" ? 0 : 1));
    }

    function openWidgetPopout(spec) {
        if (!spec)
            return false;
        spec.registration = BarWidgetService.registrationForItem(spec.widgetItem);
        surfaceContext.ensureVisible(spec.widgetItem);
        // A bar widget always opens its own popout where it was clicked; routing is for shortcuts, IPC and the dock.
        if (surfaceContext.kind === "dock" && !surfaceContext.inlineExpansion && spec.islandActivity && PopoutService.routeToIsland(spec.islandActivity, surfaceContext.screen, spec.mode !== "hover", spec.section || ""))
            return true;
        if (!spec.loader)
            return false;
        spec.loader.active = true;

        let popout = _resolvePopoutFromLoader(spec.loader);
        if (!popout) {
            _queuePopoutLoaderOpen(spec);
            return false;
        }
        return _finishWidgetPopoutOpen(spec, popout);
    }

    function _resolvePopoutFromLoader(loader) {
        if (!loader)
            return null;
        if (loader.item)
            return loader.item;

        const pairs = [[PopoutService.appDrawerLoader, PopoutService.appDrawerPopout], [PopoutService.batteryPopoutLoader, PopoutService.batteryPopout], [PopoutService.clipboardHistoryPopoutLoader, PopoutService.clipboardHistoryPopout], [PopoutService.controlCenterLoader, PopoutService.controlCenterPopout], [PopoutService.dankDashPopoutLoader, PopoutService.dankDashPopout], [PopoutService.layoutPopoutLoader, PopoutService.layoutPopout], [PopoutService.notificationCenterLoader, PopoutService.notificationCenterPopout], [PopoutService.processListPopoutLoader, PopoutService.processListPopout], [PopoutService.systemUpdateLoader, PopoutService.systemUpdatePopout], [PopoutService.vpnPopoutLoader, PopoutService.vpnPopout], [PopoutService.colorPickerPopoutLoader, PopoutService.colorPickerPopout], [PopoutService.durationPopoutLoader, PopoutService.durationPopout], [PopoutService.powerMenuPopoutLoader, PopoutService.powerMenuPopout]];
        for (let i = 0; i < pairs.length; i++) {
            if (loader === pairs[i][0] && pairs[i][1])
                return pairs[i][1];
        }
        return null;
    }

    property var pendingOpen: null
    function _queuePopoutLoaderOpen(spec) {
        pendingOpen = spec;
    }
    Connections {
        target: root.pendingOpen?.loader ?? null
        function onLoaded() {
            const request = root.pendingOpen;
            root.pendingOpen = null;
            if (!request?.loader?.item)
                return;
            root._finishWidgetPopoutOpen(request, request.loader.item);
        }
    }

    function _finishWidgetPopoutOpen(spec, popout) {
        if (spec.registration && !BarWidgetService.registrationActive(spec.registration, true))
            return false;
        const effectiveBarConfig = barConfig;
        const barPosition = getBarPosition();
        const widgetSection = spec.section || "right";
        const mode = spec.mode || "click";

        if (popout.setBarContext)
            popout.setBarContext(barPosition, effectiveBarConfig?.bottomGap ?? 0);

        if (spec.setTriggerScreen)
            popout.triggerScreen = surfaceContext.screen;

        if (spec.widgetItem) {
            // A section the island sits in is not an anchor: the popout would open under the island.
            const centred = spec.useCenterSection && widgetSection === "center" && !(surfaceContext.host?.hostsIsland && SettingsData.islandWidgetSection(surfaceContext.config) === "center");
            const visual = centred ? surfaceContext.centerSection : spec.visualItem;
            const context = spec.registration?.context?.surface ?? surfaceContext;
            context.positionPopout(popout, spec.widgetItem, widgetSection, visual, spec.triggerWidth, mode !== "hover");
        }

        if (typeof popout.prepareForTrigger === "function")
            popout.prepareForTrigger(spec.triggerSource, mode);

        if (spec.prepare)
            spec.prepare(popout);

        const request = mode === "hover" ? PopoutManager.requestHoverPopout : PopoutManager.requestPopout;
        request(popout, spec.tabIndex, spec.triggerSource);
        return true;
    }

    readonly property var widgetVisibility: ({
            "cpuUsage": DgopService.dgopAvailable,
            "memUsage": DgopService.dgopAvailable,
            "cpuTemp": DgopService.dgopAvailable,
            "gpuTemp": DgopService.dgopAvailable,
            "network_speed_monitor": DgopService.dgopAvailable
        })

    function getWidgetVisible(widgetId) {
        return widgetVisibility[widgetId] ?? true;
    }

    readonly property var componentMap: {
        const baseMap = WidgetModel.builtinComponents({
            launcherButtonComponent,
            workspaceSwitcherComponent,
            focusedWindowComponent,
            runningAppsComponent,
            appsDockComponent,
            clockComponent,
            mediaComponent,
            mediaActivityComponent,
            weatherComponent,
            systemTrayComponent,
            privacyIndicatorComponent,
            clipboardComponent,
            cpuUsageComponent,
            memUsageComponent,
            diskUsageComponent,
            cpuTempComponent,
            gpuTempComponent,
            notificationButtonComponent,
            batteryComponent,
            layoutComponent,
            controlCenterButtonComponent,
            capsLockIndicatorComponent,
            idleInhibitorComponent,
            spacerComponent,
            separatorComponent,
            networkComponent,
            keyboardLayoutNameComponent,
            vpnComponent,
            notepadButtonComponent,
            colorPickerComponent,
            systemUpdateComponent,
            powerMenuButtonComponent,
            islandComponent
        });

        let pluginMap = PluginService.getWidgetComponents();
        return Object.assign(baseMap, pluginMap);
    }

    function getWidgetComponent(widgetId) {
        return componentMap[widgetId] || componentMap[widgetId.split(":")[0]] || null;
    }

    Component {
        id: clipboardComponent

        ClipboardButton {
            id: clipboardWidget
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent)
            parentScreen: surfaceContext.screen
            popoutTarget: PopoutService.clipboardHistoryPopoutLoader?.item ?? null

            function openClipboardPopout(initialTab, mode) {
                openWidgetPopout({
                    loader: PopoutService.clipboardHistoryPopoutLoader,
                    widgetItem: clipboardWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "clipboard",
                    islandActivity: "clipboard",
                    mode: mode || "click",
                    prepare: popout => {
                        if (initialTab)
                            popout.activeTab = initialTab;
                    }
                });
            }

            onClipboardClicked: openClipboardPopout("recents")

            onShowSavedItemsRequested: openClipboardPopout("saved")

            onClearAllRequested: {
                const loader = PopoutService.clipboardHistoryPopoutLoader;
                if (!loader)
                    return;
                loader.active = true;
                const popout = loader.item;
                if (!popout?.confirmDialog) {
                    return;
                }
                const hasPinned = popout.pinnedCount > 0;
                const message = hasPinned ? I18n.tr("This will delete all unpinned entries. %1 pinned entries will be kept.").arg(popout.pinnedCount) : I18n.tr("This will permanently delete all clipboard history.");
                popout.confirmDialog.show(I18n.tr("Clear History?"), message, function () {
                    if (popout && typeof popout.clearAll === "function") {
                        popout.clearAll();
                    }
                }, function () {});
            }
        }
    }

    Component {
        id: powerMenuButtonComponent

        PowerMenuButton {
            id: powerMenuWidget
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent)
            parentScreen: surfaceContext.screen
            isActive: PopoutService.powerMenuPopoutLoader?.item ? PopoutService.powerMenuPopoutLoader?.item.shouldBeVisible : false
            onClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.powerMenuPopoutLoader,
                    widgetItem: powerMenuWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "powerMenu",
                    islandActivity: "powermenu",
                    mode: "click"
                });
            }
        }
    }

    Component {
        id: launcherButtonComponent

        LauncherButton {
            id: launcherButton
            isActive: false
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            section: root.getWidgetSection(parent)
            popoutTarget: PopoutService.appDrawerLoader?.item
            parentScreen: surfaceContext.screen
            hyprlandOverviewLoader: surfaceContext.hyprlandOverviewLoader

            function _preparePopout() {
                const loader = PopoutService.appDrawerLoader;
                if (!loader)
                    return false;
                loader.active = true;
                if (!loader.item)
                    return false;
                surfaceContext.ensureVisible(launcherButton);
                return surfaceContext.positionPopout(loader.item, launcherButton, launcherButton.section);
            }

            function openWithMode(mode) {
                if (!_preparePopout())
                    return;
                PopoutService.appDrawerLoader.item.openWithMode(mode);
            }

            function toggleWithMode(mode) {
                if (!_preparePopout())
                    return;
                PopoutService.appDrawerLoader.item.toggleWithMode(mode);
            }

            function openWithQuery(query) {
                if (!_preparePopout())
                    return;
                PopoutService.appDrawerLoader.item.openWithQuery(query);
            }

            function toggleWithQuery(query) {
                if (!_preparePopout())
                    return;
                PopoutService.appDrawerLoader.item.toggleWithQuery(query);
            }

            onClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.appDrawerLoader,
                    widgetItem: launcherButton,
                    section: launcherButton.section,
                    triggerSource: "appDrawer",
                    islandActivity: "launcher",
                    mode: "click",
                    visualItem: launcherButton
                });
            }
        }
    }

    Component {
        id: workspaceSwitcherComponent

        WorkspaceSwitcher {
            axis: root.surfaceContext.axis
            screenName: _barScreenName
            widgetThickness: root.surfaceContext.widgetThickness
            barThickness: root.surfaceContext.thickness
            parentScreen: root.surfaceContext.screen
            hyprlandOverviewLoader: root.surfaceContext.hyprlandOverviewLoader
        }
    }

    Component {
        id: focusedWindowComponent

        FocusedApp {
            id: focusedWindowWidget
            axis: surfaceContext.axis
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            barSpacing: barConfig?.spacing ?? 4
            barConfig: root.surfaceContext.config
            isAutoHideBar: root.surfaceContext.config?.autoHide ?? false
            parentScreen: surfaceContext.screen
        }
    }

    Component {
        id: runningAppsComponent

        RunningApps {
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            barSpacing: barConfig?.spacing ?? 4
            section: root.getWidgetSection(parent)
            parentScreen: surfaceContext.screen
            topBar: root
            barConfig: root.surfaceContext.config
            isAutoHideBar: root.surfaceContext.config?.autoHide ?? false
        }
    }

    Component {
        id: appsDockComponent

        AppsDock {
            surfaceContext: root.surfaceContext
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            barSpacing: barConfig?.spacing ?? 4
            section: root.getWidgetSection(parent)
            parentScreen: surfaceContext.screen
            topBar: root
            barConfig: root.surfaceContext.config
            isAutoHideBar: root.surfaceContext.config?.autoHide ?? false
        }
    }

    Component {
        id: clockComponent

        Clock {
            id: clockWidget
            axis: root.surfaceContext.axis
            compactMode: root.overlapping
            barThickness: root.surfaceContext.thickness
            widgetThickness: root.surfaceContext.widgetThickness
            section: root.getWidgetSection(parent) || "center"
            parentScreen: root.surfaceContext.screen

            Component.onCompleted: {
                if (root.surfaceContext?.host && "clockButtonRef" in root.surfaceContext.host)
                    root.surfaceContext.host.clockButtonRef = this;
            }

            Component.onDestruction: {
                if (root.surfaceContext?.host && "clockButtonRef" in root.surfaceContext.host && root.surfaceContext.host.clockButtonRef === this) {
                    root.surfaceContext.host.clockButtonRef = null;
                }
            }

            onClockClicked: {
                const action = SettingsData.widgetOption("clock", clockWidget.widgetData, "clockClickAction");
                if (action === "none")
                    return;
                if (action === "settings") {
                    PopoutService.focusOrToggleSettingsWithTab("time_weather");
                    return;
                }
                if (action === "command") {
                    const command = SettingsData.widgetOption("clock", clockWidget.widgetData, "clockClickCommand");
                    if (command)
                        Quickshell.execDetached(["sh", "-c", command]);
                    return;
                }
                // A disabled Overview opens as a tabless detail page, so it only wins when no tab is enabled.
                const tabId = DashRegistry.isSelectable(DashRegistry.overviewId) ? DashRegistry.overviewId : DashRegistry.defaultTabId || DashRegistry.overviewId;
                const section = root.getWidgetSection(parent) || "center";
                root.openWidgetPopout({
                    loader: PopoutService.dankDashPopoutLoader,
                    widgetItem: clockWidget,
                    section,
                    useCenterSection: true,
                    triggerSource: root._dashTriggerSource(section, tabId),
                    islandActivity: "home",
                    prepare: popout => popout.requestTab(tabId),
                    mode: "click",
                    setTriggerScreen: true
                });
            }
        }
    }

    Component {
        id: mediaActivityComponent
        MediaActivity {
            id: activityWidget
            onClicked: {
                const section = root.getWidgetSection(parent);
                root.openWidgetPopout({
                    loader: PopoutService.dankDashPopoutLoader,
                    widgetItem: activityWidget,
                    section,
                    useCenterSection: true,
                    triggerSource: root._dashTriggerSource(section, "media"),
                    islandActivity: "media",
                    prepare: popout => popout.requestTab("media"),
                    mode: "click",
                    setTriggerScreen: true
                });
            }
        }
    }

    Component {
        id: mediaComponent

        Media {
            id: mediaWidget
            axis: root.surfaceContext.axis
            compactMode: root.spacingTight || root.overlapping
            barThickness: root.surfaceContext.thickness
            widgetThickness: root.surfaceContext.widgetThickness
            section: root.getWidgetSection(parent) || "center"
            parentScreen: root.surfaceContext.screen
            onClicked: {
                const section = root.getWidgetSection(parent) || "center";
                root.openWidgetPopout({
                    loader: PopoutService.dankDashPopoutLoader,
                    widgetItem: mediaWidget,
                    section,
                    useCenterSection: true,
                    triggerSource: root._dashTriggerSource(section, "media"),
                    islandActivity: "media",
                    prepare: popout => popout.requestTab("media"),
                    mode: "click",
                    setTriggerScreen: true
                });
            }
        }
    }

    Component {
        id: weatherComponent

        Weather {
            id: weatherWidget
            axis: surfaceContext.axis
            barThickness: surfaceContext.thickness
            widgetThickness: surfaceContext.widgetThickness
            section: root.getWidgetSection(parent) || "center"
            parentScreen: surfaceContext.screen
            onClicked: {
                const section = root.getWidgetSection(parent) || "center";
                root.openWidgetPopout({
                    loader: PopoutService.dankDashPopoutLoader,
                    widgetItem: weatherWidget,
                    section,
                    useCenterSection: true,
                    triggerSource: root._dashTriggerSource(section, "weather"),
                    islandActivity: "weather",
                    prepare: popout => popout.requestTab("weather"),
                    mode: "click",
                    setTriggerScreen: true
                });
            }
        }
    }

    Component {
        id: systemTrayComponent

        SystemTrayBar {
            parentWindow: surfaceContext.host
            parentScreen: surfaceContext.screen
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            barSpacing: barConfig?.spacing ?? 4
            barConfig: root.surfaceContext.config
            widgetData: parent.widgetData
            isAutoHideBar: root.surfaceContext.config?.autoHide ?? false
            isAtBottom: surfaceContext.axis?.edge === "bottom"
            visible: SettingsData.getFilteredScreens("systemTray").includes(surfaceContext.screen) && SystemTray.items.values.length > 0
        }
    }

    Component {
        id: privacyIndicatorComponent

        PrivacyIndicator {
            widgetThickness: surfaceContext.widgetThickness
            section: root.getWidgetSection(parent) || "right"
            parentScreen: surfaceContext.screen
        }
    }

    Component {
        id: cpuUsageComponent

        CpuMonitor {
            id: cpuWidget
            barThickness: surfaceContext.thickness
            widgetThickness: surfaceContext.widgetThickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            popoutTarget: PopoutService.processListPopoutLoader?.item ?? null
            parentScreen: surfaceContext.screen
            widgetData: parent.widgetData
            onCpuClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.processListPopoutLoader,
                    widgetItem: cpuWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "cpu",
                    mode: "click"
                });
            }
        }
    }

    Component {
        id: memUsageComponent

        RamMonitor {
            id: ramWidget
            barThickness: surfaceContext.thickness
            widgetThickness: surfaceContext.widgetThickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            popoutTarget: PopoutService.processListPopoutLoader?.item ?? null
            parentScreen: surfaceContext.screen
            widgetData: parent.widgetData
            onRamClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.processListPopoutLoader,
                    widgetItem: ramWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "memory",
                    mode: "click"
                });
            }
        }
    }

    Component {
        id: diskUsageComponent

        DiskUsage {
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            widgetData: parent.widgetData
            parentScreen: surfaceContext.screen
            barConfig: root.surfaceContext.config
            isAutoHideBar: root.surfaceContext.config?.autoHide ?? false
        }
    }

    Component {
        id: cpuTempComponent

        CpuTemperature {
            id: cpuTempWidget
            barThickness: surfaceContext.thickness
            widgetThickness: surfaceContext.widgetThickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            popoutTarget: PopoutService.processListPopoutLoader?.item ?? null
            parentScreen: surfaceContext.screen
            widgetData: parent.widgetData
            onCpuTempClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.processListPopoutLoader,
                    widgetItem: cpuTempWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "cpu_temp",
                    mode: "click"
                });
            }
        }
    }

    Component {
        id: gpuTempComponent

        GpuTemperature {
            id: gpuTempWidget
            barThickness: surfaceContext.thickness
            widgetThickness: surfaceContext.widgetThickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            popoutTarget: PopoutService.processListPopoutLoader?.item ?? null
            parentScreen: surfaceContext.screen
            widgetData: parent.widgetData
            onGpuTempClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.processListPopoutLoader,
                    widgetItem: gpuTempWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "gpu_temp",
                    mode: "click"
                });
            }
        }
    }

    Component {
        id: networkComponent

        NetworkMonitor {}
    }

    Component {
        id: notificationButtonComponent

        NotificationCenterButton {
            id: notificationButton
            hasUnread: surfaceContext.notificationCount > 0
            isActive: PopoutService.notificationCenterLoader?.item ? PopoutService.notificationCenterLoader?.item.shouldBeVisible : false
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            popoutTarget: PopoutService.notificationCenterLoader?.item ?? null
            parentScreen: surfaceContext.screen
            onClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.notificationCenterLoader,
                    widgetItem: notificationButton,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "notifications",
                    islandActivity: "notificationcenter",
                    mode: "click",
                    setTriggerScreen: true
                });
            }
            onRightClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.durationPopoutLoader,
                    widgetItem: notificationButton,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "dndDuration",
                    mode: "click",
                    setTriggerScreen: true
                });
            }
        }
    }

    Component {
        id: batteryComponent

        Battery {
            id: batteryWidget
            batteryPopupVisible: PopoutService.batteryPopoutLoader?.item ? PopoutService.batteryPopoutLoader?.item.shouldBeVisible : false
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            barSpacing: barConfig?.spacing ?? 4
            barConfig: root.surfaceContext.config
            popoutTarget: PopoutService.batteryPopoutLoader?.item ?? null
            parentScreen: surfaceContext.screen
            onToggleBatteryPopup: {
                root.openWidgetPopout({
                    loader: PopoutService.batteryPopoutLoader,
                    widgetItem: batteryWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "battery",
                    mode: "click"
                });
            }
        }
    }

    Component {
        id: layoutComponent

        DWLLayout {
            id: layoutWidget
            layoutPopupVisible: PopoutService.layoutPopoutLoader?.item ? PopoutService.layoutPopoutLoader?.item.shouldBeVisible : false
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "center"
            popoutTarget: PopoutService.layoutPopoutLoader?.item ?? null
            parentScreen: surfaceContext.screen
            onToggleLayoutPopup: {
                root.openWidgetPopout({
                    loader: PopoutService.layoutPopoutLoader,
                    widgetItem: layoutWidget,
                    section: root.getWidgetSection(parent) || "center",
                    triggerSource: "layout",
                    mode: "click"
                });
            }
        }
    }

    Component {
        id: vpnComponent

        Vpn {
            id: vpnWidget
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            barSpacing: barConfig?.spacing ?? 4
            barConfig: root.surfaceContext.config
            isAutoHideBar: root.surfaceContext.config?.autoHide ?? false
            popoutTarget: PopoutService.vpnPopoutLoader?.item ?? null
            parentScreen: surfaceContext.screen
            onToggleVpnPopup: {
                root.openWidgetPopout({
                    loader: PopoutService.vpnPopoutLoader,
                    widgetItem: vpnWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "vpn",
                    mode: "click"
                });
            }
        }
    }

    Component {
        id: controlCenterButtonComponent

        ControlCenterButton {
            id: controlCenterButton
            isActive: PopoutService.controlCenterLoader?.item ? PopoutService.controlCenterLoader?.item.shouldBeVisible : false
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            popoutTarget: PopoutService.controlCenterLoader?.item ?? null
            parentScreen: surfaceContext.screen
            screenName: surfaceContext.screen?.name || ""
            screenModel: surfaceContext.screen?.model || ""
            widgetData: parent.widgetData

            Component.onCompleted: {
                if (surfaceContext.host && "controlCenterButtonRef" in surfaceContext.host)
                    surfaceContext.host.controlCenterButtonRef = this;
            }

            Component.onDestruction: {
                if (surfaceContext.host && "controlCenterButtonRef" in surfaceContext.host && surfaceContext.host.controlCenterButtonRef === this) {
                    surfaceContext.host.controlCenterButtonRef = null;
                }
            }

            onClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.controlCenterLoader,
                    widgetItem: controlCenterButton,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "controlCenter",
                    islandActivity: "controlcenter",
                    mode: "click",
                    setTriggerScreen: true
                });
                if (PopoutService.controlCenterLoader?.item?.shouldBeVisible && NetworkService.wifiEnabled)
                    NetworkService.scanWifi();
            }
        }
    }

    Component {
        id: capsLockIndicatorComponent

        CapsLockIndicator {
            widgetThickness: surfaceContext.widgetThickness
            section: root.getWidgetSection(parent) || "right"
            parentScreen: surfaceContext.screen
        }
    }

    Component {
        id: idleInhibitorComponent

        IdleInhibitor {
            id: idleInhibitorWidget
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            parentScreen: surfaceContext.screen
            onRightClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.durationPopoutLoader,
                    widgetItem: idleInhibitorWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "idleInhibit",
                    mode: "click",
                    setTriggerScreen: true
                });
            }
        }
    }

    // Reserves the compact face's along-axis room; the morph surface is the bar's island overlay, anchored to this slot.
    Component {
        id: islandComponent

        Item {
            id: islandSlot

            readonly property Item body: surfaceContext.kind === "bar" ? surfaceContext.host : null
            readonly property real alongSize: body?.islandHost?.compactTargetSize ?? 0

            width: surfaceContext.isVertical ? surfaceContext.widgetThickness : alongSize
            height: surfaceContext.isVertical ? alongSize : surfaceContext.widgetThickness
            implicitWidth: width
            implicitHeight: height

            Component.onCompleted: {
                if (body)
                    body.islandSlot = islandSlot;
            }
            Component.onDestruction: {
                if (body && body.islandSlot === islandSlot)
                    body.islandSlot = null;
            }
        }
    }

    Component {
        id: spacerComponent

        Item {
            width: surfaceContext.isVertical ? surfaceContext.widgetThickness : (parent.spacerSize || 20)
            height: surfaceContext.isVertical ? (parent.spacerSize || 20) : surfaceContext.widgetThickness
            implicitWidth: width
            implicitHeight: height

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Theme.outlineStrong
                border.width: 1
                radius: 2
                visible: false

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    propagateComposedEvents: true
                    cursorShape: Qt.ArrowCursor
                    onEntered: parent.visible = true
                    onExited: parent.visible = false
                }
            }
        }
    }

    Component {
        id: separatorComponent

        Item {
            width: surfaceContext.isVertical ? parent.barThickness : 1
            height: surfaceContext.isVertical ? 1 : parent.barThickness
            implicitWidth: width
            implicitHeight: height

            Rectangle {
                width: surfaceContext.isVertical ? parent.width * 0.6 : 1
                height: surfaceContext.isVertical ? 1 : parent.height * 0.6
                anchors.centerIn: parent
                color: Theme.outline
                opacity: 0.3
            }
        }
    }

    Component {
        id: keyboardLayoutNameComponent

        KeyboardLayoutName {}
    }

    Component {
        id: notepadButtonComponent

        NotepadButton {
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            parentScreen: surfaceContext.screen
        }
    }

    Component {
        id: colorPickerComponent

        ColorPicker {
            id: colorPickerWidget
            isActive: PopoutService.colorPickerPopoutLoader?.item ? PopoutService.colorPickerPopoutLoader?.item.shouldBeVisible : false
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            section: root.getWidgetSection(parent) || "right"
            parentScreen: surfaceContext.screen
            onColorPickerRequested: {
                root.openWidgetPopout({
                    loader: PopoutService.colorPickerPopoutLoader,
                    widgetItem: colorPickerWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "colorPicker",
                    mode: "click"
                });
            }
        }
    }

    Component {
        id: systemUpdateComponent

        SystemUpdate {
            id: systemUpdateWidget
            isActive: PopoutService.systemUpdateLoader?.item ? PopoutService.systemUpdateLoader?.item.shouldBeVisible : false
            widgetThickness: surfaceContext.widgetThickness
            barThickness: surfaceContext.thickness
            axis: surfaceContext.axis
            section: root.getWidgetSection(parent) || "right"
            popoutTarget: PopoutService.systemUpdateLoader?.item ?? null
            parentScreen: surfaceContext.screen

            Component.onCompleted: {
                if (surfaceContext.host && "systemUpdateButtonRef" in surfaceContext.host)
                    surfaceContext.host.systemUpdateButtonRef = this;
            }

            Component.onDestruction: {
                if (surfaceContext.host && "systemUpdateButtonRef" in surfaceContext.host && surfaceContext.host.systemUpdateButtonRef === this)
                    surfaceContext.host.systemUpdateButtonRef = null;
            }

            onClicked: {
                root.openWidgetPopout({
                    loader: PopoutService.systemUpdateLoader,
                    widgetItem: systemUpdateWidget,
                    section: root.getWidgetSection(parent) || "right",
                    triggerSource: "systemUpdate",
                    mode: "click",
                    visualItem: systemUpdateWidget
                });
            }
        }
    }
}
