pragma ComponentBehavior: Bound

import Qt.labs.folderlistmodel
import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../DCommon/Common/MaterialWallpaper.js" as Art
import "../Common/WallpaperFormats.js" as WallpaperFormats

DContextMenu {
    id: root

    property bool settingsExpanded: false
    property var stripItems: []
    property string widgetInstanceId: ""

    readonly property int stripCount: 4
    readonly property real stripUnit: Theme.listItemHeight
    readonly property string currentWallpaper: {
        if (SessionData.perMonitorWallpaper && targetScreen)
            return SessionData.getMonitorWallpaper(targetScreen.name) || "";
        return SessionData.wallpaperPath || "";
    }
    readonly property string wallpaperDir: currentWallpaper.startsWith("/") ? currentWallpaper.substring(0, currentWallpaper.lastIndexOf("/")) : ""
    readonly property bool materialWallpaper: currentWallpaper === ""
    readonly property var materialTarget: SessionData.materialWallpaperTarget(targetScreen?.name ?? "")
    readonly property var materialEntry: SessionData.materialWallpaperEntry(materialTarget)
    readonly property bool listMode: WallpaperLibraryService.enabled
    readonly property int libraryRevision: WallpaperLibraryService.revision
    readonly property string currentKey: {
        if (materialWallpaper)
            return Art.resolvePreset(materialEntry.preset, SessionData.materialWallpaperProfiles);
        return listMode ? WallpaperLibraryService.listedPath(currentWallpaper) : currentWallpaper;
    }

    layerNamespace: "dms:desktop-context-menu"
    keyboardNavigable: true
    itemFontSize: Theme.fontSizeMedium
    minMenuWidth: stripUnit * (stripCount + 1) + Theme.spacingS * (stripCount + 1)

    menuItems: {
        const instanceId = widgetInstanceId;
        const items = instanceId === "" ? [] : [
            {
                type: "item",
                icon: "tune",
                text: I18n.tr("Widget settings"),
                action: () => DesktopWidgetRegistry.editOptions(root.targetScreen, instanceId)
            },
            {
                type: "separator"
            }
        ];
        items.push({
            type: "item",
            icon: "edit",
            text: I18n.tr("Edit widgets"),
            action: () => DesktopWidgetRegistry.startEditing(root.targetScreen, false)
        }, {
            type: "item",
            icon: "extension",
            text: I18n.tr("Plugins"),
            action: () => PopoutService.openSettingsWithTab("plugins")
        }, {
            type: "item",
            icon: "palette",
            text: I18n.tr("Wallpaper & colors"),
            action: () => PopoutService.openSettingsWithTab("personalization")
        });
        if (wallpaperDir || materialWallpaper)
            items.push({
                type: "component",
                component: wallpaperStrip,
                height: stripUnit * 2 + Theme.spacingS
            });
        return items.concat([settingsEntry, allSettingsEntry, desktopWidgetsEntry, displaysEntry]);
    }

    component MenuEntry: QtObject {
        property string type: "item"
        property string icon
        property string text
        property string trailingIcon
        property real indent
        property bool keepOpen
        property bool hidden
        property var action
    }

    MenuEntry {
        id: settingsEntry
        icon: "settings"
        text: I18n.tr("Settings")
        trailingIcon: root.settingsExpanded ? "expand_less" : "expand_more"
        keepOpen: true
        action: () => root.settingsExpanded = !root.settingsExpanded
    }

    MenuEntry {
        id: allSettingsEntry
        icon: "tune"
        text: I18n.tr("All settings")
        indent: Theme.spacingS
        hidden: !root.settingsExpanded
        action: () => PopoutService.openSettings()
    }

    MenuEntry {
        id: desktopWidgetsEntry
        icon: "widgets"
        text: I18n.tr("Desktop widgets")
        indent: Theme.spacingS
        hidden: !root.settingsExpanded
        action: () => PopoutService.openSettingsWithTab("desktop_widgets")
    }

    MenuEntry {
        id: displaysEntry
        icon: "monitor"
        text: I18n.tr("Displays")
        indent: Theme.spacingS
        hidden: !root.settingsExpanded
        action: () => PopoutService.openSettingsWithTab("displays")
    }

    onBackdropRightClicked: (x, y) => openForWidget(targetScreen, x, y, "")
    onRenderActiveChanged: {
        settingsExpanded = false;
        stripItems = renderActive && materialWallpaper ? leadWithCurrent(presetItems()) : [];
        fillFromLibrary();
        if (!renderActive)
            widgetInstanceId = "";
    }
    onLibraryRevisionChanged: fillFromLibrary()
    onWallpaperDirChanged: {
        if (!listMode)
            stripItems = [];
    }

    function openForWidget(screen, x, y, instanceId) {
        widgetInstanceId = instanceId;
        open(screen, x, y, false);
    }

    function pick(item) {
        if (item.path) {
            setWallpaper(item.path);
            return;
        }
        SessionData.setMaterialWallpaperPreset(materialTarget, item.key);
    }

    function setWallpaper(path) {
        SessionData.applyWallpaperPick(targetScreen?.name ?? "", path);
    }

    // Order is fixed per open so a pick moves the check, not the list.
    function leadWithCurrent(items) {
        const start = Math.max(0, items.findIndex(item => item.key === currentKey));
        return items.slice(start).concat(items.slice(0, start));
    }

    function presetItems() {
        const profiles = SessionData.materialWallpaperProfiles;
        return Art.profiles(profiles).map(profile => ({
                    key: profile.id,
                    path: "",
                    composition: Art.composition({
                        preset: profile.id,
                        seed: materialEntry.seed
                    }, profiles)
                }));
    }

    function loadStrip(paths) {
        stripItems = leadWithCurrent(paths.map(path => ({
                    key: path,
                    path
                })));
    }

    function loadFolderStrip(model) {
        const paths = [];
        for (let i = 0; i < model.count; i++)
            paths.push(model.get(i, "filePath"));
        loadStrip(paths);
    }

    function fillFromLibrary() {
        if (renderActive && listMode && !materialWallpaper && stripItems.length === 0 && WallpaperLibraryService.loaded)
            loadStrip(WallpaperLibraryService.selected(WallpaperLibraryService.items).map(item => item.path));
    }

    Ref {
        service: WallpaperLibraryService
        active: root.renderActive && WallpaperLibraryService.enabled && root.wallpaperDir !== ""
    }

    Loader {
        active: root.renderActive && root.wallpaperDir !== "" && !WallpaperLibraryService.enabled

        sourceComponent: Item {
            FolderListModel {
                id: folderModel
                showDirs: false
                showDotAndDotDot: false
                caseSensitive: false
                nameFilters: WallpaperFormats.nameFilters(true)
                folder: "file://" + root.wallpaperDir.split("/").map(s => encodeURIComponent(s)).join("/")
                onStatusChanged: {
                    if (folderModel.status === FolderListModel.Ready)
                        root.loadFolderStrip(folderModel);
                }
            }
        }
    }

    Component {
        id: wallpaperStrip

        Item {
            DCarousel {
                x: root.menuPadding
                y: Theme.spacingXS
                width: parent.width - root.menuPadding * 2
                height: root.stripUnit * 2
                preferredItemWidth: width / 2
                itemRadius: Theme.cornerRadiusM
                model: root.stripItems

                delegate: DCarouselItem {
                    id: thumb

                    required property var modelData
                    readonly property bool current: thumb.modelData.key === root.currentKey

                    onClicked: {
                        if (!thumb.current)
                            root.pick(thumb.modelData);
                    }

                    Loader {
                        anchors.fill: parent
                        sourceComponent: thumb.modelData.path ? imageThumb : materialThumb

                        Component {
                            id: imageThumb

                            CachingImage {
                                imagePath: VideoWallpaperService.imageFor(thumb.modelData.path)
                                maxCacheSize: 256
                                animate: false
                            }
                        }

                        Component {
                            id: materialThumb

                            MaterialWallpaper {
                                composition: thumb.modelData.composition
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: Theme.iconSizeLarge
                        height: width
                        radius: width / 2
                        color: Theme.primaryContainer
                        scale: thumb.current ? 1 : 0
                        visible: scale > 0

                        Behavior on scale {
                            NumberAnimation {
                                duration: SettingsData.reduceMotion ? 0 : Theme.expressiveDurations.expressiveFastSpatial
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                            }
                        }

                        DIcon {
                            anchors.centerIn: parent
                            name: "check"
                            size: Theme.iconSizeMedium
                            color: Theme.onPrimaryContainer
                        }
                    }
                }
            }
        }
    }
}
