import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash

Rectangle {
    id: root

    property var date: null
    property bool daily: true
    property var forecastData: null
    property bool dense: false

    property bool isCurrent: {
        if (!date)
            return false;
        if (daily)
            return WeatherService.calendarDayDifference(new Date(), date) === 0;
        return WeatherService.calendarHourDifference(new Date(), date) === 0;
    }
    readonly property string dateText: {
        if (daily)
            return WeatherService.formatForecastDay(root.forecastData?.rawDate || root.forecastData?.rawSunrise || (date ? Qt.formatDate(date, "yyyy-MM-dd") : ""), 0);
        if (!root.forecastData?.rawTime)
            return root.forecastData?.time ?? "--";
        return new Date(root.forecastData.rawTime).toLocaleTimeString(I18n.locale(), SettingsData.use24HourClock ? "HH:mm" : "h:mm AP");
    }
    readonly property string tempText: {
        if (daily)
            return (WeatherService.formatTemp(root.forecastData?.tempMax) ?? "--") + " / " + (WeatherService.formatTemp(root.forecastData?.tempMin) ?? "--");
        return WeatherService.formatTemp(root.forecastData?.temp) ?? "--";
    }
    readonly property var details: {
        SettingsData.windSpeedUnit;
        SettingsData.useFahrenheit;
        if (daily)
            return [];
        return [
            {
                "icon": "thermostat",
                "text": WeatherService.formatTemp(root.forecastData?.feelsLike) ?? "--"
            },
            {
                "icon": "humidity_low",
                "text": WeatherService.formatPercent(root.forecastData?.humidity) ?? "--"
            },
            {
                "icon": "air",
                "text": WeatherService.formatSpeed(root.forecastData?.wind) ?? "--"
            },
            {
                "icon": "rainy",
                "text": (root.forecastData?.precipitationProbability ?? 0) + "%"
            }
        ];
    }
    readonly property color foreground: isCurrent ? Theme.onPrimaryContainer : Theme.surfaceText
    readonly property color muted: isCurrent ? Theme.withAlpha(Theme.onPrimaryContainer, DashMetrics.mutedAlpha) : Theme.onSurfaceVariant

    radius: Theme.cornerRadiusL
    color: isCurrent ? Theme.foregroundColor(Theme.primaryContainer, false) : DashMetrics.chipColor

    Column {
        anchors.centerIn: parent
        width: parent.width - Theme.spacingS * 2
        spacing: Theme.spacingXS

        StyledText {
            width: parent.width
            text: root.forecastData ? root.dateText : I18n.tr("Forecast Not Available")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: root.forecastData ? root.foreground : Theme.outline
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.forecastData ? WeatherService.getWeatherIcon(root.forecastData.wCode || 0, root.forecastData.isDay ?? true) : "cloud"
            size: Theme.iconSizeLarge
            color: root.isCurrent ? root.foreground : Theme.primary
            visible: root.forecastData !== null
        }

        StyledText {
            width: parent.width
            text: root.tempText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: root.foreground
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: root.forecastData !== null
        }

        Column {
            id: detailRows
            width: parent.width
            spacing: Theme.spacingXXS
            visible: !root.dense && root.details.length > 0

            Repeater {
                model: root.details

                Row {
                    required property var modelData

                    anchors.horizontalCenter: detailRows.horizontalCenter
                    spacing: Theme.spacingXS

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: parent.modelData.icon
                        size: Theme.iconSizeSmall
                        color: root.muted
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.text
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.muted
                    }
                }
            }
        }
    }
}
