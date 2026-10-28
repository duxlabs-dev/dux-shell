import QtQuick
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

DFloatingWindow {
    id: settingsModal

    property var profileBrowser: profileBrowserLoader.item
    property var wallpaperBrowser: wallpaperBrowserLoader.item

    function openProfileBrowser(allowStacking) {
        profileBrowserLoader.active = true;
        if (!profileBrowserLoader.item)
            return;
        if (allowStacking !== undefined)
            profileBrowserLoader.item.allowStacking = allowStacking;
        profileBrowserLoader.item.open();
    }

    function openWallpaperBrowser(allowStacking) {
        wallpaperBrowserLoader.active = true;
        if (!wallpaperBrowserLoader.item)
            return;
        if (allowStacking !== undefined)
            wallpaperBrowserLoader.item.allowStacking = allowStacking;
        wallpaperBrowserLoader.item.open();
    }
    property alias sidebar: sidebar
    readonly property alias modalFocusScope: contentFocusScope
    readonly property alias focusPane: contentFocusScope.activePane
    property string currentPage: "personalization"
    property var pageHistory: []
    readonly property int currentTabIndex: SettingsTabs.tabIndexForPage(currentPage)
    readonly property string currentParentId: SettingsTabs.parentOf(currentPage)
    readonly property string activeCategoryId: currentParentId || currentPage
    readonly property bool isPluginPage: SettingsTabs.isPluginPage(currentPage)
    readonly property bool canGoBack: pageHistory.length > 0 || (currentParentId !== "" && (isPluginPage || SettingsTabs.visibleLeaves(currentParentId).length > 1 || !!SettingsTabs.page(currentParentId)?.hubHeader))
    property bool shouldHaveFocus: visible
    property bool allowFocusOverride: false
    property bool shouldBeVisible: false
    readonly property bool readyToMap: shouldBeVisible && content.currentPageSettled
    readonly property bool searchFocused: sidebar.searchFocused
    property bool isCompactMode: width < SettingsMetrics.compactBreakpoint
    property bool menuVisible: !isCompactMode
    property string keybindSearchQuery: ""

    signal closingModal

    function show() {
        if (visible && !backingWindowVisible) {
            visible = false;
        }
        CompositorService.closeNiriOverviewOnWindowFocus();
        if (!shouldBeVisible && isCompactMode)
            menuVisible = true;
        shouldBeVisible = true;
        if (readyToMap)
            visible = true;
        if (backingWindowVisible)
            contentFocusScope.Window.window?.requestActivate();
    }

    function hide() {
        shouldBeVisible = false;
        visible = false;
    }

    function toggle() {
        const shown = visible ? backingWindowVisible : shouldBeVisible;
        if (shown) {
            hide();
            return;
        }
        show();
    }

    function setPage(pageId: string): bool {
        const resolved = SettingsTabs.resolvePage(pageId);
        if (!resolved)
            return false;
        pageHistory = [];
        currentPage = resolved;
        return true;
    }

    // Rows report how they were activated; buttons and cards fall back to the focused control's reason
    function navigateTo(pageId, keyboard = contentFocusScope.keyboardDriven()): bool {
        const resolved = SettingsTabs.resolvePage(pageId);
        if (!resolved || resolved === currentPage)
            return false;
        content.rememberFocus();
        pageHistory = pageHistory.concat([currentPage]);
        currentPage = resolved;
        focusCurrentPage(keyboard);
        return true;
    }

    function setPageName(name: string): bool {
        return setPage(name);
    }

    function goBack(keyboard = contentFocusScope.keyboardDriven()) {
        if (pageHistory.length > 0) {
            const history = pageHistory.slice();
            const target = history.pop();
            pageHistory = history;
            currentPage = target;
            focusCurrentPage(keyboard);
            return;
        }
        if (!currentParentId)
            return;
        currentPage = currentParentId;
        focusCurrentPage(keyboard);
    }

    function setTabIndex(tabIndex: int) {
        if (tabIndex < 0)
            return;
        setPage(SettingsTabs.pageForTabIndex(tabIndex));
    }

    function showWithTab(tabIndex: int) {
        setTabIndex(tabIndex);
        show();
    }

    function showWithTabName(tabName: string) {
        setPage(tabName);
        show();
    }

    function resolveTabIndex(tabName: string): int {
        return SettingsTabs.tabIndexForPage(SettingsTabs.resolvePage(tabName));
    }

    function showKeybindsSearch(query: string) {
        keybindSearchQuery = query || "";
        // From inside settings keep the history so back returns to the calling page
        if (visible) {
            navigateTo("keybinds");
            return;
        }
        showWithTabName("keybinds");
    }

    function openPluginSettings(pluginId: string) {
        if (!pluginId)
            return;
        setPage(SettingsTabs.pluginPrefix + pluginId);
        show();
    }

    function focusCurrentPage(keyboard = true) {
        contentFocusScope.focusContent(keyboard);
    }

    function focusSidebar() {
        contentFocusScope.focusSidebar();
    }

    function focusSearch() {
        contentFocusScope.focusSearch();
    }

    function toggleMenu() {
        menuVisible = !menuVisible;
        if (menuVisible)
            focusSearch();
    }

    objectName: "settingsModal"
    title: I18n.tr("Settings", "settings window title")
    minimumSize: Qt.size(SettingsMetrics.windowMinWidth, SettingsMetrics.windowMinHeight)
    implicitWidth: SettingsMetrics.windowWidth
    implicitHeight: heightWithin(SettingsMetrics.windowHeight, SettingsMetrics.pagePaddingH * 2 + Theme.spacingL)
    visible: false

    onClosed: hide()

    onReadyToMapChanged: {
        if (readyToMap)
            visible = true;
    }

    onIsCompactModeChanged: {
        if (!isCompactMode)
            menuVisible = true;
    }

    onCurrentPageChanged: {
        if (isCompactMode)
            menuVisible = false;
    }

    onVisibleChanged: {
        if (!visible) {
            pageHistory = [];
            closingModal();
        } else {
            const revision = contentFocusScope.focusRevision;
            Qt.callLater(() => {
                if (settingsModal.visible && revision === contentFocusScope.focusRevision)
                    settingsModal.focusSearch();
            });
        }
    }

    Connections {
        target: PluginService

        function onPluginListUpdated() {
            if (!settingsModal.isPluginPage)
                return;
            if (PluginService.availablePluginsList.length === 0)
                return;
            if (PluginService.availablePlugins[SettingsTabs.pluginIdOf(settingsModal.currentPage)])
                return;
            settingsModal.setPage("plugins");
        }
    }

    // The printers page is gated on the cups capability, which core only probes once someone subscribes.
    Ref {
        service: CupsService
        active: settingsModal.visible
    }

    LazyLoader {
        id: profileBrowserLoader
        active: false

        FileBrowserModal {
            id: profileBrowserItem

            allowStacking: true
            parentModal: settingsModal
            browserTitle: I18n.tr("Select Profile Image", "profile image file browser title")
            bucket: "profile"
            showHiddenFiles: true
            filters: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.exr", "*.svg"]
            onAccepted: paths => PortalService.setProfileImage(paths[0])
            onDialogClosed: () => {
                allowStacking = true;
                Qt.callLater(() => profileBrowserLoader.active = false);
            }
        }
    }

    LazyLoader {
        id: wallpaperBrowserLoader
        active: false

        FileBrowserModal {
            id: wallpaperBrowserItem

            allowStacking: true
            parentModal: settingsModal
            browserTitle: I18n.tr("Select Wallpaper", "wallpaper file browser title")
            bucket: "wallpaper"
            showHiddenFiles: true
            filters: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.exr", "*.svg"]
            onAccepted: paths => {
                SessionData.setWallpaper(paths[0]);
                SessionData.wallpaperCyclingFolderPath = "";
                SessionData.saveSettings();
            }
            onDialogClosed: () => {
                allowStacking = true;
                Qt.callLater(() => wallpaperBrowserLoader.active = false);
            }
        }
    }

    SettingsPaneNavigation {
        id: contentFocusScope

        sidebar: sidebar
        content: content
        parentModal: settingsModal

        LayoutMirroring.enabled: I18n.isRtl
        LayoutMirroring.childrenInherit: true

        anchors.fill: parent
        focus: true

        Keys.onBackPressed: event => {
            settingsModal.goBack();
            event.accepted = true;
        }

        Column {
            anchors.fill: parent
            spacing: 0

            DWindowHeader {
                id: titleBar
                width: parent.width
                z: 10
                controls: windowControls
                title: I18n.tr("Settings")
                onCloseRequested: settingsModal.hide()
            }

            Item {
                id: readOnlyBanner

                property bool showBanner: (SettingsData.isReadOnly && SettingsData.unsavedUserChanges) || (SessionData._isReadOnly && SessionData._hasUnsavedChanges)

                width: parent.width
                height: showBanner ? bannerContent.implicitHeight + Theme.spacingM * 2 : 0
                visible: showBanner
                clip: true

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: body.paneInset
                    anchors.rightMargin: body.paneInset
                    radius: SettingsMetrics.paneRadius
                    color: SettingsMetrics.paneColor
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium
                }

                Behavior on height {
                    NumberAnimation {
                        duration: SettingsMetrics.fadeDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }

                Row {
                    id: bannerContent

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spacingM
                    anchors.leftMargin: body.paneInset + SettingsMetrics.panePadding
                    anchors.rightMargin: body.paneInset + SettingsMetrics.panePadding
                    spacing: Theme.spacingM

                    DIcon {
                        name: "info"
                        size: Theme.iconSize
                        color: Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        id: bannerText

                        text: I18n.tr("Settings are read-only. Changes will not persist.", "read-only settings warning for NixOS home-manager users")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(SettingsMetrics.bannerTextMinWidth, parent.width - (copySettingsButton.visible ? copySettingsButton.width + Theme.spacingM : 0) - (copySessionButton.visible ? copySessionButton.width + Theme.spacingM : 0) - Theme.spacingM * 2 - Theme.iconSize)
                        wrapMode: Text.WordWrap
                    }

                    DButton {
                        id: copySettingsButton

                        visible: SettingsData.isReadOnly && SettingsData.unsavedUserChanges
                        text: "settings.json"
                        iconName: "content_copy"
                        backgroundColor: Theme.primary
                        textColor: Theme.primaryText
                        buttonHeight: Theme.buttonHeightXS
                        horizontalPadding: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            Quickshell.execDetached(["dms", "cl", "copy", SettingsData.getCurrentSettingsJson()]);
                            ToastService.showInfo(I18n.tr("Copied to clipboard"));
                        }
                    }

                    DButton {
                        id: copySessionButton

                        visible: SessionData._isReadOnly && SessionData._hasUnsavedChanges
                        text: "session.json"
                        iconName: "content_copy"
                        backgroundColor: Theme.primary
                        textColor: Theme.primaryText
                        buttonHeight: Theme.buttonHeightXS
                        horizontalPadding: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            Quickshell.execDetached(["dms", "cl", "copy", SessionData.getCurrentSessionJson()]);
                            ToastService.showInfo(I18n.tr("Copied to clipboard"));
                        }
                    }
                }
            }

            Item {
                id: body

                readonly property real paneInset: SettingsMetrics.paneMargin
                readonly property real paneSpace: width - sidebar.width - paneInset

                width: parent.width
                height: parent.height - titleBar.height - readOnlyBanner.height
                clip: true

                SettingsSidebar {
                    id: sidebar

                    anchors.left: parent.left
                    width: settingsModal.isCompactMode ? parent.width : sidebar.implicitWidth
                    parentModal: settingsModal
                    visible: !settingsModal.isCompactMode || settingsModal.menuVisible
                    currentPage: settingsModal.currentPage
                    activeCategoryId: settingsModal.activeCategoryId
                    onPageRequested: pageId => {
                        settingsModal.setPage(pageId);
                        if (settingsModal.isCompactMode)
                            settingsModal.menuVisible = false;
                    }
                }

                Rectangle {
                    id: contentPane
                    enabled: !settingsModal.isCompactMode || !settingsModal.menuVisible

                    x: {
                        const flip = I18n.isRtl ? -1 : 1;
                        if (settingsModal.isCompactMode)
                            return (settingsModal.menuVisible ? body.width * flip : 0) + body.paneInset;
                        const slack = (body.paneSpace - width) / 2;
                        return (I18n.isRtl ? body.paneInset : sidebar.width) + slack;
                    }
                    width: settingsModal.isCompactMode ? body.width - body.paneInset * 2 : Math.min(body.paneSpace, SettingsMetrics.paneMaxWidth)
                    height: body.height - body.paneInset
                    radius: SettingsMetrics.paneRadius
                    color: SettingsMetrics.paneColor
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium
                    clip: true

                    Behavior on x {
                        enabled: settingsModal.isCompactMode && !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                        NumberAnimation {
                            duration: SettingsMetrics.transitionDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.standard
                        }
                    }

                    SettingsContent {
                        id: content

                        anchors.fill: parent
                        parentModal: settingsModal
                        currentPage: settingsModal.currentPage
                    }
                }
            }
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: settingsModal
    }
}
