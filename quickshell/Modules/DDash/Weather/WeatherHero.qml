import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "WeatherVisuals.js" as Visuals

Rectangle {
    id: root

    property bool showCity: false
    property bool showSunTimes: true
    property var widgetOptions: ({})
    property string tone: widgetOptions.tone ?? "primary"
    property bool flat: false
    readonly property bool wide: width >= Theme.smallBreakpoint
    readonly property var weather: WeatherService.weather
    readonly property string cityText: [weather.city, weather.country].filter(s => !!s).join(", ")

    implicitHeight: (wide ? Math.max(details.implicitHeight, temperature.implicitHeight) : details.implicitHeight) + Theme.spacingL * 2
    radius: Theme.cornerRadiusXL
    color: flat ? "transparent" : toneColors.surfaceColor
    border.width: flat ? 0 : Theme.layerOutlineWidth
    border.color: Theme.outlineMedium

    DTone {
        id: toneColors
        tone: root.tone
        floatingWindow: Theme.isFloatingWindow(root)
    }

    Column {
        id: details
        anchors.left: parent.left
        anchors.leftMargin: root.wide ? Theme.fontSizeDisplay * 3 + Theme.spacingL * 2 : Theme.spacingL
        anchors.right: parent.right
        anchors.rightMargin: root.wide ? emblem.width + Theme.spacingL * 2 : Theme.spacingL
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        StyledText {
            id: city
            visible: root.showCity && root.cityText !== ""
            width: parent.width
            text: root.cityText
            color: toneColors.contentColor
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            elide: Text.ElideRight
        }

        Item {
            visible: !root.wide
            width: parent.width
            height: temperature.implicitHeight
        }

        StyledText {
            width: parent.width
            text: WeatherService.getWeatherCondition(root.weather.wCode)
            color: toneColors.contentColor
            font.pixelSize: Theme.fontSizeLarge
            wrapMode: Text.WordWrap
        }

        StyledText {
            width: parent.width
            text: I18n.tr("Feels Like %1°").arg(WeatherService.formatTemp(root.weather.feelsLike ?? root.weather.temp, false) ?? "--")
            color: toneColors.contentColor
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingS
            visible: root.showSunTimes

            Repeater {
                model: [
                    {
                        icon: "sunrise",
                        label: I18n.tr("Sunrise", "sunrise time label, also time of day period name"),
                        time: root.weather.rawSunrise ? WeatherService.formatTime(root.weather.rawSunrise) : root.weather.sunrise
                    },
                    {
                        icon: "sunset",
                        label: I18n.tr("Sunset", "sunset time label, also time of day period name"),
                        time: root.weather.rawSunset ? WeatherService.formatTime(root.weather.rawSunset) : root.weather.sunset
                    }
                ]

                Row {
                    id: sunTime
                    required property var modelData
                    spacing: Theme.spacingXS
                    Accessible.role: Accessible.StaticText
                    Accessible.name: modelData.label + " " + (modelData.time || "--")

                    DNFIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: sunTime.modelData.icon
                        size: Theme.iconSizeSmall
                        color: toneColors.contentColor

                        StateLayer {
                            acceptedButtons: Qt.NoButton
                            cursorShape: Qt.ArrowCursor
                            stateColor: "transparent"
                            enableRipple: false
                            tooltipText: sunTime.modelData.label
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: sunTime.modelData.time || "--"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: toneColors.contentColor
                    }
                }
            }
        }
    }

    StyledText {
        id: temperature
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingL
        y: root.wide ? (root.height - height) / 2 : details.y + (root.showCity && root.cityText !== "" ? city.height + Theme.spacingXS : 0)
        width: root.wide ? Theme.fontSizeDisplay * 3 : details.width - emblem.width - Theme.spacingS
        text: WeatherService.formatTemp(root.weather.temp) ?? "--"
        color: toneColors.contentColor
        font.pixelSize: Theme.fontSizeDisplay * 1.5
        font.weight: Theme.fontWeightMedium
        minimumPixelSize: Theme.fontSizeXXLarge
        fontSizeMode: Text.HorizontalFit
    }

    DMaterialShape {
        id: emblem
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingL
        anchors.top: parent.top
        anchors.topMargin: root.wide ? (root.height - height) / 2 : Theme.spacingL + (root.showCity && root.cityText !== "" ? Theme.fontSizeMedium + Theme.spacingXS : 0)
        width: Math.min(Theme.iconSize * 4, root.height - Theme.spacingL * 2)
        height: width
        shape: Visuals.conditionShape(root.weather.wCode, root.weather.isDay)
        color: Theme.primary

        DIcon {
            anchors.centerIn: parent
            name: WeatherService.getWeatherIcon(root.weather.wCode, root.weather.isDay)
            size: parent.width / 2
            color: Theme.onPrimary
        }
    }
}
