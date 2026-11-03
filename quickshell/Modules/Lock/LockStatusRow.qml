import QtQuick
import QtQuick.Window
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.DCommon.Session
import "../../DCommon/Common/LayoutCodes.js" as LayoutCodes

Row {
    id: root

    property bool interactive: true
    property bool showMediaPlayer: false
    property bool showWeather: true
    property bool useFahrenheit: false

    readonly property color contentColor: Theme.lockScreenContentColor
    readonly property color dimColor: Theme.withAlpha(contentColor, Theme.pendingOpacity)
    readonly property color dividerColor: Theme.withAlpha(contentColor, Theme.stateLayerPressed)
    readonly property bool weatherVisible: showWeather && WeatherService.weather.available
    readonly property bool afterWeather: systemRow.visible || batteryRow.visible
    readonly property bool afterMedia: weatherVisible || afterWeather
    readonly property bool afterKeyboard: mediaLoader.visible || afterMedia

    readonly property bool keyboardLayoutVisible: KeyboardLayoutService.layoutCount > 1
    readonly property string keyboardLayoutLabel: KeyboardLayoutService.layoutKnown ? LayoutCodes.layoutCode(KeyboardLayoutService.currentLayout) : ""
    readonly property color batteryColor: {
        if (BatteryService.isLowBattery && !BatteryService.isCharging)
            return Theme.error;
        if (BatteryService.isCharging || BatteryService.isPluggedIn)
            return Theme.primary;
        return contentColor;
    }

    spacing: Theme.spacingL

    function cycleKeyboardLayout() {
        KeyboardLayoutService.cycle();
    }

    Component.onCompleted: KeyboardLayoutService.consumers++
    Component.onDestruction: KeyboardLayoutService.consumers--

    component Divider: Rectangle {
        width: Theme.dividerWidth
        height: Theme.iconSize
        color: root.dividerColor
        anchors.verticalCenter: parent.verticalCenter
    }

    Item {
        id: keyboardLayout
        width: keyboardLayoutRow.width
        height: keyboardLayoutRow.height
        anchors.verticalCenter: parent.verticalCenter
        visible: root.keyboardLayoutVisible

        Row {
            id: keyboardLayoutRow
            spacing: Theme.spacingXS

            DIcon {
                name: "keyboard"
                size: Theme.iconSize
                color: root.contentColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.keyboardLayoutLabel
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeight
                color: root.contentColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.interactive
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.cycleKeyboardLayout()
        }
    }

    Divider {
        visible: keyboardLayout.visible && root.afterKeyboard
    }

    Loader {
        id: mediaLoader
        active: root.showMediaPlayer
        visible: active && !!MprisController.activePlayer
        anchors.verticalCenter: parent.verticalCenter

        sourceComponent: Row {
            spacing: Theme.spacingS

            Item {
                id: visualizer
                width: Theme.iconSizeSmall
                height: Theme.iconSize
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool live: visible && (Window.window?.visible ?? false) && MprisController.activePlayer?.playbackState === MprisPlaybackState.Playing

                Loader {
                    active: visualizer.live
                    sourceComponent: Ref {
                        service: CavaService
                    }
                }

                Timer {
                    running: !CavaService.cavaAvailable && visualizer.live
                    interval: 256
                    repeat: true
                    onTriggered: CavaService.values = [Math.random() * 40 + 10, Math.random() * 60 + 20, Math.random() * 50 + 15, Math.random() * 35 + 20, Math.random() * 45 + 15, Math.random() * 55 + 25]
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingXXS

                    Repeater {
                        model: 6

                        delegate: Rectangle {
                            required property int index
                            width: Theme.outlineWidthFocused
                            height: {
                                if (!visualizer.live || CavaService.values.length <= index)
                                    return Theme.spacingXXS;
                                const rawLevel = CavaService.values[index] || 0;
                                const scaledLevel = Math.sqrt(Math.min(Math.max(rawLevel, 0), 100) / 100) * 100;
                                const maxHeight = Theme.iconSize - Theme.spacingXXS;
                                return Theme.spacingXXS + (scaledLevel / 100) * (maxHeight - Theme.spacingXXS);
                            }
                            radius: Theme.cornerRadiusXS
                            color: root.contentColor
                            anchors.verticalCenter: parent.verticalCenter

                            Behavior on height {
                                NumberAnimation {
                                    duration: LockMetrics.effectsDuration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                text: {
                    const player = MprisController.activePlayer;
                    if (!player?.trackTitle)
                        return "";
                    return player.trackArtist ? player.trackTitle + " • " + player.trackArtist : player.trackTitle;
                }
                font.pixelSize: Theme.fontSizeLarge
                color: root.contentColor
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: Math.min(implicitWidth, LockMetrics.fieldWidth)
                wrapMode: Text.NoWrap
                maximumLineCount: 1
            }

            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("Previous")
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                    radius: Theme.fullRadius(width, height)
                    anchors.verticalCenter: parent.verticalCenter
                    color: prevArea.containsMouse ? root.dividerColor : "transparent"
                    opacity: prevArea.enabled ? 1 : Theme.onSurface_38.a

                    DIcon {
                        anchors.centerIn: parent
                        name: "skip_previous"
                        size: Theme.iconSizeSmall
                        color: root.contentColor
                    }

                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        enabled: MprisController.activePlayer?.canGoPrevious ?? false
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: MprisController.previousOrRewind()
                    }
                }

                Rectangle {
                    Accessible.role: Accessible.Button
                    Accessible.name: playing ? I18n.tr("Pause") : I18n.tr("Play")
                    readonly property bool playing: MprisController.activePlayer?.playbackState === MprisPlaybackState.Playing
                    width: Theme.iconSize
                    height: Theme.iconSize
                    radius: Theme.fullRadius(width, height)
                    anchors.verticalCenter: parent.verticalCenter
                    color: playing ? root.contentColor : root.dividerColor

                    DIcon {
                        anchors.centerIn: parent
                        name: parent.playing ? "pause" : "play_arrow"
                        size: Theme.iconSizeSmall
                        color: parent.playing ? Theme.screenOffColor : root.contentColor
                    }

                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisController.activePlayer?.togglePlaying()
                    }
                }

                Rectangle {
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("Next")
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                    radius: Theme.fullRadius(width, height)
                    anchors.verticalCenter: parent.verticalCenter
                    color: nextArea.containsMouse ? root.dividerColor : "transparent"
                    opacity: nextArea.enabled ? 1 : Theme.onSurface_38.a

                    DIcon {
                        anchors.centerIn: parent
                        name: "skip_next"
                        size: Theme.iconSizeSmall
                        color: root.contentColor
                    }

                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        enabled: MprisController.activePlayer?.canGoNext ?? false
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: MprisController.next()
                    }
                }
            }
        }
    }

    Divider {
        visible: mediaLoader.visible && root.afterMedia
    }

    Row {
        id: weatherRow
        spacing: Theme.spacingXS
        visible: root.weatherVisible
        anchors.verticalCenter: parent.verticalCenter

        DIcon {
            name: WeatherService.getWeatherIcon(WeatherService.weather.wCode)
            size: Theme.iconSize
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: (root.useFahrenheit ? WeatherService.weather.tempF : WeatherService.weather.temp) + "°"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeight
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Divider {
        visible: weatherRow.visible && root.afterWeather
    }

    Row {
        id: systemRow
        spacing: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        visible: NetworkService.networkAvailable || (BluetoothService.available && BluetoothService.enabled) || (AudioService.sink && AudioService.sink.audio)

        DIcon {
            name: "screen_record"
            size: Theme.iconSizeSmall
            color: NiriService.hasActiveCast ? root.contentColor : root.dimColor
            anchors.verticalCenter: parent.verticalCenter
            visible: NiriService.hasCasts
        }

        DIcon {
            id: networkIcon
            name: {
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
            size: Theme.iconSizeSmall
            color: (NetworkService.networkStatus !== "disconnected" || NetworkService.isConnecting) ? root.contentColor : root.dimColor
            anchors.verticalCenter: parent.verticalCenter
            visible: NetworkService.networkAvailable

            DBlink {
                target: networkIcon
                running: NetworkService.isWifiConnecting
            }
        }

        DIcon {
            name: "vpn_lock"
            size: Theme.iconSizeSmall
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
            visible: NetworkService.vpnAvailable && NetworkService.vpnConnected
        }

        DIcon {
            id: bluetoothIcon
            name: "bluetooth"
            size: Theme.iconSizeSmall
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
            visible: BluetoothService.available && BluetoothService.enabled

            DBlink {
                target: bluetoothIcon
                running: BluetoothService.connecting
            }
        }

        DIcon {
            name: AudioService.sinkVolumeIconName
            size: Theme.iconSizeSmall
            color: AudioService.sinkSilent ? root.dimColor : root.contentColor
            anchors.verticalCenter: parent.verticalCenter
            visible: AudioService.sink && AudioService.sink.audio
        }
    }

    Divider {
        visible: systemRow.visible && batteryRow.visible
    }

    Row {
        id: batteryRow
        spacing: Theme.spacingXS
        visible: BatteryService.batteryAvailable
        anchors.verticalCenter: parent.verticalCenter

        DIcon {
            name: BatteryService.getBatteryIcon()
            size: Theme.iconSize
            color: root.batteryColor
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: BatteryService.displayBatteryLevelText + "%"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeight
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
