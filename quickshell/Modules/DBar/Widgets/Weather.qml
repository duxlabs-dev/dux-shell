import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets

BasePill {
    id: root

    visible: SettingsData.weatherEnabled

    Component.onCompleted: WeatherService.addRef()
    Component.onDestruction: WeatherService.removeRef()

    content: Component {
        Item {
            implicitWidth: {
                if (!SettingsData.weatherEnabled)
                    return 0;
                if (root.isVerticalOrientation)
                    return root.contentThickness;
                return Math.min(100 - root.horizontalPadding * 2, weatherRow.implicitWidth);
            }
            implicitHeight: root.isVerticalOrientation ? weatherColumn.implicitHeight : root.contentThickness

            Column {
                id: weatherColumn
                visible: root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: 1

                DIcon {
                    name: WeatherService.getWeatherIcon(WeatherService.weather.wCode)
                    size: Theme.barIconSize(root.barThickness, -6, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: Theme.widgetIconColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: {
                        if (!WeatherService.weather.available) {
                            return "--";
                        }
                        const temp = SettingsData.useFahrenheit ? WeatherService.weather.tempF : WeatherService.weather.temp;
                        return temp;
                    }
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: root.contentColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Row {
                id: weatherRow
                visible: !root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DIcon {
                    name: WeatherService.getWeatherIcon(WeatherService.weather.wCode)
                    size: Theme.barIconSize(root.barThickness, -6, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: Theme.widgetIconColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                NumericText {
                    text: WeatherService.currentTempText(false)
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: root.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
