pragma ComponentBehavior: Bound
import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins
import qs.Modules.Dock
import qs.Modules.SurfaceWidgets
import qs.Common.settings
import "../../../Common/settings/DockConfig.js" as DockConfig

BasePill {
    id: root
    property var surfaceContext: null
    property var widgetData: null
    property var topBar: null
    property bool isAutoHideBar: false
    readonly property bool dockHosted: surfaceContext?.kind === "dock"
    function appOption(key, fallback) {
        if (!dockHosted)
            return SettingsData.widgetOption("appsDock", widgetData, key);
        return widgetData?.[key] ?? fallback;
    }
    // A dock reads strip options from its own configuration; a bar keeps per-instance copies.
    readonly property var appOptions: {
        const defaults = DockConfig.create("", "");
        const options = dockHosted ? Object.assign(defaults, surfaceContext.config, widgetData?.options ?? {}) : Object.assign(defaults, {
            position: barConfig?.position ?? 0,
            iconSize: Theme.barIconSize(barThickness, undefined, barConfig?.maximizeWidgetIcons, barConfig?.iconScale),
            groupByApp: true,
            itemSpacing: appOption("appsDockSpacing", 4),
            maxVisibleApps: appOption("barMaxVisibleApps", defaults.maxVisibleApps),
            maxVisibleRunningApps: appOption("barMaxVisibleRunningApps", defaults.maxVisibleRunningApps),
            showOverflowBadge: appOption("barShowOverflowBadge", defaults.showOverflowBadge),
            launcherEnabled: appOption("launcherEnabled"),
            launcherLogoMode: appOption("launcherLogoMode"),
            launcherLogoCustomPath: appOption("launcherLogoCustomPath"),
            launcherLogoColorOverride: appOption("launcherLogoColorOverride"),
            launcherLogoSizeOffset: appOption("launcherLogoSizeOffset"),
            launcherLogoBrightness: appOption("launcherLogoBrightness"),
            launcherLogoContrast: appOption("launcherLogoContrast"),
            enlargeOnHover: appOption("appsDockEnlargeOnHover"),
            enlargePercentage: appOption("appsDockEnlargePercentage")
        });
        return Object.assign(options, {
            iconSize: Math.min(options.iconSize, surfaceContext?.widgetThickness ?? options.iconSize),
            compact: dockHosted || appOption("runningAppsCompactMode", true),
            currentWorkspace: appOption("runningAppsCurrentWorkspace", false),
            hideIndicators: appOption("appsDockHideIndicators", false),
            colorizeActive: appOption("appsDockColorizeActive", false),
            activeColorMode: appOption("appsDockActiveColorMode", "primary"),
            magnification: dockHosted && (surfaceContext?.config?.magnification ?? false),
            magnificationScale: dockHosted ? (surfaceContext?.config?.magnificationScale ?? 130) : 130,
            magnificationProfile: dockHosted ? (surfaceContext?.config?.magnificationProfile ?? "parabolic") : "parabolic",
            magnificationExpand: dockHosted && (surfaceContext?.config?.magnificationExpand ?? false),
            iconSizePercentage: dockHosted ? 100 : appOption("appsDockIconSizePercentage"),
            // The Dux Icons badge is too small to read at bar size.
            bareIcons: !dockHosted
        });
    }
    property bool renderItems: true
    property var mixedStrip: null
    property var stripItem: null
    function focusFirst() {
        stripItem?.focusFirst();
    }
    readonly property bool interactionActive: appMenu.visible || trashMenu.visible || (stripItem?.requestDockShow ?? false) || (stripItem?.draggedIndex ?? -1) >= 0
    readonly property var hoveredButton: stripItem?.hoveredButton ?? null
    enableBackgroundHover: false
    enableCursor: false
    // Dock apps sit straight on the dock surface; a widget pill around them would read as a second dock.
    noBackground: dockHosted || !widgetBackground

    content: Component {
        ApplicationStrip {
            id: apps
            renderItems: root.renderItems
            mixedStrip: root.mixedStrip
            surfaceContext: root.surfaceContext
            options: root.appOptions
            dockScreen: root.parentScreen
            isVertical: root.isVerticalOrientation
            iconSize: root.appOptions.iconSize
            groupByApp: root.appOptions.groupByApp
            usesOverlayLayer: root.surfaceContext?.host?.usesOverlayLayer ?? false
            contextMenu: appMenu
            trashContextMenu: trashMenu
            Component.onCompleted: root.stripItem = apps
        }
    }
    Loader {
        id: appMenuLoader
        active: false
        property bool folderMode: false
        readonly property DockContextMenuBase menu: item as DockContextMenuBase
        sourceComponent: folderMode ? folderMenuComponent : appMenuComponent
    }
    Component {
        id: appMenuComponent
        DockContextMenu {
            options: root.appOptions
        }
    }
    Component {
        id: folderMenuComponent
        DockFolderMenu {
            options: root.appOptions
        }
    }
    Loader {
        id: trashMenuLoader
        active: false
        sourceComponent: DockTrashContextMenu {
            options: root.appOptions
        }
    }
    QtObject {
        id: appMenu
        readonly property bool visible: appMenuLoader.menu?.visible ?? false
        readonly property DockFolderMenu folderMenu: appMenuLoader.menu as DockFolderMenu

        function closeFolder() {
            folderMenu?.close();
        }
        function updateFolderDrop(item, x, y) {
            return folderMenu?.updatePinDrop(item, x, y) ?? "";
        }
        function clearFolderDrop() {
            if (folderMenu)
                folderMenu.receivingPin = false;
        }

        function showFolder(button, dockScreen, rename = false) {
            if (folderMenu?.visible && folderMenu.anchorItem === button && !rename) {
                folderMenu.close();
                return;
            }
            appMenuLoader.folderMode = true;
            appMenuLoader.active = true;
            appMenuLoader.menu.show(button, button.height, dockScreen);
            folderMenu.renaming = rename;
        }
        function showForButton(button, data, dockHeight, hidePinOption, entry, dockScreen, parentDockApps) {
            appMenuLoader.folderMode = false;
            appMenuLoader.active = true;
            const menu = appMenuLoader.item as DockContextMenu;
            menu.showForButton(button, data, dockHeight, hidePinOption, entry, dockScreen, parentDockApps);
        }
    }
    QtObject {
        id: trashMenu
        readonly property bool visible: trashMenuLoader.item?.visible ?? false

        function showForButton(button, dockHeight, dockScreen, parentDockApps) {
            trashMenuLoader.active = true;
            trashMenuLoader.item.showForButton(button, dockHeight, dockScreen, parentDockApps);
        }
    }
}
