import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash
import qs.Modules.DDash.Weather
import "../Weather/WeatherVisuals.js" as Visuals

Card {
    id: root

    property bool live: Window.window?.visible ?? false
    property bool weatherRefHeld: false

    readonly property bool available: WeatherService.weather.available
    readonly property bool tall: height > width
    readonly property bool narrow: width < DashMetrics.gridRowUnit * 2
    readonly property bool compact: narrow && !tall
    readonly property bool wide: width >= DashMetrics.gridRowUnit * 3
    readonly property bool roomy: !narrow && height >= DashMetrics.gridRowUnit * 2
    readonly property bool stacked: tall || narrow || roomy
    readonly property bool heroLayout: available && roomy && wide
    readonly property bool showReadings: options.readings !== false
    readonly property bool showCity: options.city === true && available && !!WeatherService.weather.city
    readonly property string cityText: WeatherService.weather.city ?? ""
    readonly property string rowTitle: showCity && wide ? cityText + " · " + conditionText : conditionText
    readonly property string rowSubtitle: {
        if (showReadings)
            return wide ? readingsText : feelsLikeText;
        return showCity && !wide ? cityText : "";
    }
    readonly property string iconName: available ? WeatherService.getWeatherIcon(WeatherService.weather.wCode, WeatherService.weather.isDay) : "cloud_off"
    readonly property string tempText: available ? WeatherService.currentTempText(false) : I18n.tr("No Weather")
    readonly property string conditionText: available ? WeatherService.getWeatherCondition(WeatherService.weather.wCode) : ""
    readonly property string feelsLikeText: {
        if (!available)
            return "";
        const feelsLike = SettingsData.useFahrenheit ? (WeatherService.weather.feelsLikeF ?? WeatherService.weather.tempF) : (WeatherService.weather.feelsLike ?? WeatherService.weather.temp);
        return I18n.tr("Feels Like %1°", "weather feels like temperature").arg(feelsLike);
    }
    readonly property string readingsText: {
        if (!available)
            return "";
        const parts = [feelsLikeText];
        const humidity = WeatherService.formatPercent(WeatherService.weather.humidity);
        if (humidity)
            parts.push(humidity);
        const wind = WeatherService.formatSpeed(WeatherService.weather.wind);
        if (wind)
            parts.push(wind);
        return parts.join(" · ");
    }

    entryId: "weather"
    tone: options.tone ?? ""
    clickable: true
    pad: compact ? Theme.spacingS : Theme.spacingM

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

    onLiveChanged: syncWeatherRef(live)
    Component.onCompleted: syncWeatherRef(live)
    Component.onDestruction: syncWeatherRef(false)

    Column {
        anchors.fill: parent
        spacing: Theme.spacingXS
        visible: root.compact

        Row {
            width: parent.width
            height: parent.height - compactCondition.height - parent.spacing
            spacing: Theme.spacingXS

            Item {
                id: compactIcon
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.height, parent.width * DashMetrics.weatherCompactIconRatio)
                height: width

                DIcon {
                    anchors.centerIn: parent
                    name: root.iconName
                    size: parent.width
                    color: root.accentColor
                    visible: root.available || !WeatherService.weather.loading
                }

                DSpinner {
                    anchors.centerIn: parent
                    size: parent.width
                    color: root.contentColor
                    visible: !root.available && WeatherService.weather.loading
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - compactIcon.width - parent.spacing
                height: parent.height
                text: root.available ? root.tempText : ""
                font.pixelSize: Theme.fontSizeXXLarge
                minimumPixelSize: Theme.fontSizeLarge
                fontSizeMode: Text.HorizontalFit
                font.weight: Theme.fontWeightMedium
                color: root.contentColor
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        StyledText {
            id: compactCondition
            width: parent.width
            text: root.available ? (root.showCity ? root.cityText : root.conditionText) : root.tempText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: root.mutedColor
            elide: Text.ElideRight
        }
    }

    Item {
        id: stackedLayout
        anchors.fill: parent
        visible: root.stacked && !root.compact && !root.heroLayout

        DMaterialShape {
            id: stackedChip
            width: Math.min(parent.width * 0.5, parent.height * 0.42)
            height: width
            shape: Visuals.conditionShape(WeatherService.weather.wCode, WeatherService.weather.isDay)
            color: root.chipColor

            DIcon {
                anchors.centerIn: parent
                name: root.iconName
                size: parent.width * 0.55
                color: root.accentColor
                visible: root.available || !WeatherService.weather.loading
            }

            DSpinner {
                anchors.centerIn: parent
                size: parent.width * 0.55
                color: root.contentColor
                visible: !root.available && WeatherService.weather.loading
            }
        }

        StyledText {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.left: stackedChip.right
            anchors.leftMargin: Theme.spacingS
            text: root.cityText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: root.mutedColor
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            visible: root.showCity && !root.narrow
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 0

            StyledText {
                width: parent.width
                text: root.tempText
                font.pixelSize: root.available ? Math.min(Theme.fontSizeDisplay * 1.5, stackedLayout.height * 0.32) : Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                minimumPixelSize: Theme.fontSizeXLarge
                fontSizeMode: Text.HorizontalFit
                color: root.contentColor
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.conditionText
                font.pixelSize: root.narrow ? Theme.fontSizeSmall : Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: root.mutedColor
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text !== ""
            }

            StyledText {
                width: parent.width
                text: root.narrow ? root.feelsLikeText : root.readingsText
                font.pixelSize: Theme.fontSizeSmall
                color: root.mutedColor
                elide: Text.ElideRight
                visible: root.showReadings && text !== ""
            }

            StyledText {
                width: parent.width
                text: root.cityText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: root.mutedColor
                elide: Text.ElideRight
                visible: root.showCity && root.narrow
            }
        }
    }

    WeatherHero {
        anchors.fill: parent
        visible: root.heroLayout
        showCity: root.showCity
        showSunTimes: root.showReadings
        tone: root.tone
        flat: true
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingM
        visible: !root.stacked

        DMaterialShape {
            id: iconChip
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(DashMetrics.weatherChipSize, root.height - root.pad * 2)
            height: width
            shape: Visuals.conditionShape(WeatherService.weather.wCode, WeatherService.weather.isDay)
            color: root.chipColor

            DIcon {
                anchors.centerIn: parent
                name: root.iconName
                size: Theme.iconSize
                color: root.accentColor
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - iconChip.width - tempLabel.width - parent.spacing * 2
            spacing: 0

            StyledText {
                width: parent.width
                text: root.available ? root.rowTitle : root.tempText
                wrapMode: Text.NoWrap
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: root.contentColor
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.rowSubtitle
                wrapMode: Text.NoWrap
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: root.mutedColor
                elide: Text.ElideRight
                visible: text !== ""
            }
        }

        StyledText {
            id: tempLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root.available ? root.tempText : ""
            font.pixelSize: DashMetrics.weatherTempSize
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
        }
    }
}
