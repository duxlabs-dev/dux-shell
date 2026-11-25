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
    readonly property bool animationsEnabled: !Theme.reduceMotion
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

    function _cacheable(page) {
        return !SettingsTabs.isPluginPage(page) && !SettingsTabs.page(page)?.titleFrom;
    }

    // Pages are children of the stack view from the start, parked past its clip while they are prepared: there
    // they are laid out and drawn once out of sight, and reparenting one later would walk its whole tree
    function _takePage(page, index) {
        if (_ahead?.page === page) {
            const host = _ahead;
            _ahead = null;
            host.pathIndex = index;
            return host;
        }
        const cached = _cache[page];
        if (!cached) {
            const host = pageComponent.createObject(pageStack, {
                x: pageStack.width,
                page,
                pathIndex: index,
                width: pageStack.width,
                height: pageStack.height
            });
            host.load();
            return host;
        }
        delete _cache[page];
        _cacheOrder = _cacheOrder.filter(id => id !== page);
        cached.pathIndex = index;
        cached.x = pageStack.width;
        cached.visible = true;
        cached.width = pageStack.width;
        cached.height = pageStack.height;
        cached.resetScroll();
        return cached;
    }

    function _release(host) {
        host.visible = false;
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

    // Tearing a page down costs frames, so it happens a card at a time while nothing else is going on
    function _doom(host) {
        _doomed = _doomed.concat([host]);
        if (!sessionVisible)
            _reap();
    }

    Timer {
        interval: SettingsMetrics.pageTeardownInterval
        repeat: true
        running: root.sessionVisible && root._doomed.length > 0 && !pageStack.busy && root._staged === null && !root._syncRequested
        onTriggered: root._reap()
    }

    function _reap() {
        if (_doomed.length === 0)
            return;
        if (!sessionVisible) {
            const doomed = _doomed;
            _doomed = [];
            for (const host of doomed)
                host.destroy();
            return;
        }
        const doomed = _doomed.slice();
        if (!doomed[0].scroller?.unbuildCard?.())
            doomed.shift().destroy();
        _doomed = doomed;
    }

    // StackView leaves an item with an explicit size alone
    function _fitPages() {
        for (let i = 0; i < pageStack.depth; i++) {
            const host = pageStack.get(i, StackView.DontLoad);
            host.width = pageStack.width;
            host.height = pageStack.height;
        }
    }

    function _dropCache() {
        for (const page of _cacheOrder)
            _doom(_cache[page]);
        _cache = {};
        _cacheOrder = [];
    }

    function _operation(transition) {
        const animate = animationsEnabled && pageStack.depth > 0 && (parentModal?.visible ?? false);
        return animate ? transition : StackView.Immediate;
    }

    function _syncPages() {
        _discardStaged();
        if (!sessionVisible) {
            _shelve();
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
            pageStack.currentItem.holdPose();
            _slideFrom = -pageStack.slideDistance;
            pageStack.pop(pageStack.get(shared - 1), _operation(StackView.PopTransition));
            return;
        }
        if (_ahead && !pagePath.includes(_ahead.page))
            _shelve();
        const pages = [];
        for (let index = shared; index < pagePath.length; index++) {
            const page = _takePage(pagePath[index], index);
            // StackView only transitions the top of a multi-item push; pages beneath stay painted until hidden here
            page.visible = index === pagePath.length - 1;
            pages.push(page);
        }
        _staged = {
            "pages": pages,
            "shared": shared
        };
    }

    // A transition started in the turn that prepared its page is charged that work on its first tick and skips ahead
    property var _staged: null

    // A page the pointer rests on is built ahead into the cache, so the click that follows finds it ready
    property string _anticipated: ""
    property var _ahead: null

    function anticipate(pageId) {
        _anticipated = SettingsTabs.resolvePage(pageId);
        anticipation.restart();
    }

    function _aheadable(page) {
        return page && page !== currentPage && !_cache[page] && _cacheable(page);
    }

    // The page under the pointer first, then, while the cache has room, the sidebar neighbours of the current one
    function _nextAhead() {
        if (_aheadable(_anticipated))
            return _anticipated;
        if (_cacheOrder.length >= SettingsMetrics.pageCacheLimit)
            return "";
        const ids = SettingsTabs.structure.filter(entry => !entry.separator && SettingsTabs.isVisible(entry)).map(entry => SettingsTabs.resolvePage(entry.id));
        const at = ids.indexOf(pagePath[0]);
        for (let distance = 1; distance < ids.length; distance++) {
            if (_aheadable(ids[at + distance]))
                return ids[at + distance];
            if (_aheadable(ids[at - distance]))
                return ids[at - distance];
        }
        return "";
    }

    function _buildAhead() {
        if (!sessionVisible)
            return;
        if (_ahead || _staged || _syncRequested || pageStack.busy) {
            anticipation.restart();
            return;
        }
        const page = _nextAhead();
        if (!page)
            return;
        _ahead = _takePage(page, 0);
        if (_ahead.firstScreenReady)
            _shelve();
    }

    function _shelve() {
        if (!_ahead)
            return;
        const host = _ahead;
        _ahead = null;
        _release(host);
        anticipation.restart();
    }

    Timer {
        id: anticipation
        interval: SettingsMetrics.pageAnticipationDelay
        onTriggered: root._buildAhead()
    }

    function _discardStaged() {
        if (!_staged)
            return;
        const pages = _staged.pages;
        _staged = null;
        for (const page of pages)
            _release(page);
    }

    function _commitStaged() {
        if (!_staged)
            return;
        const pages = _staged.pages;
        const shared = _staged.shared;
        _staged = null;
        pageStack.currentItem?.holdPose();
        for (const page of pages)
            page.x = 0;
        if (shared < pageStack.depth) {
            _slideFrom = 0;
            pageStack.replace(pageStack.get(shared), pages, _operation(StackView.ReplaceTransition));
        } else {
            _slideFrom = pageStack.slideDistance;
            pageStack.push(pages, _operation(StackView.PushTransition));
        }
    }

    // Each step waits for a frame: the click is answered before the page is prepared, and the prepared page
    // has been drawn once, out of sight, before its transition starts
    property bool _syncRequested: false
    property int _framesWaited: 0

    function _requestSync() {
        if (!sessionVisible) {
            Qt.callLater(_syncPages);
            return;
        }
        _syncRequested = true;
        _framesWaited = 0;
    }

    FrameAnimation {
        running: root._syncRequested || root._staged !== null
        onTriggered: {
            if (root._syncRequested) {
                if (root._framesWaited++ < 1)
                    return;
                root._syncRequested = false;
                root._framesWaited = 0;
                Qt.callLater(root._syncPages);
                return;
            }
            if (!root._staged)
                return;
            const pages = root._staged.pages;
            if (!pages[pages.length - 1].firstScreenReady) {
                root._framesWaited = 0;
                return;
            }
            if (root._framesWaited++ < 1)
                return;
            root._commitStaged();
        }
    }

    onPagePathChanged: _requestSync()
    onSessionVisibleChanged: _requestSync()

    // One eased progress drives both pages: the leaving one is gone before the arriving one shows
    component PageMotion: Transition {
        id: motion

        SequentialAnimation {
            PropertyAction {
                property: "opacity"
                value: 1
            }

            PropertyAction {
                property: "transitionProgress"
                value: 0
            }

            NumberAnimation {
                property: "transitionProgress"
                to: 1
                duration: SettingsMetrics.pageTransitionDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: SettingsMetrics.pageTransitionCurve
            }
        }
    }

    property real _slideFrom: 0
    readonly property bool _fadeThrough: _slideFrom === 0
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
            readonly property bool pageSettled: pageActive && !pageStack.busy && root._staged === null
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
            // A page is built while parked off screen, where an edge fade cannot find the pane painted behind it
            readonly property color surfaceColor: SettingsMetrics.paneColor
            readonly property bool firstScreenReady: scroller?.firstScreenBuilt ?? true
            onFirstScreenReadyChanged: {
                if (firstScreenReady && root._ahead === host)
                    root._shelve();
            }

            width: pageStack.width
            height: pageStack.height

            // StackView writes opacity on the pages it manages, so the transition animates this and the stage reads it
            property real transitionProgress: 1
            readonly property bool entering: pageStack.currentItem === host
            // A navigation can land while this page is still arriving; it then leaves from where it had got to
            property real heldOpacity: 1
            property real heldX: 0
            property real heldScale: 1

            function holdPose() {
                heldOpacity = stage.opacity;
                heldX = stage.slideX;
                heldScale = stage.scale;
            }

            StackView.onRemoved: root._release(host)
            // An immediate operation skips the transition, so the final pose is written here
            StackView.onActivated: {
                opacity = 1;
                transitionProgress = 1;
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

            Item {
                id: stage

                // A curve that overshoots must not carry the page past its resting pose
                readonly property real progress: Math.max(0, Math.min(1, host.transitionProgress))
                readonly property real fadeIn: Math.max(0, (progress - SettingsMetrics.pageFadeThreshold) / (1 - SettingsMetrics.pageFadeThreshold))
                readonly property real fadeOut: Math.max(0, 1 - progress / SettingsMetrics.pageFadeThreshold)

                readonly property real pixelRatio: Window.window?.devicePixelRatio ?? Screen.devicePixelRatio
                readonly property real slideX: host.entering ? root._slideFrom * (1 - progress) : host.heldX - root._slideFrom * progress
                readonly property real enterScale: root._fadeThrough ? SettingsMetrics.pageEnterScale + (1 - SettingsMetrics.pageEnterScale) * progress : 1

                anchors.fill: parent
                opacity: host.entering ? fadeIn : host.heldOpacity * fadeOut
                scale: host.entering ? enterScale : host.heldScale
                // Glyphs sit on whole pixels: scaled live they shake in their rows, so a scaled page is drawn as one image
                layer.enabled: progress < 1 && scale !== 1
                layer.smooth: true
                // Same reason, the slide moves by whole pixels
                transform: Translate {
                    x: Theme.px(stage.slideX, stage.pixelRatio)
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

                    Row {
                        id: pageHeading

                        readonly property real crumbExtent: crumbLabel.implicitWidth + Theme.iconSize + spacing * 2
                        readonly property bool showCrumb: host.crumbTitle !== "" && crumbExtent + Math.ceil(titleMetrics.advanceWidth) <= width

                        anchors.left: backSlot.right
                        anchors.right: parent.right
                        anchors.rightMargin: Math.max(0, root.windowButtonsReserve - (host.width - pageHeader.width) / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS
                        visible: host.pageTitle !== ""

                        StyledText {
                            id: crumbLabel
                            text: host.crumbTitle
                            font.pixelSize: Theme.fontSizeXXLarge
                            color: Theme.surfaceVariantText
                            visible: pageHeading.showCrumb

                            StateLayer {
                                anchors.margins: -Theme.spacingXS
                                cornerRadius: Theme.cornerRadiusS
                                stateColor: Theme.surfaceText
                                onClicked: root.goBack()
                            }
                        }

                        DIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "chevron_right"
                            size: Theme.iconSize
                            color: Theme.surfaceVariantText
                            rotation: I18n.isRtl ? 180 : 0
                            visible: pageHeading.showCrumb
                        }

                        StyledText {
                            id: pageTitleLabel
                            text: titleMetrics.elidedText
                            font.pixelSize: Theme.fontSizeXXLarge
                            color: Theme.surfaceText
                        }

                        // An eliding Text reports its elided width as implicitWidth, so the full title is measured here
                        TextMetrics {
                            id: titleMetrics
                            font: pageTitleLabel.font
                            text: host.pageTitle
                            elide: Text.ElideRight
                            elideWidth: pageHeading.width
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
            }

            // Disabling a page walks every control in it, so one on its way in or out is shielded from the pointer
            MouseArea {
                anchors.fill: parent
                visible: !host.pageActive
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true
                onWheel: wheel => wheel.accepted = true
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
            "accessibility": "AccessibilityTab.qml",
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
            "dash_sysmon_card": "DashSysmonCardTab.qml",
            "audio": "AudioTab.qml",
            "locale": "LocaleTab.qml",
            "multiplexers": "MuxTab.qml",
            "users": "UsersTab.qml",
            "user_create": "CreateUserTab.qml",
            "greeter_auth": "GreeterAuthTab.qml",
            "autostart": "AutoStartTab.qml",
            "battery": "BatteryTab.qml",
            "dank_dash": "DDashTab.qml",
            "wellbeing_limits": "WellbeingLimitsTab.qml",
            "wellbeing_breaks": "WellbeingBreaksTab.qml",
            "wellbeing_alerts": "WellbeingAlertsTab.qml",
            "wellbeing_stats": "WellbeingStatsTab.qml",
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

    readonly property var pagesWithParentModal: ["dankbar_widgets", "window_rules", "notification_rules", "display_config", "users", "time_weather", "weather", "lock_screen", "greeter", "dank_dash", "wallpaper_cycling", "wallpaper_folders", "wallpaper_folder", "theme_schedule", "surface_shadows", "keybinds", "dankbar_settings", "dankbar_appearance", "bar_widget", "dock_general", "dock_widgets", "dock_appearance", "dock_advanced", "fcitx5", "global_shortcuts", "launcher", "theme", "theme_apps", "media_player", "desktop_widgets", "desktop_widget", "dash_sysmon_card", "autostart", "compositor_layout", "compositor_includes", "motion", "updater", "display_gamma", "about", "profiles", "profile_edit", "profile_inspect", "network_connections", "network_connection", "network_ethernet", "network_wifi", "network_hotspot", "network_wifi_connect", "network_vpn", "network_cellular", "network_tailscale", "network_tailscale_add", "screenshot", "osd"]

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

        readonly property real slideDistance: I18n.isRtl ? -SettingsMetrics.pageSlideDistance : SettingsMetrics.pageSlideDistance

        pushEnter: PageMotion {}
        pushExit: PageMotion {}
        popEnter: PageMotion {}
        popExit: PageMotion {}
        replaceEnter: PageMotion {}
        replaceExit: PageMotion {}

        onWidthChanged: root._fitPages()
        onHeightChanged: root._fitPages()
        onBusyChanged: {
            if (!busy)
                anticipation.restart();
        }
    }
}
