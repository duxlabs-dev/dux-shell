pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash
import qs.Modules.DDash.Weather
import qs.Modules.ControlCenter.Widgets

Item {
    id: root

    property string entryId: "weather"
    property bool live: Window.window?.visible ?? false
    property bool editMode: false
    property bool weatherRefHeld: false
    property var transientSurfaceTracker: null
    readonly property bool available: WeatherService.weather.available
    readonly property var addable: widgets.addable
    readonly property Item focusTarget: available ? widgets.focusTarget : refreshButton
    readonly property var menuActions: [
        {
            label: I18n.tr("Refresh Weather"),
            iconName: "refresh",
            enabled: !WeatherService.weather.loading,
            action: () => WeatherService.forceRefresh()
        },
        {
            label: I18n.tr("Settings"),
            iconName: "settings",
            action: () => {
                PopoutService.closeDankDash();
                PopoutService.openSettingsWithTab("weather");
            }
        }
    ]
    readonly property bool blocksTabNavigation: widgets.blocksTabNavigation
    readonly property bool cardInteracting: widgets.cardInteracting
    readonly property var forecastOptions: [DashRegistry.choice("forecast", I18n.tr("Forecast", "weather widget option label for forecast display type"), "chart", [
            {
                "value": "chart",
                "text": I18n.tr("Chart", "noun, weather forecast display option")
            },
            {
                "value": "cards",
                "text": I18n.tr("Cards", "noun, weather forecast display option")
            }
        ])]
    readonly property var metricOptions: [DashRegistry.toggle("graphics", I18n.tr("Show graphics", "Dashboard widget option for decorative data graphics"), true), DashRegistry.toneOption()]

    implicitWidth: DashMetrics.contentWidthFor(SettingsData.showWeekNumber, DashMetrics.panelColumnsFor(entryId))
    implicitHeight: widgets.implicitHeight
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

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

    function openAddMenu(anchor) {
        widgets.openAddMenu(anchor);
    }
    function resetWidgets() {
        widgets.resetWidgets();
    }
    function clearWidgets() {
        widgets.clearWidgets();
    }
    function handleKeyEvent(event) {
        return widgets.handleKeyEvent(event);
    }
    function cycleFocus(backwards) {
        return widgets.cycleFocus(backwards);
    }

    onLiveChanged: syncWeatherRef(live)
    Component.onCompleted: syncWeatherRef(live)
    Component.onDestruction: syncWeatherRef(false)

    DashWidgetGrid {
        id: widgets
        anchors.fill: parent
        entryId: root.entryId
        transientSurfaceTracker: root.transientSurfaceTracker
        live: root.live && root.available
        editMode: root.editMode
        visible: root.available || root.editMode
        definitions: [
            {
                id: "conditions",
                text: I18n.tr("Current conditions", "Weather dashboard widget"),
                icon: "partly_cloudy_day",
                component: conditions,
                w: 2,
                h: 2,
                minW: 2,
                minH: 2,
                maxW: 4,
                maxH: 3,
                options: [DashRegistry.toneOption("primary"), DashRegistry.toggle("city", I18n.tr("Show city"), false)]
            },
            {
                id: "readings",
                text: I18n.tr("Readings", "weather widget title, grid of current measurements"),
                icon: "grid_view",
                component: readings,
                w: 2,
                h: 2,
                minW: 2,
                minH: 1,
                maxW: 4,
                maxH: 2,
                options: [DashRegistry.toneOption()]
            },
            {
                id: "hourly",
                text: I18n.tr("Hourly", "adjective, hourly weather forecast widget title"),
                icon: "schedule",
                component: hourly,
                w: 4,
                h: 2,
                minW: 2,
                minH: 2,
                maxW: 4,
                maxH: 4,
                options: root.forecastOptions
            },
            {
                id: "sun",
                text: I18n.tr("Sun", "Weather daylight widget title"),
                icon: "sunny",
                component: sun,
                w: 1,
                h: 2,
                minH: 2,
                maxW: 4,
                maxH: 3,
                options: [DashRegistry.toneOption()],
                enabled: false
            },
            {
                id: "moon",
                text: I18n.tr("Moon", "Weather moon position widget title"),
                icon: "dark_mode",
                component: moon,
                w: 1,
                h: 2,
                minH: 2,
                maxW: 4,
                maxH: 3,
                options: [DashRegistry.toneOption()],
                enabled: false
            },
            {
                id: "humidity",
                text: I18n.tr("Humidity"),
                icon: "humidity_low",
                component: metric,
                w: 1,
                h: 2,
                minH: 2,
                maxW: 2,
                maxH: 3,
                options: root.metricOptions,
                enabled: false
            },
            {
                id: "wind",
                text: I18n.tr("Wind"),
                icon: "air",
                component: metric,
                w: 1,
                h: 2,
                minH: 2,
                maxW: 2,
                maxH: 3,
                options: root.metricOptions,
                enabled: false
            },
            {
                id: "daily",
                text: I18n.tr("Daily", "adjective, daily weather forecast widget title"),
                icon: "calendar_month",
                component: daily,
                w: 4,
                h: 2,
                minW: 2,
                minH: 2,
                maxW: 4,
                maxH: 4,
                options: root.forecastOptions
            },
            {
                id: "pressure",
                text: I18n.tr("Pressure"),
                icon: "speed",
                component: metric,
                w: 1,
                h: 2,
                minH: 2,
                maxW: 2,
                maxH: 3,
                options: root.metricOptions,
                enabled: false
            },
            {
                id: "precipitation",
                text: I18n.tr("Precipitation"),
                icon: "rainy",
                component: metric,
                w: 1,
                h: 2,
                minH: 2,
                maxW: 2,
                maxH: 3,
                options: root.metricOptions,
                enabled: false
            },
            {
                id: "visibility",
                text: I18n.tr("Visibility", "weather visibility distance metric", true),
                icon: "visibility",
                component: metric,
                w: 1,
                h: 2,
                minH: 2,
                maxW: 2,
                maxH: 3,
                options: root.metricOptions,
                enabled: false
            },
            {
                id: "uv",
                text: I18n.tr("UV Index"),
                icon: "light_mode",
                component: metric,
                w: 1,
                h: 2,
                minH: 2,
                maxW: 2,
                maxH: 3,
                options: root.metricOptions,
                enabled: false
            }
        ]
    }

    Component {
        id: conditions
        WeatherHero {
            showCity: widgetOptions.city === true
            showSunTimes: true
        }
    }

    Component {
        id: metric
        WeatherMetricCard {}
    }

    Component {
        id: readings
        WeatherReadingsCard {}
    }

    Component {
        id: hourly
        WeatherForecastWidget {
            chartMode: widgetOptions.forecast !== "cards"
        }
    }

    Component {
        id: daily
        WeatherForecastWidget {
            daily: true
            chartMode: widgetOptions.forecast !== "cards"
        }
    }

    Component {
        id: sun
        WeatherSky {}
    }

    Component {
        id: moon
        WeatherSky {
            moon: true
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: Theme.spacingM
        visible: !root.available && !root.editMode

        CcEmptyState {
            iconName: "cloud_off"
            title: I18n.tr("No weather data available")
            subtitle: WeatherService.lastFetchError
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingS

            DRefreshButton {
                id: refreshButton
                busy: WeatherService.weather.loading
                Accessible.name: I18n.tr("Refresh Weather")
                onClicked: WeatherService.forceRefresh()
            }

            DButton {
                text: I18n.tr("Settings")
                iconName: "settings"
                onClicked: {
                    PopoutService.closeDankDash();
                    PopoutService.openSettingsWithTab("weather");
                }
            }
        }
    }
}
