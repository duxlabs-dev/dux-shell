import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 120
    minHeight: 120

    property bool showSeconds: pluginData.showSeconds ?? true
    property bool showDate: pluginData.showDate ?? true
    property string clockStyle: pluginData.clockStyle ?? "analog"
    property real backgroundOpacity: (pluginData.backgroundOpacity ?? 50) / 100

    SystemClock {
        id: systemClock
        precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.hostSurface
        opacity: root.backgroundOpacity
    }

    Loader {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        sourceComponent: root.clockStyle === "digital" ? digitalClock : analogClock
    }

    Component {
        id: analogClock

        Item {
            id: analogClockRoot

            property real clockSize: Math.min(width, height) - (root.showDate ? 30 : 0)

            Item {
                id: clockFace
                width: analogClockRoot.clockSize
                height: analogClockRoot.clockSize
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Theme.spacingS

                Repeater {
                    model: 12

                    Rectangle {
                        required property int index
                        property real markAngle: index * 30
                        property real markRadius: clockFace.width / 2 - 8

                        x: clockFace.width / 2 + markRadius * Math.sin(markAngle * Math.PI / 180) - width / 2
                        y: clockFace.height / 2 - markRadius * Math.cos(markAngle * Math.PI / 180) - height / 2
                        width: index % 3 === 0 ? 8 : 4
                        height: width
                        radius: width / 2
                        color: index % 3 === 0 ? Theme.primary : Theme.outlineVariant
                    }
                }

                Rectangle {
                    id: hourHand
                    property int hours: systemClock.date?.getHours() % 12 ?? 0
                    property int minutes: systemClock.date?.getMinutes() ?? 0

                    x: clockFace.width / 2 - width / 2
                    y: clockFace.height / 2 - height + 4
                    width: 6
                    height: clockFace.height * 0.25
                    radius: 3
                    color: Theme.primary
                    antialiasing: true
                    transformOrigin: Item.Bottom
                    rotation: (hours + minutes / 60) * 30
                }

                Rectangle {
                    id: minuteHand
                    property int minutes: systemClock.date?.getMinutes() ?? 0
                    property int seconds: systemClock.date?.getSeconds() ?? 0

                    x: clockFace.width / 2 - width / 2
                    y: clockFace.height / 2 - height + 4
                    width: 4
                    height: clockFace.height * 0.35
                    radius: 2
                    color: Theme.onSurface
                    antialiasing: true
                    transformOrigin: Item.Bottom
                    rotation: (minutes + seconds / 60) * 6
                }

                Rectangle {
                    id: secondHand
                    visible: root.showSeconds
                    property int seconds: systemClock.date?.getSeconds() ?? 0

                    x: clockFace.width / 2 - width / 2
                    y: clockFace.height / 2 - height + 4
                    width: 2
                    height: clockFace.height * 0.4
                    radius: 1
                    color: Theme.error
                    antialiasing: true
                    transformOrigin: Item.Bottom
                    rotation: seconds * 6
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    radius: 5
                    color: Theme.primary
                }
            }

            Text {
                visible: root.showDate
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.spacingXS
                text: systemClock.date?.toLocaleDateString(I18n.locale(), "ddd, MMM d") ?? ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }
        }
    }

    Component {
        id: digitalClock

        Item {
            id: digitalRoot

            property real timeFontSize: Math.min(width * 0.16, height * (root.showDate ? 0.4 : 0.5))
            property real dateFontSize: Math.max(Theme.fontSizeSmall, timeFontSize * 0.35)

            Text {
                id: timeText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: root.showDate ? -digitalRoot.dateFontSize * 0.8 : 0
                text: systemClock.date?.toLocaleTimeString(Qt.locale(), root.showSeconds ? "hh:mm:ss" : "hh:mm") ?? ""
                font.pixelSize: digitalRoot.timeFontSize
                font.weight: Theme.fontWeightMedium
                font.family: "monospace"
                color: Theme.primary
            }

            Text {
                id: dateText
                visible: root.showDate
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: timeText.bottom
                anchors.topMargin: Theme.spacingXS
                text: systemClock.date?.toLocaleDateString(I18n.locale(), "ddd, MMM d") ?? ""
                font.pixelSize: digitalRoot.dateFontSize
                color: Theme.surfaceText
            }
        }
    }
}
