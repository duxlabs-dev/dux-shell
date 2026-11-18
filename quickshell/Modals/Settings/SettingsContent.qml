import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

FocusScope {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string currentPage: ""
    property var parentModal: null
    property Item dialogHost: null
    property real windowButtonsReserve: 0
    property FloatingWindowControls windowDragControls: null

    readonly property bool sessionVisible: parentModal?.shouldBeVisible ?? false
    readonly property list<string> pagePath: (parentModal?.pageHistory ?? []).concat([currentPage])
    readonly property Item currentPageItem: pageStack.currentItem?.item ?? null
    readonly property bool currentPageSettled: pageStack.currentItem?.page === currentPage
    readonly property bool isPluginPage: SettingsTabs.isPluginPage(currentPage)
    readonly property bool isCompactMode: parentModal?.isCompactMode ?? false
    readonly property bool menuHidden: isCompactMode && !(parentModal?.menuVisible ?? true)
    readonly property bool showBack: (parentModal?.canGoBack ?? false) || isPluginPage || menuHidden
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
    // Mouse navigation lands parked; only keyboard navigation highlights a control on the page
    property bool keyboardNavigation: true

    focus: true

    function rememberFocus() {
        const item = Window.activeFocusItem;
        if (pageStack.currentItem && item !== currentPageItem && _contains(currentPageItem, item))
            pageStack.currentItem.rememberedFocus = item;
    }

    function _validRemembered() {
        const remembered = pageStack.currentItem?.rememberedFocus;
        return remembered?.visible && remembered.enabled && _contains(currentPageItem, remembered) ? remembered : null;
    }

    function _focusPage() {
        const revision = parentModal?.modalFocusScope?.focusRevision;
        Qt.callLater(() => {
            if (revision !== parentModal?.modalFocusScope?.focusRevision)
                return;
            if (parentModal?.modalFocusScope?.transientOwnsFocus())
                return;
            if (!sessionVisible || !currentPageItem || pageStack.currentItem.page !== currentPage)
                return;
            if (parentModal?.focusPane === "sidebar")
                return;
            if (!keyboardNavigation) {
                if (!_contains(currentPageItem, Window.activeFocusItem))
                    parkFocus();
                return;
            }
            const remembered = _validRemembered();
            if (remembered) {
                remembered.forceActiveFocus(Qt.TabFocusReason);
                reveal(remembered);
                return;
            }
            let item = currentPageItem;
            do {
                item = item.nextItemInFocusChain(true);
                if (!item || item === currentPageItem || !_contains(currentPageItem, item)) {
                    currentPageItem.forceActiveFocus(Qt.TabFocusReason);
                    return;
                }
            } while (!item.visible || !item.enabled || !_inViewport(item))
            item.forceActiveFocus(Qt.TabFocusReason);
        });
    }

    function goBack(keyboard) {
        if (!showBack)
            return false;
        if (menuHidden && !(parentModal?.canGoBack ?? false)) {
            parentModal.toggleMenu();
            return true;
        }
        parentModal?.goBack(keyboard);
        return true;
    }

    function _contains(ancestor, item) {
        for (let p = item; p; p = p.parent) {
            if (p === ancestor)
                return true;
        }
        return false;
    }

    // Parked focus highlights nothing until a key resumes from rememberedFocus
    function parkFocus() {
        focusAnchor.forceActiveFocus(Qt.MouseFocusReason);
    }

    Item {
        id: focusAnchor
    }

    function _moveFocus(forward) {
        const page = currentPageItem;
        let start = Window.activeFocusItem;
        if (!page || (start !== focusAnchor && !_contains(page, start)))
            return false;
        if (start === focusAnchor) {
            const remembered = _validRemembered();
            if (remembered) {
                remembered.forceActiveFocus(Qt.TabFocusReason);
                reveal(remembered);
                return true;
            }
            start = page;
        }
        let item = start;
        do {
            item = item.nextItemInFocusChain(forward);
            if (!item || item === start || !_contains(page, item))
                return false;
        } while (!item.visible || !item.enabled)
        item.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        reveal(item);
        return true;
    }

    function _inViewport(item) {
        for (let f = item.parent; f; f = f.parent) {
            if (typeof f.flick !== "function")
                continue;
            const y = item.mapToItem(f.contentItem, 0, 0).y;
            const top = Math.max(f.originY, y - Theme.spacingL);
            const bottom = Math.min(f.originY + f.contentHeight, y + item.height + Theme.spacingL);
            if (top < f.contentY || bottom > f.contentY + f.height)
                return false;
        }
        return true;
    }

    function reveal(item) {
        for (let f = item.parent; f; f = f.parent) {
            if (typeof f.flick !== "function" || f.contentHeight <= f.height)
                continue;
            const top = item.mapToItem(f.contentItem, 0, 0).y - Theme.spacingL;
            const bottom = top + item.height + Theme.spacingL * 2;
            if (typeof f.revealRange === "function") {
                f.revealRange(top, bottom);
                return;
            }
            if (top < f.contentY)
                f.contentY = Math.max(f.originY, top);
            else if (bottom > f.contentY + f.height)
                f.contentY = Math.min(f.originY + f.contentHeight - f.height, bottom - f.height);
            return;
        }
    }

    // Keys bubble up from the focused control, so a control that uses an arrow itself (text, lists, open menus) keeps it
    Keys.onPressed: event => {
        const mods = event.modifiers & ~Qt.KeypadModifier;
        const backKey = I18n.isRtl ? Qt.Key_Right : Qt.Key_Left;
        if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && mods === Qt.NoModifier) {
            event.accepted = _moveFocus(event.key === Qt.Key_Down);
            return;
        }
        if ((event.key === backKey && mods === Qt.AltModifier) || (event.key === Qt.Key_Backspace && mods === Qt.NoModifier)) {
            event.accepted = goBack(true);
            return;
        }
        if (event.key !== Qt.Key_Escape || mods !== Qt.NoModifier)
            return;
        const focused = Window.activeFocusItem;
        if (focused && focused !== currentPageItem && focused.cursorPosition !== undefined)
            currentPageItem?.forceActiveFocus();
        else if (!goBack(true))
            parentModal?.focusSidebar();
        event.accepted = true;
    }

    function titleFor(page) {
        const info = SettingsTabs.page(page);
        return (info?.titleFrom ? SettingsUiState[info.titleFrom] : "") || (info?.text ?? "");
    }

    function _fileFor(page) {
        if (pageFiles[page])
            return pageFiles[page];
        if (SettingsTabs.isPluginPage(page))
            return "PluginSettingsPage.qml";
        if (SettingsTabs.page(page)?.kind === "hub")
            return "SettingsHubPage.qml";
        return "";
    }

    function pageSource(page) {
        return Qt.resolvedUrl("../../Modules/Settings/" + _fileFor(page));
    }

    function pageProperties(page) {
        return _propertiesFor(page);
    }

    function _propertiesFor(page) {
        if (SettingsTabs.isPluginPage(page))
            return {
                "parentModal": Qt.binding(() => root.parentModal),
                "pluginId": SettingsTabs.pluginIdOf(page)
            };
        if (!pageFiles[page] && SettingsTabs.page(page)?.kind === "hub")
            return {
                "parentModal": Qt.binding(() => root.parentModal),
                "pageHost": root,
                "hubId": page
            };
        const properties = {};
        if (pagesWithParentModal.includes(page))
            properties.parentModal = Qt.binding(() => root.parentModal);
        if (page === "fcitx5_addon" || page === "fcitx5_addon_sub") {
            const sub = page === "fcitx5_addon_sub";
            properties.parentModal = Qt.binding(() => root.parentModal);
            properties.addon = sub ? SettingsUiState.selectedFcitx5SubAddon : SettingsUiState.selectedFcitx5Addon;
        }
        if (page === "keybinds")
            properties.requestedSearchQuery = Qt.binding(() => root.parentModal?.keybindSearchQuery ?? "");
        return properties;
    }

    property var _cache: ({})
    property var _cacheOrder: []
    property var _doomed: []
    property int _warmUp: 0

    function _cacheable(page) {
        return !SettingsTabs.isPluginPage(page) && !SettingsTabs.page(page)?.titleFrom;
    }

    // Pages are built before their stack operation starts, so the transition never shares frames with a build
    function _takePage(page, index) {
        const cached = _cache[page];
        if (!cached) {
            const host = pageComponent.createObject(pageCache, {
                page,
                pathIndex: index
            });
            host.load();
            return host;
        }
        delete _cache[page];
        _cacheOrder = _cacheOrder.filter(id => id !== page);
        cached.pathIndex = index;
        cached.resetScroll();
        return cached;
    }

    function _release(host) {
        host.parent = pageCache;
        host.fresh = false;
        if (!sessionVisible || !_cacheable(host.page) || _cache[host.page]) {
            _doom(host);
            return;
        }
        _cache[host.page] = host;
        const order = _cacheOrder.concat([host.page]);
        while (order.length > SettingsMetrics.pageCacheLimit) {
            const evicted = order.shift();
            _doom(_cache[evicted]);
            delete _cache[evicted];
        }
        _cacheOrder = order;
    }

    // Tearing a page down takes long enough to cost a frame, so it waits for the transition to end
    function _doom(host) {
        _doomed = _doomed.concat([host]);
        _reap();
    }

    function _reap() {
        if (_doomed.length === 0 || (sessionVisible && (pageStack.busy || slideMotion.running)))
            return;
        const doomed = _doomed;
        _doomed = [];
        for (const host of doomed)
            host.destroy();
    }

    function _dropCache() {
        for (const page of _cacheOrder)
            _doom(_cache[page]);
        _cache = {};
        _cacheOrder = [];
    }

    function _sidebarOrder(page) {
        const top = SettingsTabs.parentOf(page) || page;
        return SettingsTabs.structure.findIndex(entry => entry.id === top);
    }

    // A navigation that lands mid-transition cuts in rather than queueing behind it
    function _operation(transition) {
        const animate = animationsEnabled && pageStack.depth > 0 && !pageStack.busy && (parentModal?.visible ?? false);
        return animate ? transition : StackView.Immediate;
    }

    function _syncPages() {
        if (!sessionVisible) {
            pageStack.clear(StackView.Immediate);
            _dropCache();
            return;
        }
        if (!currentPage)
            return;
        let shared = 0;
        while (shared < Math.min(pageStack.depth, pagePath.length) && pageStack.get(shared).page === pagePath[shared])
            shared++;
        if (shared === pagePath.length) {
            if (shared === pageStack.depth)
                return;
            _warmUp = 0;
            const operation = _operation(StackView.PopTransition);
            _slideIn(operation, -pageStack.pageOffset, 0);
            pageStack.pop(pageStack.get(shared - 1), operation);
            return;
        }
        const pages = [];
        _warmUp = 0;
        for (let index = shared; index < pagePath.length; index++) {
            const page = _takePage(pagePath[index], index);
            // StackView only transitions the top of a multi-item push; pages beneath stay painted until hidden here
            page.visible = index === pagePath.length - 1;
            pages.push(page);
        }
        if (pages[pages.length - 1].fresh)
            _warmUp = SettingsMetrics.pageWarmUpDuration;
        if (shared < pageStack.depth) {
            const operation = _operation(StackView.ReplaceTransition);
            const direction = _sidebarOrder(pagePath[shared]) < _sidebarOrder(pageStack.get(shared).page) ? -1 : 1;
            _slideIn(operation, 0, direction * SettingsMetrics.pageSlideOffset);
            pageStack.replace(pageStack.get(shared), pages, operation);
        } else {
            const operation = _operation(StackView.PushTransition);
            _slideIn(operation, pageStack.pageOffset, 0);
            pageStack.push(pages, operation);
        }
        for (const page of pages)
            page.building = false;
    }

    onPagePathChanged: Qt.callLater(_syncPages)
    onSessionVisibleChanged: Qt.callLater(_syncPages)

    // The leaving page is gone before the next one shows, so two translucent pages never blend
    component PageExit: Transition {
        id: exit

        property int warmUp: 0

        SequentialAnimation {
            PauseAnimation {
                duration: exit.warmUp
            }

            NumberAnimation {
                property: "opacity"
                to: 0
                duration: SettingsMetrics.pageExitDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
            }
        }
    }

    component PageEnter: Transition {
        id: enter

        property int warmUp: 0

        signal revealed

        SequentialAnimation {
            // Qt skips painting at opacity 0, so a new page would lay out and paint for the first time mid-fade
            PropertyAction {
                property: "opacity"
                value: SettingsMetrics.pagePrepaintOpacity
            }

            PauseAnimation {
                duration: enter.warmUp + SettingsMetrics.pageExitDuration
            }

            ScriptAction {
                script: enter.revealed()
            }

            NumberAnimation {
                property: "opacity"
                to: 1
                duration: SettingsMetrics.pageEnterFadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
            }
        }
    }

    readonly property var _slideSpring: Theme.springPreset("defaultSpatial", Theme.expressiveDurations.expressiveFastSpatial)
    property point _slideFrom: Qt.point(0, 0)

    SpringMotion {
        id: slideMotion
        enabled: !Theme.springMotionDisabled
        stiffness: root._slideSpring.stiffness
        damping: root._slideSpring.damping
        onRunningChanged: root._reap()
    }

    function _slideIn(operation, x, y) {
        if (operation === StackView.Immediate) {
            slideMotion.snapTo(1);
            return;
        }
        _slideFrom = Qt.point(x, y);
        slideMotion.snapTo(0);
    }

    function _scrollerOf(item) {
        if (typeof item.flick === "function")
            return item;
        for (const child of item.children) {
            const found = _scrollerOf(child);
            if (found)
                return found;
        }
        return null;
    }

    // A page's Flickable accepts every press inside it before the pane handler sees it, so the scroller carries its own.
    // Handlers die with their parent, so one per page.
    Component {
        id: scrollerTap

        TapHandler {
            onPressedChanged: {
                if (pressed)
                    root.parentModal?.modalFocusScope?.pointerFocus("content");
            }
        }
    }

    Component {
        id: pageComponent

        Item {
            id: host

            required property string page
            property int pathIndex: 0
            readonly property bool pageActive: root.sessionVisible && page === root.currentPage && pageStack.currentItem === host
            // Deferred cards wait for this, so their builds never share frames with the transition
            readonly property bool pageSettled: pageActive && !pageStack.busy && !slideMotion.running
            readonly property alias item: loader.item
            readonly property alias dialogLayer: dialogLayer
            readonly property int status: loader.status

            readonly property string pageTitle: root.titleFor(page)
            readonly property string crumbPage: pathIndex > 0 ? (root.pagePath[pathIndex - 1] ?? "") : (canGoBack ? parentId : "")
            readonly property string crumbTitle: root.titleFor(crumbPage)
            readonly property bool showBack: canGoBack || SettingsTabs.isPluginPage(page) || root.menuHidden
            readonly property string parentId: SettingsTabs.parentOf(page)
            readonly property bool canGoBack: pathIndex > 0 || (parentId !== "" && (SettingsTabs.isPluginPage(page) || SettingsTabs.visibleLeaves(parentId).length > 1 || !!SettingsTabs.page(parentId)?.hubHeader))
            property Item rememberedFocus: null
            property Item scroller: null
            // Controls built disabled animate their colors once enabled, so a page stays enabled while it is built
            property bool building: true
            // Never shown yet, so its first layout and paint are still owed
            property bool fresh: true

            width: pageStack.width
            height: pageStack.height
            enabled: pageActive || building

            StackView.onRemoved: root._release(host)
            // An immediate operation skips the nested enter animation, so the final pose is written here
            StackView.onActivated: opacity = 1

            transform: Translate {
                x: pageStack.currentItem === host ? root._slideFrom.x * (1 - slideMotion.value) : 0
                y: pageStack.currentItem === host ? root._slideFrom.y * (1 - slideMotion.value) : 0
            }

            function load() {
                const file = root._fileFor(page);
                if (file)
                    loader.setSource(Qt.resolvedUrl("../../Modules/Settings/" + file), root._propertiesFor(page));
            }

            function resetScroll() {
                if (scroller)
                    scroller.contentY = scroller.originY;
            }

            MouseArea {
                width: parent.width
                height: pageHeader.height
                enabled: root.windowDragControls !== null
                onPressed: root.windowDragControls.tryStartMove()
                onDoubleClicked: root.windowDragControls.tryToggleMaximize()
            }

            Item {
                id: pageHeader
                width: Math.min(host.item?.contentMaxWidth ?? SettingsMetrics.contentMaxWidth, parent.width - SettingsMetrics.panePadding * 2)
                anchors.horizontalCenter: parent.horizontalCenter
                height: Math.max(SettingsMetrics.pageHeaderHeight, pageHeading.implicitHeight + Theme.spacingS * 2)

                Item {
                    id: backSlot

                    readonly property real glyphInset: (Theme.iconButtonSize - Theme.iconSize) / 2

                    anchors.left: parent.left
                    anchors.leftMargin: host.showBack ? -glyphInset : 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: host.showBack ? Theme.iconButtonSize + Theme.spacingM - glyphInset : 0
                    height: Theme.iconButtonSize

                    DActionButton {
                        buttonSize: Theme.iconButtonSize
                        iconName: I18n.isRtl ? "arrow_forward" : "arrow_back"
                        Accessible.name: I18n.tr("Back")
                        iconSize: Theme.iconSize
                        iconColor: Theme.surfaceText
                        visible: host.showBack
                        onClicked: root.goBack()
                    }
                }

                Flow {
                    id: pageHeading
                    anchors.left: backSlot.right
                    anchors.right: parent.right
                    anchors.rightMargin: Math.max(0, root.windowButtonsReserve - (host.width - pageHeader.width) / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS
                    visible: host.pageTitle !== ""

                    StyledText {
                        width: Math.min(implicitWidth, pageHeading.width)
                        wrapMode: Text.WordWrap
                        text: host.crumbTitle
                        font.pixelSize: Theme.fontSizeXXLarge
                        color: Theme.surfaceVariantText
                        visible: host.crumbTitle !== ""

                        StateLayer {
                            anchors.margins: -Theme.spacingXS
                            cornerRadius: Theme.cornerRadiusS
                            stateColor: Theme.surfaceText
                            onClicked: root.goBack()
                        }
                    }

                    DIcon {
                        height: pageTitleLabel.implicitHeight / Math.max(1, pageTitleLabel.lineCount)
                        name: "chevron_right"
                        size: Theme.iconSize
                        color: Theme.surfaceVariantText
                        rotation: I18n.isRtl ? 180 : 0
                        visible: host.crumbTitle !== ""
                    }

                    StyledText {
                        id: pageTitleLabel
                        width: Math.min(implicitWidth, pageHeading.width)
                        wrapMode: Text.WordWrap
                        text: host.pageTitle
                        font.pixelSize: Theme.fontSizeXXLarge
                        color: Theme.surfaceText
                    }
                }
            }

            Loader {
                id: loader

                anchors.top: pageHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: SettingsMetrics.panePadding
                anchors.rightMargin: SettingsMetrics.panePadding

                onLoaded: {
                    if (item.pageActive !== undefined)
                        item.pageActive = Qt.binding(() => host.pageActive);
                    if (item.pageSettled !== undefined)
                        item.pageSettled = Qt.binding(() => host.pageSettled);
                    const scroller = root._scrollerOf(item);
                    host.scroller = scroller;
                    if (scroller)
                        scrollerTap.createObject(scroller, {
                            "parent": scroller
                        });
                    root._focusPage();
                }
            }

            Item {
                id: dialogLayer

                parent: root.dialogHost ?? host
                anchors.fill: parent
                visible: host.pageActive
            }

            onPageActiveChanged: {
                if (pageActive)
                    root._focusPage();
            }
        }
    }

    readonly property var pageFiles: ({
            "wallpaper_cycling": "WallpaperCyclingTab.qml",
            "wallpaper_folders": "WallpaperFoldersTab.qml",
            "wallpaper_folder": "WallpaperFolderTab.qml",
            "theme_schedule": "ThemeScheduleTab.qml",
            "surface_shadows": "ShadowsTab.qml",
            "time_weather": "TimeWeatherTab.qml",
            "weather": "WeatherSettingsTab.qml",
            "keybinds": "KeybindsTab.qml",
            "dankbar_widgets": "WidgetsTab.qml",
            "window_rules": "WindowRulesTab.qml",
            "dankbar_settings": "DBarTab.qml",
            "dankbar_appearance": "DBarAppearanceTab.qml",
            "dankbar_dot": "DDotTab.qml",
            "bar_widget": "BarWidgetTab.qml",
            "network_connections": "NetworkConnectionsTab.qml",
            "network_connection": "NetworkConnectionTab.qml",
            "network_wifi_connect": "NetworkWifiConnectTab.qml",
            "compositor_layout": "CompositorLayoutTab.qml",
            "compositor_animations": "CompositorAnimationsTab.qml",
            "compositor_includes": "CompositorIncludesTab.qml",
            "dock_general": "DockGeneralTab.qml",
            "dock_widgets": "DockWidgetsTab.qml",
            "dock_appearance": "DockAppearanceTab.qml",
            "dock_advanced": "DockAdvancedTab.qml",
            "display_config": "DisplayConfigTab.qml",
            "display_gamma": "GammaControlTab.qml",
            "display_widgets": "DisplayWidgetsTab.qml",
            "network_status": "NetworkStatusTab.qml",
            "network_ethernet": "NetworkEthernetTab.qml",
            "network_wifi": "NetworkWifiTab.qml",
            "network_hotspot": "NetworkHotspotTab.qml",
            "network_vpn": "NetworkVpnTab.qml",
            "network_tailscale": "NetworkTailscaleTab.qml",
            "network_tailscale_add": "NetworkTailscaleAddTab.qml",
            "network_cellular": "NetworkCellularTab.qml",
            "printers": "PrinterTab.qml",
            "global_shortcuts": "GlobalShortcutsTab.qml",
            "launcher": "LauncherTab.qml",
            "theme": "ThemeColorsTab.qml",
            "theme_apps": "ThemeAppsTab.qml",
            "palette_inject": "PaletteInjectTab.qml",
            "lock_screen": "LockScreenTab.qml",
            "greeter": "GreeterTab.qml",
            "about": "AboutTab.qml",
            "motion": "MotionTab.qml",
            "sounds": "SoundsTab.qml",
            "media_player": "MediaPlayerTab.qml",
            "notification_rules": "NotificationRulesTab.qml",
            "osd": "OSDTab.qml",
            "default_apps": "DefaultAppsTab.qml",
            "running_apps": "RunningAppsTab.qml",
            "updater": "SoftwareUpdatesTab.qml",
            "updater_changelog": "ChangelogTab.qml",
            "power_sleep": "PowerSleepTab.qml",
            "clipboard": "ClipboardTab.qml",
            "screenshot": "ScreenshotTab.qml",
            "desktop_widgets": "DesktopWidgetsTab.qml",
            "desktop_widget": "DesktopWidgetTab.qml",
            "audio": "AudioTab.qml",
            "locale": "LocaleTab.qml",
            "multiplexers": "MuxTab.qml",
            "users": "UsersTab.qml",
            "user_create": "CreateUserTab.qml",
            "greeter_auth": "GreeterAuthTab.qml",
            "autostart": "AutoStartTab.qml",
            "battery": "BatteryTab.qml",
            "dank_dash": "DDashTab.qml",
            "wellbeing": "DigitalWellbeingTab.qml",
            "mouse_touchpad": "MouseTouchpadTab.qml",
            "keyboard": "KeyboardTab.qml",
            "fcitx5": "Fcitx5Tab.qml",
            "fcitx5_addon": "Fcitx5AddonTab.qml",
            "fcitx5_addon_sub": "Fcitx5AddonTab.qml",
            "plugins_manage": "PluginsManageTab.qml",
            "profiles": "ProfilesTab.qml",
            "profile_edit": "ProfileEditTab.qml",
            "profile_inspect": "ProfileInspectTab.qml"
        })

    readonly property var pagesWithParentModal: ["dankbar_widgets", "window_rules", "notification_rules", "display_config", "users", "time_weather", "weather", "lock_screen", "greeter", "dank_dash", "wallpaper_cycling", "wallpaper_folders", "wallpaper_folder", "theme_schedule", "surface_shadows", "keybinds", "dankbar_settings", "dankbar_appearance", "bar_widget", "dock_general", "dock_widgets", "dock_appearance", "dock_advanced", "fcitx5", "global_shortcuts", "launcher", "theme", "theme_apps", "media_player", "desktop_widgets", "desktop_widget", "autostart", "compositor_layout", "compositor_includes", "motion", "updater", "display_gamma", "about", "profiles", "profile_edit", "profile_inspect", "network_connections", "network_connection", "network_ethernet", "network_wifi", "network_hotspot", "network_wifi_connect", "network_vpn", "network_cellular", "network_tailscale", "network_tailscale_add", "screenshot", "osd"]

    // The page scroller stops at the Loader edges; wheel over the header and gutters lands here instead
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        onWheel: event => {
            const scroller = pageStack.currentItem?.scroller;
            if (!scroller?.forwardWheel || !scroller.enabled) {
                event.accepted = false;
                return;
            }
            scroller.forwardWheel(event);
        }

        onActiveChanged: {
            if (active)
                return;
            const scroller = pageStack.currentItem?.scroller;
            if (scroller?.forwardWheelEnd)
                scroller.forwardWheelEnd();
        }
    }

    StackView {
        id: pageStack

        anchors.fill: parent
        clip: true

        readonly property real pageOffset: I18n.isRtl ? -SettingsMetrics.pageSlideOffset : SettingsMetrics.pageSlideOffset

        // The slide starts as the page fades in, so its travel is seen
        pushEnter: PageEnter {
            warmUp: root._warmUp
            onRevealed: slideMotion.retarget(1)
        }
        pushExit: PageExit {
            warmUp: root._warmUp
        }
        popEnter: PageEnter {
            onRevealed: slideMotion.retarget(1)
        }
        popExit: PageExit {}
        replaceEnter: PageEnter {
            warmUp: root._warmUp
            onRevealed: slideMotion.retarget(1)
        }
        replaceExit: PageExit {
            warmUp: root._warmUp
        }

        onBusyChanged: root._reap()
    }

    Item {
        id: pageCache
        visible: false
    }
}
