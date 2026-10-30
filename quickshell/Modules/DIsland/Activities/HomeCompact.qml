pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import qs.Common
import qs.Modules.DBar.Widgets
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    required property var controller
    required property var systemModel

    readonly property bool tight: root.controller.homeCompactTight
    readonly property real slotSize: root.tight ? Theme.iconSize : Theme.iconSizeLarge
    readonly property real textSize: root.tight ? Theme.fontSizeSmall : Theme.fontSizeMedium
    readonly property real iconSize: root.textSize + Theme.spacingXS
    readonly property real statusIconSize: root.textSize + Theme.spacingXXS

    Ref {
        service: PrivacyService
    }
    readonly property real groupSpacing: root.controller.homeSlotMargin
    readonly property bool isVertical: root.controller.isVertical
    readonly property string clockDisplay: root.controller.homeClockDisplay
    readonly property real edgePad: Math.max(root.groupSpacing, ((root.isVertical ? root.height - compactColumn.height : root.width - compactRow.width)) / 2)
    readonly property bool weatherSlotEnabled: root.controller.homeWeatherEnabled
    readonly property var brightnessDevice: BrightnessService.getCurrentDeviceInfo()
    readonly property real brightnessMaximum: BrightnessService.brightnessMaximum(root.brightnessDevice)
    readonly property int brightnessPercent: root.brightnessMaximum > 0 ? Math.round(BrightnessService.brightnessLevel / root.brightnessMaximum * 100) : 0
    readonly property int volumePercent: AudioService.sinkVolumePercent
    readonly property var groupIds: root.groupsForSide("left").concat(["clock"]).concat(root.groupsForSide("right"))
    readonly property real touchpadThreshold: 100
    property real wheelAccumulator: 0
    property bool weatherRefHeld: false
    // Same options as the bar's switcher widget
    readonly property var workspaceWidgetData: SettingsData.barWidgetEntry(root.controller.barConfig, "workspaceSwitcher")

    function workspaceOption(key) {
        return SettingsData.widgetOption("workspaceSwitcher", root.workspaceWidgetData, key);
    }

    WorkspaceSwitcherModel {
        id: workspaces

        screenName: root.controller.screen?.name ?? ""
        screen: root.controller.screen
        followFocus: root.workspaceOption("workspaceFollowFocus")
        occupiedOnly: root.workspaceOption("showOccupiedWorkspacesOnly")
        showAllTags: root.workspaceOption("dwlShowAllTags")
        showPadding: root.workspaceOption("showWorkspacePadding")
        paddingCount: root.workspaceOption("workspacePaddingCount")
        showSpecial: root.workspaceOption("showSpecialWorkspaces")
        reverseScrolling: root.workspaceOption("reverseScrolling")
    }

    readonly property bool traySlotEnabled: (root.controller.homeLeftGroups.indexOf("tray") !== -1 || root.controller.homeRightGroups.indexOf("tray") !== -1)
    readonly property var allTrayItems: traySlotEnabled ? TrayMenuManager.filterEnvHidden(SystemTray.items.values) : []
    readonly property var allSortedTrayItems: TrayMenuManager.sortByPreferredOrder(allTrayItems, SessionData.trayItemOrder)
    // Same options as the bar's tray widget (a satellite entry on island bars)
    readonly property var trayWidgetData: SettingsData.barWidgetEntry(root.controller.barConfig, "systemTray")
    readonly property var visibleSortedTrayItems: allSortedTrayItems.filter(item => !SessionData.isHiddenTrayId(TrayMenuManager.getTrayItemKey(item)))
    readonly property int trayVisibleLimit: {
        const shown = root.visibleSortedTrayItems.length;
        if (!SettingsData.widgetOption("systemTray", root.trayWidgetData, "trayAutoOverflow"))
            return shown;
        const limit = Number(SettingsData.widgetOption("systemTray", root.trayWidgetData, "trayMaxVisibleItems") || 0);
        return limit > 0 ? Math.max(1, Math.min(shown, limit)) : shown;
    }
    readonly property var visibleTrayItems: visibleSortedTrayItems.slice(0, trayVisibleLimit)
    readonly property var autoOverflowTrayItems: visibleSortedTrayItems.slice(trayVisibleLimit)
    readonly property var hiddenTrayItems: allSortedTrayItems.filter(item => !root.visibleTrayItems.includes(item))

    function isManualHiddenTrayItem(item) {
        return SessionData.isHiddenTrayId(TrayMenuManager.getTrayItemKey(item));
    }

    function isAutoOverflowTrayItem(item) {
        return root.autoOverflowTrayItems.includes(item);
    }

    function promoteTrayItemToBar(item) {
        const key = TrayMenuManager.getTrayItemKey(item);
        if (!key)
            return;
        if (SessionData.isHiddenTrayId(key)) {
            SessionData.showTrayId(key);
            return;
        }
        const order = root.allSortedTrayItems.map(entry => TrayMenuManager.getTrayItemKey(entry));
        const from = order.indexOf(key);
        if (from < 0)
            return;
        order.splice(from, 1);
        order.splice(Math.max(0, Math.min(root.trayVisibleLimit - 1, order.length)), 0, key);
        SessionData.setTrayItemOrder(order);
    }

    property int trayDraggedIndex: -1
    property int trayDropTargetIndex: -1
    property bool suppressTrayShiftAnimation: false

    function beginTrayDrag(visualIndex) {
        root.trayDraggedIndex = visualIndex;
        root.trayDropTargetIndex = visualIndex;
    }

    function updateTrayDrag(axisOffset, visualIndex, itemSize) {
        const slotOffset = Math.round(axisOffset / itemSize);
        const visualTargetIndex = Math.max(0, Math.min(root.visibleTrayItems.length - 1, visualIndex + slotOffset));
        if (visualTargetIndex !== root.trayDropTargetIndex)
            root.trayDropTargetIndex = visualTargetIndex;
    }

    function finishTrayDrag() {
        const fromIdx = root.trayDraggedIndex;
        const toIdx = root.trayDropTargetIndex;
        root.trayDraggedIndex = -1;
        root.trayDropTargetIndex = -1;

        const didReorder = toIdx >= 0 && fromIdx >= 0 && toIdx !== fromIdx;
        if (didReorder) {
            const fromItem = root.visibleTrayItems[fromIdx];
            const toItem = root.visibleTrayItems[toIdx];
            const fromKey = TrayMenuManager.getTrayItemKey(fromItem);
            const toKey = TrayMenuManager.getTrayItemKey(toItem);
            const allKeys = root.allSortedTrayItems.map(item => TrayMenuManager.getTrayItemKey(item));
            const nextOrder = TrayMenuManager.reorderItemKeys(allKeys, fromKey, toKey);
            if (nextOrder) {
                root.suppressTrayShiftAnimation = true;
                SessionData.setTrayItemOrder(nextOrder);
                Qt.callLater(() => root.suppressTrayShiftAnimation = false);
            }
        }
        return didReorder;
    }

    Connections {
        target: TrayMenuManager
        enabled: root.traySlotEnabled

        function onOpenTrayMenuRequested() {
            Qt.callLater(() => {
                const screen = root.controller.screen;
                const request = TrayMenuManager.claimMenuRequest(screen?.name);
                if (!request)
                    return;

                const item = TrayMenuManager.findTrayItem(request.itemId);
                if (!item || !item.hasMenu || !root.trayContextMenu)
                    return;

                const edge = root.controller.edge;
                let targetX = 0;
                let targetY = 0;
                if (edge === "bottom" || edge === "top") {
                    targetX = root.screenPosAt(root, root.width / 2, 0).x;
                    targetY = root.islandEdgeCoord();
                } else {
                    targetX = root.islandEdgeCoord();
                    targetY = root.screenPosAt(root, 0, root.height / 2).y;
                }

                root.trayContextMenu.openFor(item, targetX, targetY, screen, edge);
            });
        }
    }

    // The island sits inside a host window, so mapToGlobal is window-relative, not screen space.
    function screenPosAt(item, x, y) {
        const p = item.mapToItem(null, x, y);
        return Qt.point(p.x + root.controller.sectionOriginX, p.y + root.controller.sectionOriginY);
    }

    function islandEdgeCoord() {
        const edge = root.controller.edge;
        switch (edge) {
        case "bottom":
            return root.screenPosAt(root, 0, 0).y;
        case "top":
            return root.screenPosAt(root, 0, root.height).y;
        case "left":
            return root.screenPosAt(root, root.width, 0).x;
        case "right":
            return root.screenPosAt(root, 0, 0).x;
        }
        return 0;
    }

    function trayIconSourceFor(trayItem) {
        return TrayMenuManager.iconSourceFor(trayItem);
    }

    function groupsForSide(side) {
        const groups = side === "left" ? root.controller.homeLeftGroups : root.controller.homeRightGroups;
        return groups.filter(id => root.groupShown(id));
    }

    function groupShown(id) {
        switch (id) {
        case "weather":
            return root.controller.homeWeatherEnabled && WeatherService.weather.available;
        case "notifications":
            return root.controller.homeNotificationBadge;
        case "volume":
            return !!AudioService.sink?.audio;
        case "brightness":
            return BrightnessService.brightnessAvailable && !!root.brightnessDevice;
        case "privacy":
            return PrivacyService.anyPrivacyActive;
        case "workspaces":
            return workspaces.available;
        case "tray":
            return root.visibleTrayItems.length > 0 || root.hiddenTrayItems.length > 0;
        }
        return true;
    }

    function wheelDirection(delta) {
        const isMouseWheel = Math.abs(delta) >= 120 && Math.abs(delta) % 120 === 0;
        if (isMouseWheel)
            return delta > 0 ? 1 : -1;
        root.wheelAccumulator += delta;
        if (Math.abs(root.wheelAccumulator) < root.touchpadThreshold)
            return 0;
        const direction = root.wheelAccumulator > 0 ? 1 : -1;
        root.wheelAccumulator = 0;
        return direction;
    }

    function activateGroup(groupId) {
        switch (groupId) {
        case "media":
            if (root.controller.mediaAvailable) {
                root.controller.requestActivity("media", true, true);
                return;
            }
            root.controller.requestLauncher("", "", false);
            return;
        case "weather":
            root.controller.requestWeather(false);
            return;
        case "notifications":
            root.controller.requestNotificationCenter(false);
            return;
        case "volume":
        case "brightness":
            root.systemModel.open(groupId);
            return;
        case "privacy":
            root.controller.requestControlCenter("audioInput", false);
            return;
        }
        root.controller.requestControlCenter("", false);
    }

    function adjustSystemLevel(activityId, delta) {
        const direction = root.wheelDirection(delta);
        if (direction === 0)
            return;
        switch (activityId) {
        case "volume":
            root.adjustVolume(direction);
            return;
        case "brightness":
            root.adjustBrightness(direction);
            return;
        }
    }

    function adjustVolume(direction) {
        if (!AudioService.sink?.audio)
            return;
        SessionData.suppressOSDTemporarily();
        AudioService.adjustDefaultSinkVolume(AudioService.wheelVolumeStep, direction);
        AudioService.playVolumeChangeSoundIfEnabled();
    }

    function adjustBrightness(direction) {
        if (!root.brightnessDevice)
            return;
        SessionData.suppressOSDTemporarily();
        const next = Math.max(BrightnessService.brightnessMinimum(root.brightnessDevice), Math.min(root.brightnessMaximum, BrightnessService.brightnessLevel + direction * 5));
        BrightnessService.setGroupBrightness(next, BrightnessService.lastIpcTargets(), true);
    }

    function connectivityIconName(type) {
        if (type === "wifi") {
            if (!NetworkService.wifiAvailable || !NetworkService.networkAvailable)
                return "wifi_off";
            if (NetworkService.wifiToggling)
                return "sync";
            if (!NetworkService.wifiEnabled)
                return "wifi_off";
            return NetworkService.wifiSignalIcon;
        }

        if (!BluetoothService.available)
            return "bluetooth_disabled";
        return BluetoothService.connected ? "bluetooth_connected" : "bluetooth";
    }

    function connectivityIconColor(type) {
        if (type === "wifi") {
            if (!NetworkService.wifiAvailable || !NetworkService.networkAvailable)
                return Theme.surfaceTextMedium;
            if (NetworkService.wifiToggling || NetworkService.isWifiConnecting || NetworkService.wifiConnected)
                return Theme.primary;
            if (!NetworkService.wifiEnabled)
                return Theme.surfaceTextMedium;
            return Theme.surfaceText;
        }

        if (!BluetoothService.available || !BluetoothService.enabled)
            return Theme.surfaceTextMedium;
        return (BluetoothService.connected || BluetoothService.connecting) ? Theme.primary : Theme.surfaceText;
    }

    function connectivityIconOpacity(type) {
        if (type === "wifi")
            return NetworkService.wifiAvailable && NetworkService.networkAvailable && (NetworkService.wifiEnabled || NetworkService.wifiToggling) ? 1 : 0.5;
        return BluetoothService.available && BluetoothService.enabled ? 1 : 0.5;
    }

    function connectivityBusy(type) {
        return type === "wifi" ? (NetworkService.wifiToggling || NetworkService.isWifiConnecting) : BluetoothService.connecting;
    }

    function toggleConnectivity(type) {
        if (type === "wifi") {
            if (!NetworkService.wifiAvailable || !NetworkService.networkAvailable || NetworkService.wifiToggling || NetworkService.isWifiConnecting)
                return;
            NetworkService.toggleWifiRadio();
            return;
        }

        if (!BluetoothService.available || BluetoothService.connecting)
            return;
        BluetoothService.toggleBluetooth();
    }

    function syncWeatherRef(wanted) {
        if (wanted === weatherRefHeld)
            return;
        weatherRefHeld = wanted;
        if (wanted) {
            WeatherService.addRef();
            return;
        }
        WeatherService.removeRef();
    }

    function pushMeasuredLength() {
        root.controller.setHomeContentLength(root.isVertical ? compactColumn.implicitHeight : compactRow.implicitWidth);
    }

    onWeatherSlotEnabledChanged: root.syncWeatherRef(root.weatherSlotEnabled)
    onIsVerticalChanged: root.pushMeasuredLength()
    onVisibleTrayItemsChanged: root.pushMeasuredLength()
    Component.onCompleted: {
        root.syncWeatherRef(root.weatherSlotEnabled);
        root.pushMeasuredLength();
    }
    Component.onDestruction: root.syncWeatherRef(false)

    component IslandClock: ClockContent {
        vertical: root.isVertical
        displayMode: root.clockDisplay
        fontSize: root.textSize
        availableWidth: root.width
        dateColor: Theme.surfaceTextMedium
        separatorColor: Theme.primary
    }

    component ConnectivityIcon: Item {
        id: connectivityIcon

        required property string type

        width: root.iconSize
        height: root.iconSize
        opacity: root.connectivityIconOpacity(connectivityIcon.type)

        DIcon {
            id: connectivityGlyph

            anchors.centerIn: parent
            name: root.connectivityIconName(connectivityIcon.type)
            size: root.statusIconSize
            color: root.connectivityIconColor(connectivityIcon.type)

            DBlink {
                target: connectivityGlyph
                running: connectivityIcon.visible && root.connectivityBusy(connectivityIcon.type)
            }
        }
    }

    component PrivacyIcon: DIcon {
        required property bool active

        visible: active
        size: root.statusIconSize
        color: Theme.error
        filled: true
    }

    component GroupHoverArea: IslandSlotHoverArea {
        id: slotArea

        required property var group

        enabled: !group.isClock
        controller: root.controller
        acceptedButtons: group.isTray ? Qt.NoButton : (Qt.LeftButton | Qt.MiddleButton)

        function connectivityTypeAt(event) {
            const clickPos = group.vertical ? event.y : event.x;
            const groupMid = group.leadPad + (group.vertical ? group.height : group.width) / 2;
            return clickPos < groupMid ? "wifi" : "bluetooth";
        }

        onClicked: event => {
            if (event.button === Qt.MiddleButton) {
                if (group.usesConnectivity)
                    root.toggleConnectivity(connectivityTypeAt(event));
                if (group.isPrivacy && PrivacyService.microphoneActive && AudioService.source?.audio) {
                    SessionData.suppressOSDTemporarily();
                    AudioService.toggleMicMute();
                }
                if (group.isMedia && root.controller.mediaAvailable && MprisController.activePlayer?.canTogglePlaying)
                    MprisController.activePlayer.togglePlaying();
                if (group.isVolume && AudioService.sink?.audio) {
                    SessionData.suppressOSDTemporarily();
                    AudioService.toggleMute();
                }
                if (group.isWorkspaces)
                    workspaces.secondaryAction(null);
                return;
            }
            if (group.isWorkspaces) {
                const pager = group.pager;
                if (!pager)
                    return;
                const point = pager.mapFromItem(slotArea, event.x, event.y);
                workspaces.switchTo(pager.entryAt(point.x, point.y));
                return;
            }
            root.activateGroup(group.groupId);
        }
        onWheel: wheel => {
            if (group.isWorkspaces) {
                workspaces.handleWheel(wheel);
                wheel.accepted = true;
                return;
            }
            if (!group.isVolume && !group.isBrightness)
                return;
            root.adjustSystemLevel(group.groupId, wheel.angleDelta.y || wheel.angleDelta.x);
            wheel.accepted = true;
        }
    }

    component HomeGroup: Item {
        id: group

        required property string groupId
        required property int slotIndex

        readonly property bool vertical: root.isVertical
        readonly property real leadPad: group.slotIndex === 0 ? root.edgePad : root.groupSpacing / 2
        readonly property real trailPad: group.slotIndex === root.groupIds.length - 1 ? root.edgePad : root.groupSpacing / 2
        readonly property bool isClock: group.groupId === "clock"
        readonly property bool isMedia: group.groupId === "media"
        readonly property bool isWeather: group.groupId === "weather"
        readonly property bool isStatus: group.groupId === "status"
        readonly property bool isNotifications: group.groupId === "notifications"
        readonly property bool isVolume: group.groupId === "volume"
        readonly property bool isBrightness: group.groupId === "brightness"
        readonly property bool isPrivacy: group.groupId === "privacy"
        readonly property bool isWorkspaces: group.groupId === "workspaces"
        readonly property bool isTray: group.groupId === "tray"
        readonly property bool isSystemLevel: group.isVolume || group.isBrightness
        readonly property var pager: pagerLoader.item
        readonly property bool usesConnectivity: group.isStatus && root.controller.homeStatusContent === "connectivity"
        readonly property bool usesBattery: group.isStatus && !group.usesConnectivity && BatteryService.batteryAvailable
        readonly property bool iconOnly: group.isMedia || (group.isStatus && !group.usesBattery && !group.usesConnectivity)
        readonly property string levelDisplay: group.isVolume ? root.controller.homeVolumeDisplay : root.controller.homeBrightnessDisplay
        readonly property int levelPercent: group.isVolume ? root.volumePercent : root.brightnessPercent
        readonly property string levelReserve: group.isVolume ? String(AudioService.sinkMaxVolume) : "100"

        width: group.vertical ? root.width : (group.iconOnly ? root.iconSize : content.implicitWidth)
        height: group.vertical ? content.implicitHeight : root.slotSize

        GroupHoverArea {
            id: groupArea

            group: group
            anchors.verticalCenter: group.vertical ? undefined : parent.verticalCenter
            anchors.horizontalCenter: group.vertical ? parent.horizontalCenter : undefined
            x: group.vertical ? 0 : -group.leadPad
            y: group.vertical ? -group.leadPad : 0
            width: group.vertical ? root.width : parent.width + group.leadPad + group.trailPad
            height: group.vertical ? parent.height + group.leadPad + group.trailPad : root.height
        }

        Rectangle {
            anchors.centerIn: parent
            width: group.vertical ? root.slotSize : parent.width + Theme.spacingS
            height: group.vertical ? parent.height + Theme.spacingXS : root.slotSize
            radius: group.vertical ? Theme.cornerRadius : Theme.fullRadius(width, height)
            color: groupArea.containsMouse ? Theme.surfaceTextHover : "transparent"
            visible: !group.isClock && !group.isTray && (group.vertical || !group.usesBattery)
        }

        Grid {
            id: content

            anchors.centerIn: parent
            columns: group.vertical ? 1 : Math.max(1, content.visibleChildren.length)
            spacing: group.vertical ? 0 : Theme.spacingXXS
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            Loader {
                active: group.isClock
                visible: active
                sourceComponent: IslandClock {}
            }

            Loader {
                id: pagerLoader

                active: group.isWorkspaces
                visible: active
                sourceComponent: WorkspacePager {
                    model: workspaces
                    vertical: group.vertical
                    dotSize: Math.round(root.iconSize / 2)
                }
            }

            AudioVisualization {
                width: root.iconSize + Theme.spacingXS
                height: width
                maxBarHeight: Math.max(3, height - 2)
                idleIconName: "graphic_eq"
                visible: group.isMedia && root.controller.mediaAvailable
            }

            DIcon {
                visible: group.isMedia && !root.controller.mediaAvailable
                name: "search"
                size: root.iconSize
                color: Theme.surfaceTextMedium
            }

            DIcon {
                visible: group.isWeather
                name: WeatherService.getWeatherIcon(WeatherService.weather.wCode)
                size: root.statusIconSize
                color: Theme.surfaceTextSecondary
            }

            StyledText {
                visible: group.isWeather
                text: WeatherService.currentTempText()
                color: Theme.surfaceTextSecondary
                font.pixelSize: root.textSize
            }

            DIcon {
                visible: group.isNotifications
                name: "notifications"
                size: root.statusIconSize
                color: Theme.secondary
            }

            StyledText {
                visible: group.isNotifications
                text: root.controller.unreadNotificationCount
                color: Theme.surfaceTextSecondary
                font.pixelSize: root.textSize
            }

            DIcon {
                visible: group.isSystemLevel && (group.vertical || group.levelDisplay !== "percentage")
                name: group.isVolume ? AudioService.sinkVolumeIconName : BrightnessService.brightnessIconName(root.brightnessDevice, BrightnessService.brightnessLevel)
                size: root.statusIconSize
                color: Theme.surfaceTextSecondary
            }

            NumericText {
                visible: group.isSystemLevel && group.levelDisplay !== "icon"
                text: group.vertical ? group.levelPercent : group.levelPercent + "%"
                reserveText: group.vertical ? group.levelReserve : group.levelReserve + "%"
                color: Theme.surfaceTextSecondary
                font.pixelSize: root.textSize
            }

            BatteryMeter {
                visible: group.usesBattery
                vertical: group.vertical
                thickness: root.statusIconSize
                fontSize: root.textSize
                hovered: groupArea.containsMouse
                meterStyle: root.controller.batteryStyle
                levelColors: (root.controller.barConfig?.batteryColorMode ?? "theme") === "level"
            }

            Grid {
                visible: group.usesConnectivity
                columns: group.vertical ? 1 : 2
                spacing: Theme.spacingXXS

                ConnectivityIcon {
                    type: "wifi"
                }

                ConnectivityIcon {
                    type: "bluetooth"
                }
            }

            Grid {
                visible: group.isPrivacy
                columns: group.vertical ? 1 : 3
                spacing: Theme.spacingXXS

                PrivacyIcon {
                    // Same muted check as the bar's PrivacyIndicator
                    name: {
                        const sourceAudio = AudioService.source?.audio;
                        const muted = !sourceAudio || sourceAudio.muted || sourceAudio.volume === 0.0;
                        return muted ? "mic_off" : "mic";
                    }
                    active: PrivacyService.microphoneActive
                }

                PrivacyIcon {
                    name: "camera_video"
                    active: PrivacyService.cameraActive
                }

                PrivacyIcon {
                    name: "screen_share"
                    active: PrivacyService.screensharingActive
                }
            }

            DIcon {
                visible: group.isStatus && !group.usesBattery && !group.usesConnectivity
                name: "tune"
                size: root.iconSize
                color: Theme.surfaceText
            }

            Repeater {
                model: group.isTray ? root.visibleTrayItems : []

                Item {
                    id: trayItemRoot

                    required property var modelData
                    required property int index
                    readonly property var trayItem: modelData
                    property bool hovered: false

                    readonly property real itemStep: (group.vertical ? height : width) + content.spacing
                    property real shiftOffset: TrayMenuManager.dragShiftOffset(index, root.trayDraggedIndex, root.trayDropTargetIndex, itemStep)

                    width: group.vertical ? root.slotSize : (root.iconSize + Theme.spacingXS)
                    height: group.vertical ? (root.iconSize + Theme.spacingXS) : root.slotSize
                    z: dragHandler.dragging ? 100 : 0

                    transform: Translate {
                        x: !group.vertical ? trayItemRoot.shiftOffset : 0
                        y: group.vertical ? trayItemRoot.shiftOffset : 0
                        Behavior on x {
                            enabled: !root.suppressTrayShiftAnimation && !group.vertical
                            NumberAnimation {
                                duration: Theme.shortDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on y {
                            enabled: !root.suppressTrayShiftAnimation && group.vertical
                            NumberAnimation {
                                duration: Theme.shortDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Item {
                        id: visualContent
                        anchors.fill: parent

                        transform: Translate {
                            x: dragHandler.dragging && !group.vertical ? dragHandler.dragAxisOffset : 0
                            y: dragHandler.dragging && group.vertical ? dragHandler.dragAxisOffset : 0
                        }

                        Rectangle {
                            id: trayHighlightBg
                            anchors.fill: parent
                            radius: Theme.fullRadius(width, height)
                            color: trayMouseArea.pressed
                                ? Theme.withAlpha(Theme.surfaceText, Theme.stateLayerPressed)
                                : (trayItemRoot.hovered ? Theme.surfaceTextHover : "transparent")
                            border.width: dragHandler.dragging ? Theme.outlineWidthFocused : 0
                            border.color: Theme.primary
                            opacity: dragHandler.dragging ? 0.8 : 1.0
                        }

                        TrayItemIcon {
                            anchors.centerIn: parent
                            trayItem: trayItemRoot.trayItem
                            source: root.trayIconSourceFor(trayItemRoot.trayItem)
                            iconSize: root.statusIconSize
                            fallbackTextColor: Theme.surfaceTextSecondary
                        }
                    }

                    Item {
                        id: dragHandler
                        anchors.fill: parent
                        property bool dragInitiated: false
                        property bool dragging: false
                        property bool wasDragging: false
                        property point dragStartPos: Qt.point(0, 0)
                        property real dragAxisOffset: 0
                    }

                    MouseArea {
                        id: trayMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: dragHandler.dragging ? Qt.DragMoveCursor : Qt.PointingHandCursor

                        onContainsMouseChanged: {
                            trayItemRoot.hovered = containsMouse;
                            if (containsMouse) {
                                root.controller.slotHoverEntered();
                            } else {
                                if (!dragHandler.dragging)
                                    root.controller.slotHoverExited();
                            }
                        }

                        Component.onDestruction: {
                            dragHandler.dragging = false;
                            dragHandler.dragInitiated = false;
                            if (trayItemRoot.hovered) {
                                trayItemRoot.hovered = false;
                                root.controller.slotHoverExited();
                            }
                        }

                        onPressed: mouse => {
                            dragHandler.wasDragging = false;
                            if (mouse.button === Qt.LeftButton) {
                                dragHandler.dragInitiated = true;
                                dragHandler.dragStartPos = Qt.point(mouse.x, mouse.y);
                                root.controller.hoverOpenTimer.stop();
                                root.controller.hoverHeld = true;
                            }
                        }

                        onReleased: mouse => {
                            dragHandler.dragInitiated = false;
                            const wasDragging = dragHandler.dragging;
                            dragHandler.dragging = false;
                            dragHandler.dragAxisOffset = 0;
                            if (wasDragging) {
                                dragHandler.wasDragging = true;
                                root.finishTrayDrag();
                                if (!trayMouseArea.containsMouse)
                                    root.controller.slotHoverExited();
                            }
                            root.controller.hoverOpenTimer.stop();
                            Qt.callLater(() => {
                                root.controller.hoverOpenTimer.stop();
                                if (!trayMouseArea.containsMouse)
                                    root.controller.hoverHeld = false;
                            });
                        }

                        onPositionChanged: mouse => {
                            if (!dragHandler.dragInitiated || (mouse.buttons & Qt.LeftButton) === 0)
                                return;

                            root.controller.hoverOpenTimer.stop();
                            root.controller.hoverHeld = true;

                            const dist = Math.hypot(mouse.x - dragHandler.dragStartPos.x, mouse.y - dragHandler.dragStartPos.y);
                            if (!dragHandler.dragging && dist > 5) {
                                dragHandler.dragging = true;
                                root.beginTrayDrag(trayItemRoot.index);
                            }
                            if (!dragHandler.dragging)
                                return;

                            const axisDelta = group.vertical ? (mouse.y - dragHandler.dragStartPos.y) : (mouse.x - dragHandler.dragStartPos.x);
                            dragHandler.dragAxisOffset = axisDelta;
                            root.updateTrayDrag(axisDelta, trayItemRoot.index, trayItemRoot.itemStep);
                        }

                        onClicked: mouse => {
                            if (dragHandler.wasDragging) {
                                dragHandler.wasDragging = false;
                                return;
                            }
                            if (!trayItemRoot.trayItem)
                                return;
                            const screen = root.controller.screen;
                            const screenX = screen?.x || 0;
                            const screenY = screen?.y || 0;
                            const edge = root.controller.edge;
                            let targetX = 0;
                            let targetY = 0;
                            if (edge === "bottom" || edge === "top") {
                                targetX = root.screenPosAt(trayMouseArea, trayItemRoot.width / 2, 0).x;
                                targetY = root.islandEdgeCoord();
                            } else {
                                targetX = root.islandEdgeCoord();
                                targetY = root.screenPosAt(trayMouseArea, 0, trayItemRoot.height / 2).y;
                            }
                            if (mouse.button === Qt.RightButton) {
                                if (trayItemRoot.trayItem.hasMenu && root.trayContextMenu) {
                                    root.trayContextMenu.openFor(trayItemRoot.trayItem, targetX, targetY, screen, edge);
                                    return;
                                }
                                const mousePt = root.screenPosAt(trayMouseArea, mouse.x, mouse.y);
                                TrayMenuManager.callContextMenuFallback(trayItemRoot.trayItem.id, screenX + mousePt.x, screenY + mousePt.y);
                                return;
                            }
                            if (!trayItemRoot.trayItem.onlyMenu) {
                                trayItemRoot.trayItem.activate();
                                return;
                            }
                            if (trayItemRoot.trayItem.hasMenu && root.trayContextMenu) {
                                root.trayContextMenu.openFor(trayItemRoot.trayItem, targetX, targetY, screen, edge);
                            }
                        }
                    }
                }
            }

            Item {
                id: caretRoot
                visible: group.isTray && root.hiddenTrayItems.length > 0
                width: group.vertical ? root.slotSize : (root.iconSize + Theme.spacingXS)
                height: group.vertical ? (root.iconSize + Theme.spacingXS) : root.slotSize
                property bool hovered: false

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.fullRadius(width, height)
                    color: caretArea.pressed
                        ? Theme.withAlpha(Theme.surfaceText, Theme.stateLayerPressed)
                        : (caretRoot.hovered ? Theme.surfaceTextHover : "transparent")
                }

                DIcon {
                    anchors.centerIn: parent
                    name: {
                        const edge = root.controller.edge;
                        const open = root.trayOverflowMenu ? root.trayOverflowMenu.openState : false;
                        switch (edge) {
                        case "left":
                            return open ? "keyboard_arrow_left" : "keyboard_arrow_right";
                        case "right":
                            return open ? "keyboard_arrow_right" : "keyboard_arrow_left";
                        case "bottom":
                            return open ? "keyboard_arrow_down" : "keyboard_arrow_up";
                        case "top":
                        default:
                            return open ? "keyboard_arrow_up" : "keyboard_arrow_down";
                        }
                    }
                    size: root.statusIconSize
                    color: Theme.surfaceText
                }

                MouseArea {
                    id: caretArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onContainsMouseChanged: {
                        caretRoot.hovered = containsMouse;
                        if (containsMouse) {
                            root.controller.slotHoverEntered();
                        } else {
                            root.controller.slotHoverExited();
                        }
                    }

                    Component.onDestruction: {
                        if (caretRoot.hovered) {
                            caretRoot.hovered = false;
                            root.controller.slotHoverExited();
                        }
                    }

                    onClicked: {
                        if (!root.trayOverflowMenu)
                            return;
                        if (root.trayOverflowMenu.openState) {
                            root.trayOverflowMenu.hide();
                            return;
                        }
                        const screen = root.controller.screen;
                        const edge = root.controller.edge;
                        let triggerX = 0;
                        let triggerY = 0;
                        if (edge === "bottom" || edge === "top") {
                            triggerX = root.screenPosAt(caretArea, caretRoot.width / 2, 0).x;
                            triggerY = root.islandEdgeCoord();
                        } else {
                            triggerX = root.islandEdgeCoord();
                            triggerY = root.screenPosAt(caretArea, 0, caretRoot.height / 2).y;
                        }
                        root.trayOverflowMenu.openAt(triggerX, triggerY, screen, edge);
                    }
                }
            }
        }
    }

    readonly property var trayContextMenu: trayMenusLoader.item?.contextMenu ?? null
    readonly property var trayOverflowMenu: trayMenusLoader.item?.overflowMenu ?? null

    Loader {
        id: trayMenusLoader
        active: root.traySlotEnabled
        sourceComponent: Component {
            Item {
                id: trayMenusHost
                readonly property alias contextMenu: ctxMenu
                readonly property alias overflowMenu: ovMenu

                TrayContextMenu {
                    id: ctxMenu
                    bar: root
                }

                TrayOverflowMenu {
                    id: ovMenu
                    hiddenItems: root.hiddenTrayItems
                    contextMenu: ctxMenu
                }
            }
        }
    }

    Row {
        id: compactRow

        anchors.centerIn: parent
        visible: !root.isVertical
        onImplicitWidthChanged: root.pushMeasuredLength()
        height: root.slotSize
        spacing: root.groupSpacing

        Repeater {
            model: root.isVertical ? [] : root.groupIds

            HomeGroup {
                required property var modelData
                required property int index
                groupId: String(modelData)
                slotIndex: index
            }
        }
    }

    Column {
        id: compactColumn

        anchors.centerIn: parent
        visible: root.isVertical
        onImplicitHeightChanged: root.pushMeasuredLength()
        width: root.width
        spacing: root.groupSpacing

        Repeater {
            model: root.isVertical ? root.groupIds : []

            HomeGroup {
                required property var modelData
                required property int index
                groupId: String(modelData)
                slotIndex: index
            }
        }
    }
}
