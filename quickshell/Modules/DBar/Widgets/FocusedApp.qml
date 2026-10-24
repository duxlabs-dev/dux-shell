import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

BasePill {
    id: root

    property var widgetData: null
    property bool showAppName: SettingsData.widgetOption("focusedWindow", widgetData, "focusedWindowShowAppName")
    property bool showWindowTitle: SettingsData.widgetOption("focusedWindow", widgetData, "focusedWindowShowWindowTitle")
    property bool showIcon: SettingsData.widgetOption("focusedWindow", widgetData, "focusedWindowShowIcon")
    readonly property int maxWidth: {
        const size = SettingsData.widgetOption("focusedWindow", widgetData, "focusedWindowSize");
        switch (size) {
        case 0:
            return 288;
        case 2:
            return 656;
        case 3:
            return 856;
        default:
            return 456;
        }
    }
    property real allottedPrimarySize: 0
    property real availableWidth: allottedPrimarySize > 0 ? allottedPrimarySize : maxWidth
    readonly property real naturalPrimarySize: isVerticalOrientation ? height : !hasWindowsOnCurrentWorkspace ? 0 : Theme.pxCeil(Math.min(contentItem?.naturalWidth ?? 0, maxWidth - horizontalPadding * 2) + horizontalPadding * 2, dpr)
    readonly property real minimumPrimarySize: isVerticalOrientation ? height : Math.min(naturalPrimarySize, Theme.snap((contentItem?.minimumWidth ?? 0) + horizontalPadding * 2, dpr))
    readonly property real effectiveHorizontalWidth: Math.max(0, Math.min(maxWidth, availableWidth))
    readonly property real effectiveHorizontalInnerWidth: Math.max(0, effectiveHorizontalWidth - horizontalPadding * 2)
    property var activeWindow: null
    property var activeDesktopEntry: null
    property bool isHovered: mouseArea.containsMouse

    readonly property string screenName: parentScreen?.name ?? ""
    readonly property bool popoutVisible: focusedWindowPopoutLoader.item?.shouldBeVisible ?? false

    function updateActiveWindow() {
        activeWindow = CompositorService.activeWindowForScreen(parentScreen ? parentScreen.name : null, activeWindow, popoutVisible);
    }

    Component.onCompleted: {
        updateActiveWindow();
        updateDesktopEntry();
    }

    readonly property Toplevel managerActiveToplevel: ToplevelManager.activeToplevel

    onManagerActiveToplevelChanged: updateActiveWindow()

    Connections {
        target: CompositorService
        function onToplevelsChanged() {
            root.updateActiveWindow();
        }
        function onWorkspaceStateChanged() {
            root.updateActiveWindow();
        }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.updateDesktopEntry();
        }
    }

    function syncPopoutState() {
        const popout = focusedWindowPopoutLoader.item;
        if (!popout || !activeWindow || !root.parentScreen)
            return;
        popout.currentWindow = activeWindow;
        popout.processId = CompositorService.windowPid(activeWindow);
        root.positionPopout(popout);
    }

    onActiveWindowChanged: {
        updateDesktopEntry();
        if (focusedWindowPopoutLoader.item?.shouldBeVisible) {
            if (activeWindow) {
                syncPopoutState();
                Qt.callLater(() => root.syncPopoutState());
            } else {
                focusedWindowPopoutLoader.item.close();
            }
        }
    }

    readonly property var settingsAppIdSubstitutions: SettingsData.appIdSubstitutions

    onSettingsAppIdSubstitutionsChanged: updateDesktopEntry()

    function updateDesktopEntry() {
        if (activeWindow && activeWindow.appId) {
            const moddedId = Paths.moddedAppId(activeWindow.appId);
            activeDesktopEntry = DesktopEntries.heuristicLookup(moddedId);
        } else {
            activeDesktopEntry = null;
        }
    }
    readonly property bool hasWindowsOnCurrentWorkspace: {
        CompositorService.windowStateRevision;
        if (!activeWindow || !(activeWindow.title || activeWindow.appId))
            return false;
        return CompositorService.windowOnActiveWorkspace(screenName, activeWindow, popoutVisible);
    }

    width: hasWindowsOnCurrentWorkspace ? (isVerticalOrientation ? barThickness : (effectiveHorizontalInnerWidth > 0 ? visualWidth : 0)) : 0
    height: hasWindowsOnCurrentWorkspace ? (isVerticalOrientation ? visualHeight : barThickness) : 0
    visible: hasWindowsOnCurrentWorkspace && (isVerticalOrientation || effectiveHorizontalInnerWidth > 0)

    content: Component {
        Item {
            readonly property bool iconShown: horizontalAppIcon.visible || horizontalSteamIcon.visible
            readonly property real appTextNatural: appText.visible ? Math.min(appText.implicitWidth, 180) : 0
            readonly property real naturalWidth: {
                const parts = [];
                if (iconShown)
                    parts.push(contentRow.iconSize);
                if (appText.visible)
                    parts.push(appTextNatural);
                if (appSeparator.visible)
                    parts.push(appSeparator.width);
                if (titleText.visible)
                    parts.push(titleText.implicitWidth);
                return parts.reduce((sum, part) => sum + part, 0) + Math.max(0, parts.length - 1) * contentRow.spacing;
            }
            readonly property real minimumWidth: (iconShown ? contentRow.iconSize + contentRow.spacing : 0) + Math.min(48, appText.visible ? appTextNatural : titleText.visible ? titleText.implicitWidth : 0)
            implicitWidth: {
                if (!root.hasWindowsOnCurrentWorkspace)
                    return 0;
                if (root.isVerticalOrientation)
                    return root.contentThickness;
                return Math.min(contentRow.implicitWidth, root.effectiveHorizontalInnerWidth);
            }
            width: root.isVerticalOrientation ? root.contentThickness : Math.min(implicitWidth, root.effectiveHorizontalInnerWidth)
            implicitHeight: root.contentThickness
            clip: false

            IconImage {
                id: appIcon
                anchors.centerIn: parent
                width: 18
                height: 18
                visible: root.isVerticalOrientation && activeWindow && status === Image.Ready
                source: {
                    if (!activeWindow || !activeWindow.appId)
                        return "";
                    return Paths.getAppIcon(activeWindow.appId, activeDesktopEntry);
                }
                smooth: true
                mipmap: true
                asynchronous: true
                layer.enabled: activeWindow && Paths.isDmsAppId(activeWindow.appId)
                layer.smooth: true
                layer.mipmap: true
                layer.effect: MultiEffect {
                    saturation: 0
                    colorization: 1
                    colorizationColor: Theme.primary
                }
            }

            DIcon {
                anchors.centerIn: parent
                size: 18
                name: "sports_esports"
                color: root.contentColor
                visible: root.isVerticalOrientation && activeWindow && activeWindow.appId && appIcon.status !== Image.Ready && Paths.isSteamApp(activeWindow.appId)
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.isVerticalOrientation && activeWindow && activeWindow.appId && appIcon.status !== Image.Ready && !Paths.isSteamApp(activeWindow.appId)
                text: {
                    if (!activeWindow || !activeWindow.appId)
                        return "?";
                    const appName = Paths.getAppName(activeWindow.appId, activeDesktopEntry);
                    return appName.charAt(0).toUpperCase();
                }
                font.pixelSize: 10
                color: root.contentColor
            }

            Item {
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: root.barThickness

                Row {
                    id: contentRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: Theme.spacingS
                    visible: !root.isVerticalOrientation

                    readonly property real iconSize: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)

                    IconImage {
                        id: horizontalAppIcon
                        width: contentRow.iconSize
                        height: contentRow.iconSize
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.showIcon && activeWindow && status === Image.Ready
                        source: {
                            if (!activeWindow || !activeWindow.appId)
                                return "";
                            return Paths.getAppIcon(activeWindow.appId, activeDesktopEntry);
                        }
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        layer.enabled: activeWindow && Paths.isDmsAppId(activeWindow.appId)
                        layer.smooth: true
                        layer.mipmap: true
                        layer.effect: MultiEffect {
                            saturation: 0
                            colorization: 1
                            colorizationColor: Theme.primary
                        }
                    }

                    DIcon {
                        id: horizontalSteamIcon
                        width: contentRow.iconSize
                        size: contentRow.iconSize
                        anchors.verticalCenter: parent.verticalCenter
                        name: "sports_esports"
                        color: root.contentColor
                        visible: root.showIcon && activeWindow && activeWindow.appId && horizontalAppIcon.status !== Image.Ready && Paths.isSteamApp(activeWindow.appId)
                    }

                    StyledText {
                        id: appText
                        text: {
                            if (!root.showAppName || !activeWindow || !activeWindow.appId)
                                return "";
                            return Paths.getAppName(activeWindow.appId, activeDesktopEntry);
                        }
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: root.contentColor
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        width: {
                            const sp = contentRow.spacing;
                            let used = 0;
                            if (horizontalAppIcon.visible)
                                used += horizontalAppIcon.width + sp;
                            else if (horizontalSteamIcon.visible)
                                used += horizontalSteamIcon.width + sp;
                            const budget = Math.max(0, root.effectiveHorizontalInnerWidth - used);
                            return Math.min(implicitWidth, 180, budget);
                        }
                        visible: text.length > 0
                    }

                    StyledText {
                        id: appSeparator
                        text: "•"
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: Theme.outlineButton
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.showAppName && root.showWindowTitle && appText.text && titleText.text
                    }

                    StyledText {
                        id: titleText
                        text: {
                            if (!root.showWindowTitle) {
                                return "";
                            }

                            const title = activeWindow && activeWindow.title ? activeWindow.title : "";
                            const appName = appText.text;

                            if (!title || !appName)
                                return title;

                            if (title.endsWith(appName))
                                return title.substring(0, title.length - appName.length).replace(/ (-|—) $/, "");

                            return title;
                        }
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: root.contentColor
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        width: {
                            const sp = contentRow.spacing;
                            let used = 0;
                            if (horizontalAppIcon.visible)
                                used += horizontalAppIcon.width + sp;
                            else if (horizontalSteamIcon.visible)
                                used += horizontalSteamIcon.width + sp;
                            if (appText.visible)
                                used += appText.width + sp;
                            if (appSeparator.visible)
                                used += appSeparator.width + sp;
                            const budget = root.effectiveHorizontalInnerWidth - used;
                            return Math.min(implicitWidth, Math.max(0, budget));
                        }
                        visible: text.length > 0
                    }
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        hoverEnabled: root.isVerticalOrientation
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            if (root.isVerticalOrientation && activeWindow && activeWindow.appId && root.parentScreen) {
                tooltipLoader.active = true;
                if (tooltipLoader.item) {
                    const localPos = mapToItem(null, width / 2, height / 2);
                    const currentScreen = root.parentScreen;
                    const adjustedY = localPos.y + root.minTooltipY;
                    const tooltipX = root.axis?.edge === "left" ? (Theme.barHeight + (barConfig?.spacing ?? 4) + Theme.spacingXS) : (currentScreen.width - Theme.barHeight - (barConfig?.spacing ?? 4) - Theme.spacingXS);

                    const appName = Paths.getAppName(activeWindow.appId, activeDesktopEntry);
                    const title = activeWindow.title || "";
                    const tooltipText = appName + (title ? " • " + title : "");

                    const isLeft = root.axis?.edge === "left";
                    tooltipLoader.item.show(tooltipText, tooltipX, adjustedY, currentScreen, isLeft, !isLeft);
                }
            }
        }
        onExited: {
            if (tooltipLoader.item) {
                tooltipLoader.item.hide();
            }
            tooltipLoader.active = false;
        }

        acceptedButtons: Qt.LeftButton
        onClicked: {
            if (!activeWindow || !root.parentScreen)
                return;
            if (tooltipLoader.item)
                tooltipLoader.item.hide();
            tooltipLoader.active = false;

            // No context menu from inside the overflow popup; behave like a task switcher.
            const owner = BarWidgetService.registrationForItem(root)?.context?.owner;
            if (owner?.overflowAnchor) {
                CompositorService.activateToplevel(activeWindow);
                owner.overflowSurface?.close();
                return;
            }

            focusedWindowPopoutLoader.active = true;
            if (!focusedWindowPopoutLoader.item)
                return;

            root.syncPopoutState();
            focusedWindowPopoutLoader.item.toggle();
        }
    }

    Loader {
        id: tooltipLoader
        active: false
        sourceComponent: DTooltip {}
    }

    Loader {
        id: focusedWindowPopoutLoader
        active: false
        sourceComponent: FocusedWindowContextMenu {
            onPopoutClosed: root.updateActiveWindow()
        }
    }

    onPopoutVisibleChanged: {
        if (!popoutVisible)
            updateActiveWindow();
    }
}
