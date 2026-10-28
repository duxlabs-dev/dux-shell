pragma ComponentBehavior: Bound

import Qt.labs.folderlistmodel
import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../DCommon/Common/MaterialWallpaper.js" as Art

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
    readonly property string currentKey: materialWallpaper ? Art.resolvePreset(materialEntry.preset, SessionData.materialWallpaperProfiles) : currentWallpaper

    layerNamespace: "dms:desktop-context-menu"
    keyboardNavigable: true
    itemHeight: Theme.listItemHeight + Theme.densityStepM
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
        hidden: !root.settingsExpanded
        action: () => PopoutService.openSettings()
    }

    MenuEntry {
        id: desktopWidgetsEntry
        icon: "widgets"
        text: I18n.tr("Desktop widgets")
        hidden: !root.settingsExpanded
        action: () => PopoutService.openSettingsWithTab("desktop_widgets")
    }

    MenuEntry {
        id: displaysEntry
        icon: "monitor"
        text: I18n.tr("Displays")
        hidden: !root.settingsExpanded
        action: () => PopoutService.openSettingsWithTab("displays")
    }

    onBackdropRightClicked: (x, y) => openForWidget(targetScreen, x, y, "")
    onRenderActiveChanged: {
        settingsExpanded = false;
        stripItems = renderActive && materialWallpaper ? leadWithCurrent(presetItems()) : [];
        if (!renderActive)
            widgetInstanceId = "";
    }
    onWallpaperDirChanged: stripItems = []

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
        if (SessionData.perMonitorWallpaper && targetScreen) {
            SessionData.setMonitorWallpaper(targetScreen.name, path);
            SessionData.setMonitorCyclingFolderPath(targetScreen.name, "");
            return;
        }
        SessionData.setWallpaper(path);
        SessionData.wallpaperCyclingFolderPath = "";
        SessionData.saveSettings();
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

    function loadStrip(model) {
        const items = [];
        for (let i = 0; i < model.count; i++) {
            const path = model.get(i, "filePath");
            items.push({
                key: path,
                path
            });
        }
        stripItems = leadWithCurrent(items);
    }

    Loader {
        active: root.renderActive && root.wallpaperDir !== ""

        sourceComponent: Item {
            FolderListModel {
                id: folderModel
                showDirs: false
                showDotAndDotDot: false
                caseSensitive: false
                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.exr", "*.svg"]
                folder: "file://" + root.wallpaperDir.split("/").map(s => encodeURIComponent(s)).join("/")
                onStatusChanged: {
                    if (folderModel.status === FolderListModel.Ready)
                        root.loadStrip(folderModel);
                }
            }
        }
    }

    Component {
        id: wallpaperStrip

        Item {
            DCarousel {
                y: Theme.spacingXS
                width: parent.width
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
                                imagePath: thumb.modelData.path
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
