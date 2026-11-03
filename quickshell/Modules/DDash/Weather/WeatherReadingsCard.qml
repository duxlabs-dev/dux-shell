pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash

Rectangle {
    id: root

    property var widgetOptions: ({})
    readonly property var weather: WeatherService.weather
    readonly property var readings: {
        SettingsData.useFahrenheit;
        SettingsData.windSpeedUnit;
        return [
            {
                icon: "humidity_low",
                label: I18n.tr("Humidity", "weather metric label"),
                value: WeatherService.formatPercent(weather.humidity)
            },
            {
                icon: "air",
                label: I18n.tr("Wind", "noun, weather wind speed metric label"),
                value: WeatherService.formatSpeed(weather.wind)
            },
            {
                icon: "speed",
                label: I18n.tr("Pressure", "weather atmospheric pressure metric label"),
                value: WeatherService.formatPressure(weather.pressure)
            },
            {
                icon: "rainy",
                label: I18n.tr("Precipitation", "weather precipitation probability metric label"),
                value: WeatherService.formatPercent(weather.precipitationProbability)
            },
            {
                nerdIcon: "sunrise",
                label: I18n.tr("Sunrise", "sunrise time label, also time of day period name"),
                value: weather.rawSunrise ? WeatherService.formatTime(weather.rawSunrise) : weather.sunrise
            },
            {
                nerdIcon: "sunset",
                label: I18n.tr("Sunset", "sunset time label, also time of day period name"),
                value: weather.rawSunset ? WeatherService.formatTime(weather.rawSunset) : weather.sunset
            }
        ];
    }
    readonly property real cellHeight: Theme.fontSizeSmall * 1.4 + Theme.fontSizeMedium * 1.4 + Theme.spacingXS
    readonly property int rows: Math.max(1, Math.min(2, Math.floor((height - Theme.spacingL * 2) / cellHeight)))
    readonly property int columns: Math.ceil(readings.length / rows)

    radius: Theme.cornerRadiusXL
    color: toneColors.surfaceColor
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium
    Accessible.role: Accessible.StaticText
    Accessible.name: readings.map(reading => reading.label + " " + (reading.value ?? I18n.tr("Not available"))).join(", ")

    DTone {
        id: toneColors
        tone: root.widgetOptions.tone ?? ""
    }

    Grid {
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        columns: root.columns
        rows: root.rows
        columnSpacing: Theme.spacingS
        rowSpacing: Theme.spacingS

        Repeater {
            model: root.readings

            Column {
                id: cell

                required property var modelData

                width: (parent.width - (root.columns - 1) * parent.columnSpacing) / root.columns
                height: (parent.height - (root.rows - 1) * parent.rowSpacing) / root.rows
                spacing: Theme.spacingXS
                topPadding: Math.max(0, (height - implicitHeight) / 2)

                Row {
                    width: parent.width
                    spacing: Theme.spacingXS

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!cell.modelData.icon
                        name: cell.modelData.icon ?? ""
                        size: Theme.iconSizeSmall
                        color: toneColors.contentColor
                    }

                    DNFIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!cell.modelData.nerdIcon
                        name: cell.modelData.nerdIcon ?? ""
                        size: Theme.iconSizeSmall
                        color: toneColors.contentColor
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.iconSizeSmall - parent.spacing
                        text: cell.modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        color: toneColors.contentColor
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    width: parent.width
                    text: root.weather.available && cell.modelData.value != null ? cell.modelData.value : "--"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: toneColors.contentColor
                    elide: Text.ElideRight
                }
            }
        }
    }
}
