pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets

BasePill {
    id: root

    property bool isActive: false
    property var popoutTarget: null
    property var widgetData: null
    property string screenName: ""
    property string screenModel: ""
    property bool showNetworkIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showNetworkIcon")
    property bool showBluetoothIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showBluetoothIcon")
    property bool showAudioIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showAudioIcon")
    property bool showAudioPercent: SettingsData.widgetOption("controlCenterButton", widgetData, "showAudioPercent")
    property bool showVpnIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showVpnIcon")
    property bool showBrightnessIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showBrightnessIcon")
    property bool showBrightnessPercent: SettingsData.widgetOption("controlCenterButton", widgetData, "showBrightnessPercent")
    property bool showMicIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showMicIcon")
    property bool showMicPercent: SettingsData.widgetOption("controlCenterButton", widgetData, "showMicPercent")
    property bool showBatteryIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showBatteryIcon")
    property bool showPrinterIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showPrinterIcon")
    property bool showScreenSharingIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showScreenSharingIcon")
    property bool showIdleInhibitorIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showIdleInhibitorIcon")
    property bool showDoNotDisturbIcon: SettingsData.widgetOption("controlCenterButton", widgetData, "showDoNotDisturbIcon")
    property real touchpadThreshold: 100
    property real micAccumulator: 0
    property real volumeAccumulator: 0
    property real brightnessAccumulator: 0
    readonly property real vIconSize: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
    property var _hRow: null
    property var _vCol: null
    property var _hAudio: null
    property var _hBrightness: null
    property var _hMic: null
    property var _vAudio: null
    property var _vBrightness: null
    property var _vMic: null
    property var _interactionDelegates: []
    readonly property var defaultControlCenterGroupOrder: ["network", "vpn", "bluetooth", "audio", "microphone", "brightness", "battery", "printer", "screenSharing", "idleInhibitor", "doNotDisturb"]
    readonly property var effectiveControlCenterGroupOrder: getEffectiveControlCenterGroupOrder()
    readonly property var controlCenterRenderModel: getControlCenterRenderModel()

    onIsVerticalOrientationChanged: root.clearInteractionRefs()

    onWheel: function (wheelEvent) {
        const delta = wheelEvent.angleDelta.y;
        if (delta === 0)
            return;

        root.refreshInteractionRefs();

        const rootX = wheelEvent.x - root.leftMargin;
        const rootY = wheelEvent.y - root.topMargin;

        if (root.isVerticalOrientation && _vCol) {
            const pos = root.mapToItem(_vCol, rootX, rootY);
            if (_vBrightness?.visible && pos.y >= _vBrightness.y && pos.y < _vBrightness.y + _vBrightness.height) {
                root.handleBrightnessWheel(delta);
            } else if (_vMic?.visible && pos.y >= _vMic.y && pos.y < _vMic.y + _vMic.height) {
                root.handleMicWheel(delta);
            } else {
                root.handleVolumeWheel(delta);
            }
        } else if (_hRow) {
            const pos = root.mapToItem(_hRow, rootX, rootY);
            if (_hBrightness?.visible && pos.x >= _hBrightness.x && pos.x < _hBrightness.x + _hBrightness.width) {
                root.handleBrightnessWheel(delta);
            } else if (_hMic?.visible && pos.x >= _hMic.x && pos.x < _hMic.x + _hMic.width) {
                root.handleMicWheel(delta);
            } else {
                root.handleVolumeWheel(delta);
            }
        } else {
            root.handleVolumeWheel(delta);
        }
        wheelEvent.accepted = true;
    }

    onRightClicked: function (rootX, rootY) {
        root.refreshInteractionRefs();

        if (root.isVerticalOrientation && _vCol) {
            const pos = root.mapToItem(_vCol, rootX, rootY);
            if (_vAudio?.visible && pos.y >= _vAudio.y && pos.y < _vAudio.y + _vAudio.height) {
                AudioService.toggleMute();
                return;
            }
            if (_vMic?.visible && pos.y >= _vMic.y && pos.y < _vMic.y + _vMic.height) {
                AudioService.toggleMicMute();
                return;
            }
        } else if (_hRow) {
            const pos = root.mapToItem(_hRow, rootX, rootY);
            if (_hAudio?.visible && pos.x >= _hAudio.x && pos.x < _hAudio.x + _hAudio.width) {
                AudioService.toggleMute();
                return;
            }
            if (_hMic?.visible && pos.x >= _hMic.x && pos.x < _hMic.x + _hMic.width) {
                AudioService.toggleMicMute();
                return;
            }
        }
    }

    Loader {
        active: root.showPrinterIcon
        sourceComponent: Component {
            Ref {
                service: CupsService
            }
        }
    }

    function getNetworkIconName() {
        if (NetworkService.wifiToggling)
            return "sync";
        switch (NetworkService.networkStatus) {
        case "ethernet":
            return "lan";
        case "cellular":
            return "network_cell";
        case "vpn":
            return NetworkService.ethernetConnected ? "lan" : (NetworkService.cellularConnected ? "network_cell" : NetworkService.wifiSignalIcon);
        default:
            return NetworkService.wifiSignalIcon;
        }
    }

    function getNetworkIconColor() {
        if (NetworkService.wifiToggling)
            return Theme.primary;
        if (NetworkService.isConnecting && !NetworkService.ethernetConnected)
            return Theme.primary;
        return NetworkService.networkStatus !== "disconnected" ? Theme.primary : Theme.surfaceText;
    }

    function getIconBlinking(id) {
        if (id === "network")
            return NetworkService.isWifiConnecting;
        if (id === "bluetooth")
            return BluetoothService.connecting;
        return false;
    }

    function getMicIconName() {
        if (!AudioService.source?.audio)
            return "mic";
        if (AudioService.source.audio.muted || AudioService.source.audio.volume === 0)
            return "mic_off";
        return "mic";
    }

    function getMicIconColor() {
        if (!AudioService.source?.audio)
            return Theme.surfaceText;
        if (AudioService.source.audio.muted || AudioService.source.audio.volume === 0)
            return Theme.surfaceText;
        return Theme.widgetIconColor;
    }

    function getAudioIconColor() {
        if (AudioService.sinkSilent)
            return Theme.widgetInactiveIconColor;
        return Theme.widgetIconColor;
    }

    function getBrightnessIconName() {
        const deviceName = getEffectiveBrightnessDevice();
        return BrightnessService.brightnessIconName(BrightnessService.getCurrentDeviceInfoByName(deviceName), BrightnessService.getDeviceBrightness(deviceName));
    }

    function getScreenPinKey() {
        if (!root.screenName)
            return "";
        const screen = Quickshell.screens.find(s => s.name === root.screenName);
        if (screen) {
            return SettingsData.getScreenDisplayName(screen);
        }
        if (SettingsData.displayNameMode === "model" && root.screenModel && root.screenModel.length > 0) {
            return root.screenModel;
        }
        return root.screenName;
    }

    function getBrightnessTargets() {
        const pinned = BrightnessService.pinnedDevices(getScreenPinKey());
        return pinned.length > 0 ? pinned : [BrightnessService.getDefaultDevice()];
    }

    function getEffectiveBrightnessDevice() {
        return getBrightnessTargets()[0];
    }

    function handleVolumeWheel(delta) {
        if (!AudioService.sink?.audio)
            return;

        var step = 5;
        const isMouseWheel = Math.abs(delta) >= 120 && (Math.abs(delta) % 120) === 0;
        if (!isMouseWheel) {
            step = 1;
            volumeAccumulator += delta;
            if (Math.abs(volumeAccumulator) < touchpadThreshold)
                return;

            delta = volumeAccumulator;
            volumeAccumulator = 0;
        }

        const maxVol = AudioService.sinkMaxVolume;
        const currentVolume = AudioService.sink.audio.volume * 100;
        const newVolume = delta > 0 ? Math.min(maxVol, currentVolume + step) : Math.max(0, currentVolume - step);
        AudioService.sink.audio.muted = false;
        AudioService.sink.audio.volume = newVolume / 100;
        AudioService.playVolumeChangeSoundIfEnabled();
    }

    function handleMicWheel(delta) {
        if (!AudioService.source?.audio)
            return;

        var step = 5;
        const isMouseWheel = Math.abs(delta) >= 120 && (Math.abs(delta) % 120) === 0;
        if (!isMouseWheel) {
            step = 1;
            micAccumulator += delta;
            if (Math.abs(micAccumulator) < touchpadThreshold)
                return;

            delta = micAccumulator;
            micAccumulator = 0;
        }

        const currentVolume = AudioService.source.audio.volume * 100;
        const newVolume = delta > 0 ? Math.min(100, currentVolume + step) : Math.max(0, currentVolume - step);
        AudioService.source.audio.muted = false;
        AudioService.source.audio.volume = newVolume / 100;
        AudioService.micVolumeChanged();
    }

    function handleBrightnessWheel(delta) {
        const deviceName = getEffectiveBrightnessDevice();
        if (!deviceName) {
            return;
        }

        var step = 5;
        const isMouseWheel = Math.abs(delta) >= 120 && (Math.abs(delta) % 120) === 0;
        if (!isMouseWheel) {
            step = 1;
            brightnessAccumulator += delta;
            if (Math.abs(brightnessAccumulator) < touchpadThreshold)
                return;

            delta = brightnessAccumulator;
            brightnessAccumulator = 0;
        }

        const currentBrightness = BrightnessService.getDeviceBrightness(deviceName);
        const newBrightness = delta > 0 ? Math.min(100, currentBrightness + step) : Math.max(1, currentBrightness - step);
        BrightnessService.setGroupBrightness(newBrightness, getBrightnessTargets());
    }

    function getBrightness() {
        const deviceName = getEffectiveBrightnessDevice();
        if (!deviceName) {
            return;
        }
        return BrightnessService.getDeviceBrightness(deviceName) / 100;
    }

    function getBatteryIconColor() {
        if (!BatteryService.batteryAvailable)
            return Theme.widgetIconColor;
        if (BatteryService.isLowBattery && !BatteryService.isCharging)
            return Theme.error;
        if (BatteryService.isCharging || BatteryService.isPluggedIn)
            return Theme.primary;
        return Theme.widgetIconColor;
    }

    function hasPrintJobs() {
        return CupsService.getTotalJobsNum() > 0;
    }

    function getControlCenterIconSize() {
        return Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale);
    }

    function getEffectiveControlCenterGroupOrder() {
        const knownIds = root.defaultControlCenterGroupOrder;
        const savedOrder = root.widgetData?.controlCenterGroupOrder;
        const result = [];
        const seen = {};

        if (savedOrder && typeof savedOrder.length === "number") {
            for (let i = 0; i < savedOrder.length; ++i) {
                const groupId = savedOrder[i];
                if (knownIds.indexOf(groupId) === -1 || seen[groupId])
                    continue;

                seen[groupId] = true;
                result.push(groupId);
            }
        }

        for (let i = 0; i < knownIds.length; ++i) {
            const groupId = knownIds[i];
            if (seen[groupId])
                continue;

            seen[groupId] = true;
            result.push(groupId);
        }

        return result;
    }

    function isGroupVisible(groupId) {
        switch (groupId) {
        case "screenSharing":
            return root.showScreenSharingIcon && NiriService.hasCasts;
        case "network":
            return root.showNetworkIcon && NetworkService.networkAvailable;
        case "vpn":
            return root.showVpnIcon && NetworkService.vpnAvailable && NetworkService.vpnConnected;
        case "bluetooth":
            return root.showBluetoothIcon && BluetoothService.available && BluetoothService.enabled;
        case "audio":
            return root.showAudioIcon;
        case "microphone":
            return root.showMicIcon;
        case "brightness":
            return root.showBrightnessIcon && BrightnessService.brightnessAvailable && root.getEffectiveBrightnessDevice().length > 0;
        case "battery":
            return root.showBatteryIcon && BatteryService.batteryAvailable;
        case "printer":
            return root.showPrinterIcon && CupsService.cupsAvailable && root.hasPrintJobs();
        case "idleInhibitor":
            return root.showIdleInhibitorIcon && SessionService.idleInhibited;
        case "doNotDisturb":
            return root.showDoNotDisturbIcon && SessionData.doNotDisturb;
        default:
            return false;
        }
    }

    function isCompositeGroup(groupId) {
        return groupId === "audio" || groupId === "microphone" || groupId === "brightness";
    }

    function getControlCenterRenderModel() {
        return root.effectiveControlCenterGroupOrder.map(groupId => ({
                    "id": groupId,
                    "visible": root.isGroupVisible(groupId),
                    "composite": root.isCompositeGroup(groupId)
                }));
    }

    function clearInteractionRefs() {
        root._hAudio = null;
        root._hBrightness = null;
        root._hMic = null;
        root._vAudio = null;
        root._vBrightness = null;
        root._vMic = null;
    }

    function registerInteractionDelegate(isVertical, item) {
        if (!item)
            return;

        for (let i = 0; i < root._interactionDelegates.length; ++i) {
            const entry = root._interactionDelegates[i];
            if (entry && entry.item === item) {
                entry.isVertical = isVertical;
                return;
            }
        }

        root._interactionDelegates = root._interactionDelegates.concat([
            {
                "isVertical": isVertical,
                "item": item
            }
        ]);
    }

    function unregisterInteractionDelegate(item) {
        if (!item)
            return;

        root._interactionDelegates = root._interactionDelegates.filter(entry => entry && entry.item !== item);
    }

    function refreshInteractionRefs() {
        root.clearInteractionRefs();

        for (let i = 0; i < root._interactionDelegates.length; ++i) {
            const entry = root._interactionDelegates[i];
            const item = entry?.item;
            if (!item || !item.visible)
                continue;

            const groupId = item.interactionGroupId;
            if (entry.isVertical) {
                if (groupId === "audio")
                    root._vAudio = item;
                else if (groupId === "microphone")
                    root._vMic = item;
                else if (groupId === "brightness")
                    root._vBrightness = item;
            } else {
                if (groupId === "audio")
                    root._hAudio = item;
                else if (groupId === "microphone")
                    root._hMic = item;
                else if (groupId === "brightness")
                    root._hBrightness = item;
            }
        }
    }

    function hasNoVisibleIcons() {
        return !root.controlCenterRenderModel.some(entry => entry.visible);
    }

    content: Component {
        Item {
            implicitWidth: root.isVerticalOrientation ? root.contentThickness : controlIndicators.implicitWidth
            implicitHeight: root.isVerticalOrientation ? controlColumn.implicitHeight : root.contentThickness

            Component.onCompleted: {
                root._hRow = controlIndicators;
                root._vCol = controlColumn;
                root.clearInteractionRefs();
            }

            Column {
                id: controlColumn
                visible: root.isVerticalOrientation
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingXS

                Repeater {
                    model: root.controlCenterRenderModel
                    Item {
                        id: verticalGroupItem
                        required property var modelData
                        required property int index
                        property string interactionGroupId: modelData.id

                        width: parent.width
                        height: {
                            switch (modelData.id) {
                            case "audio":
                                return root.vIconSize + (audioPercentV.visible ? audioPercentV.implicitHeight + 2 : 0);
                            case "microphone":
                                return root.vIconSize + (micPercentV.visible ? micPercentV.implicitHeight + 2 : 0);
                            case "brightness":
                                return root.vIconSize + (brightnessPercentV.visible ? brightnessPercentV.implicitHeight + 2 : 0);
                            default:
                                return root.vIconSize;
                            }
                        }
                        visible: modelData.visible

                        Component.onCompleted: {
                            root.registerInteractionDelegate(true, verticalGroupItem);
                            root.refreshInteractionRefs();
                        }
                        Component.onDestruction: {
                            if (root) {
                                root.unregisterInteractionDelegate(verticalGroupItem);
                                root.refreshInteractionRefs();
                            }
                        }
                        onVisibleChanged: root.refreshInteractionRefs()
                        onInteractionGroupIdChanged: {
                            root.refreshInteractionRefs();
                        }

                        DIcon {
                            id: vIconOnlyItem
                            anchors.centerIn: parent
                            visible: !verticalGroupItem.modelData.composite
                            name: {
                                switch (verticalGroupItem.modelData.id) {
                                case "screenSharing":
                                    return "screen_record";
                                case "network":
                                    return root.getNetworkIconName();
                                case "vpn":
                                    return "vpn_lock";
                                case "bluetooth":
                                    return BluetoothService.connected ? "bluetooth_connected" : "bluetooth";
                                case "battery":
                                    return Theme.getBatteryIcon(BatteryService.displayBatteryLevel, BatteryService.isCharging, BatteryService.batteryAvailable);
                                case "printer":
                                    return "print";
                                case "idleInhibitor":
                                    return "local_cafe";
                                case "doNotDisturb":
                                    return "do_not_disturb_on";
                                default:
                                    return "settings";
                                }
                            }
                            size: root.vIconSize
                            color: {
                                switch (verticalGroupItem.modelData.id) {
                                case "screenSharing":
                                    return NiriService.hasActiveCast ? Theme.primary : Theme.surfaceText;
                                case "network":
                                    return root.getNetworkIconColor();
                                case "vpn":
                                    return NetworkService.vpnConnected ? Theme.primary : Theme.surfaceText;
                                case "bluetooth":
                                    return (BluetoothService.connected || BluetoothService.connecting) ? Theme.primary : Theme.surfaceText;
                                case "battery":
                                    return root.getBatteryIconColor();
                                case "printer":
                                    return Theme.primary;
                                case "idleInhibitor":
                                    return Theme.primary;
                                case "doNotDisturb":
                                    return Theme.primary;
                                default:
                                    return Theme.widgetIconColor;
                                }
                            }

                            DBlink {
                                target: vIconOnlyItem
                                running: root.surfaceLive && root.getIconBlinking(verticalGroupItem.modelData.id)
                            }
                        }

                        DIcon {
                            id: audioIconV
                            visible: verticalGroupItem.modelData.id === "audio"
                            name: AudioService.sinkVolumeIconName
                            size: root.vIconSize
                            color: root.getAudioIconColor()
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                        }

                        NumericText {
                            id: audioPercentV
                            visible: verticalGroupItem.modelData.id === "audio" && root.showAudioPercent && isFinite(AudioService.sink?.audio?.volume)
                            text: Math.round((AudioService.sink?.audio?.volume ?? 0) * 100) + "%"
                            reserveText: "100%"
                            font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                            color: Theme.widgetTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: audioIconV.bottom
                            anchors.topMargin: 2
                        }

                        DIcon {
                            id: micIconV
                            visible: verticalGroupItem.modelData.id === "microphone"
                            name: root.getMicIconName()
                            size: root.vIconSize
                            color: root.getMicIconColor()
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                        }

                        NumericText {
                            id: micPercentV
                            visible: verticalGroupItem.modelData.id === "microphone" && root.showMicPercent && isFinite(AudioService.source?.audio?.volume)
                            text: Math.round((AudioService.source?.audio?.volume ?? 0) * 100) + "%"
                            reserveText: "100%"
                            font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                            color: Theme.widgetTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: micIconV.bottom
                            anchors.topMargin: 2
                        }

                        DIcon {
                            id: brightnessIconV
                            visible: verticalGroupItem.modelData.id === "brightness"
                            name: root.getBrightnessIconName()
                            size: root.vIconSize
                            color: Theme.widgetIconColor
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                        }

                        NumericText {
                            id: brightnessPercentV
                            visible: verticalGroupItem.modelData.id === "brightness" && root.showBrightnessPercent && isFinite(getBrightness())
                            text: Math.round(getBrightness() * 100) + "%"
                            reserveText: "100%"
                            font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                            color: Theme.widgetTextColor
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: brightnessIconV.bottom
                            anchors.topMargin: 2
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: root.vIconSize
                    visible: root.hasNoVisibleIcons()

                    DIcon {
                        name: "settings"
                        size: root.vIconSize
                        color: root.isActive ? Theme.primary : Theme.widgetIconColor
                        anchors.centerIn: parent
                    }
                }
            }

            Row {
                id: controlIndicators
                visible: !root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                Repeater {
                    model: root.controlCenterRenderModel

                    Item {
                        id: horizontalGroupItem
                        required property var modelData
                        required property int index
                        property string interactionGroupId: modelData.id

                        width: {
                            switch (modelData.id) {
                            case "audio":
                                return audioGroup.width;
                            case "microphone":
                                return micGroup.width;
                            case "brightness":
                                return brightnessGroup.width;
                            default:
                                return root.getControlCenterIconSize();
                            }
                        }
                        implicitWidth: width
                        height: root.contentThickness
                        visible: modelData.visible

                        Component.onCompleted: {
                            root.registerInteractionDelegate(false, horizontalGroupItem);
                            root.refreshInteractionRefs();
                        }
                        Component.onDestruction: {
                            if (root) {
                                root.unregisterInteractionDelegate(horizontalGroupItem);
                                root.refreshInteractionRefs();
                            }
                        }
                        onVisibleChanged: root.refreshInteractionRefs()
                        onInteractionGroupIdChanged: {
                            root.refreshInteractionRefs();
                        }

                        DIcon {
                            id: iconOnlyItem
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            visible: !horizontalGroupItem.modelData.composite
                            name: {
                                switch (horizontalGroupItem.modelData.id) {
                                case "screenSharing":
                                    return "screen_record";
                                case "network":
                                    return root.getNetworkIconName();
                                case "vpn":
                                    return "vpn_lock";
                                case "bluetooth":
                                    return BluetoothService.connected ? "bluetooth_connected" : "bluetooth";
                                case "battery":
                                    return Theme.getBatteryIcon(BatteryService.displayBatteryLevel, BatteryService.isCharging, BatteryService.batteryAvailable);
                                case "printer":
                                    return "print";
                                case "idleInhibitor":
                                    return "local_cafe";
                                case "doNotDisturb":
                                    return "do_not_disturb_on";
                                default:
                                    return "settings";
                                }
                            }
                            size: root.getControlCenterIconSize()
                            color: {
                                switch (horizontalGroupItem.modelData.id) {
                                case "screenSharing":
                                    return NiriService.hasActiveCast ? Theme.primary : Theme.surfaceText;
                                case "network":
                                    return root.getNetworkIconColor();
                                case "vpn":
                                    return NetworkService.vpnConnected ? Theme.primary : Theme.surfaceText;
                                case "bluetooth":
                                    return (BluetoothService.connected || BluetoothService.connecting) ? Theme.primary : Theme.surfaceText;
                                case "battery":
                                    return root.getBatteryIconColor();
                                case "printer":
                                    return Theme.primary;
                                case "idleInhibitor":
                                    return Theme.primary;
                                case "doNotDisturb":
                                    return Theme.primary;
                                default:
                                    return Theme.widgetIconColor;
                                }
                            }

                            DBlink {
                                target: iconOnlyItem
                                running: root.surfaceLive && root.getIconBlinking(horizontalGroupItem.modelData.id)
                            }
                        }

                        Rectangle {
                            id: audioGroup
                            width: audioContent.implicitWidth + 2
                            implicitWidth: width
                            height: parent.height
                            color: "transparent"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: horizontalGroupItem.modelData.id === "audio"

                            Row {
                                id: audioContent
                                anchors.left: parent.left
                                anchors.leftMargin: 1
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXXS

                                DIcon {
                                    id: audioIcon
                                    name: AudioService.sinkVolumeIconName
                                    size: root.getControlCenterIconSize()
                                    color: root.getAudioIconColor()
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                NumericText {
                                    id: audioPercent
                                    visible: root.showAudioPercent && isFinite(AudioService.sink?.audio?.volume)
                                    text: Math.round((AudioService.sink?.audio?.volume ?? 0) * 100) + "%"
                                    reserveText: "100%"
                                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                                    color: Theme.widgetTextColor
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: visible ? reservedWidth : 0
                                }
                            }
                        }

                        Rectangle {
                            id: micGroup
                            width: micContent.implicitWidth + 2
                            implicitWidth: width
                            height: parent.height
                            color: "transparent"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: horizontalGroupItem.modelData.id === "microphone"

                            Row {
                                id: micContent
                                anchors.left: parent.left
                                anchors.leftMargin: 1
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXXS

                                DIcon {
                                    id: micIcon
                                    name: root.getMicIconName()
                                    size: root.getControlCenterIconSize()
                                    color: root.getMicIconColor()
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                NumericText {
                                    id: micPercent
                                    visible: root.showMicPercent && isFinite(AudioService.source?.audio?.volume)
                                    text: Math.round((AudioService.source?.audio?.volume ?? 0) * 100) + "%"
                                    reserveText: "100%"
                                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                                    color: Theme.widgetTextColor
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: visible ? reservedWidth : 0
                                }
                            }
                        }

                        Rectangle {
                            id: brightnessGroup
                            width: brightnessContent.implicitWidth + 2
                            implicitWidth: width
                            height: parent.height
                            color: "transparent"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: horizontalGroupItem.modelData.id === "brightness"

                            Row {
                                id: brightnessContent
                                anchors.left: parent.left
                                anchors.leftMargin: 1
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXXS

                                DIcon {
                                    id: brightnessIcon
                                    name: root.getBrightnessIconName()
                                    size: root.getControlCenterIconSize()
                                    color: Theme.widgetIconColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                NumericText {
                                    id: brightnessPercent
                                    visible: root.showBrightnessPercent && isFinite(getBrightness())
                                    text: Math.round(getBrightness() * 100) + "%"
                                    reserveText: "100%"
                                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                                    color: Theme.widgetTextColor
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: visible ? reservedWidth : 0
                                }
                            }
                        }
                    }
                }

                DIcon {
                    name: "settings"
                    size: root.getControlCenterIconSize()
                    color: root.isActive ? Theme.primary : Theme.widgetIconColor
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.hasNoVisibleIcons()
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.NoButton
            }
        }
    }
}
