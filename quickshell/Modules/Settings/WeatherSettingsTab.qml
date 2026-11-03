import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null
    readonly property var coordinates: SettingsData.weatherCoordinates.split(",")
    readonly property bool validCoordinates: latitude.text.trim() !== "" && longitude.text.trim() !== "" && Number.isFinite(Number(latitude.text)) && Number.isFinite(Number(longitude.text)) && Math.abs(Number(latitude.text)) <= 90 && Math.abs(Number(longitude.text)) <= 180
    readonly property bool coordinatesEdited: Number(latitude.text) !== Number(coordinates[0]) || Number(longitude.text) !== Number(coordinates[1])

    function saveCoordinates() {
        if (!validCoordinates || !coordinatesEdited)
            return;
        SettingsData.setWeatherLocation("", Number(latitude.text) + "," + Number(longitude.text));
    }

    SettingsPage {
        SettingsCard {
            title: I18n.tr("General")
            tab: "weather"
            settingKey: "weather"

            SettingsToggleRow {
                tab: "weather"
                settingKey: "weatherEnabled"
                tags: ["weather", "enable", "forecast"]
                text: I18n.tr("Weather")
                checked: SettingsData.weatherEnabled
                onToggled: checked => SettingsData.set("weatherEnabled", checked)
            }

            SettingsToggleRow {
                tab: "weather"
                settingKey: "useFahrenheit"
                tags: ["weather", "imperial", "fahrenheit", "celsius", "units", "mph"]
                text: I18n.tr("Imperial units")
                checked: SettingsData.useFahrenheit
                onToggled: checked => SettingsData.set("useFahrenheit", checked)
            }

            SettingsToggleRow {
                enabled: !SettingsData.useFahrenheit
                tab: "weather"
                settingKey: "windSpeedUnit"
                tags: ["weather", "wind", "speed", "units", "metric"]
                text: I18n.tr("Wind speed in m/s")
                checked: SettingsData.windSpeedUnit === "ms"
                onToggled: checked => SettingsData.set("windSpeedUnit", checked ? "ms" : "kmh")
            }
        }

        SettingsCard {
            title: I18n.tr("Location")
            tab: "weather"
            settingKey: "weatherLocation"
            tags: ["weather", "location", "city", "coordinates"]

            SettingsToggleRow {
                tab: "weather"
                settingKey: "useAutoLocation"
                tags: ["weather", "location", "auto", "gps", "ip"]
                text: I18n.tr("Auto location")
                checked: SettingsData.useAutoLocation
                onToggled: checked => SettingsData.set("useAutoLocation", checked)
            }

            SettingsRow {
                enabled: !SettingsData.useAutoLocation
                title: I18n.tr("Location search")
                body: DLocationSearch {
                    width: parent.width
                    currentLocation: SettingsData.weatherLocation
                    placeholderText: I18n.tr("New York, NY")
                    onLocationSelected: (displayName, coordinates) => SettingsData.setWeatherLocation(displayName, coordinates)
                }
            }

            SettingsRow {
                enabled: !SettingsData.useAutoLocation
                title: I18n.tr("Custom location")
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        DTextField {
                            id: latitude
                            outlined: true
                            leftIconName: "location_on"
                            width: (parent.width - parent.spacing) / 2
                            labelText: I18n.tr("Latitude", "weather location coordinate text field label")
                            text: root.coordinates[0]?.trim() ?? ""
                            keyNavigationTab: longitude
                            onAccepted: root.saveCoordinates()
                        }

                        DTextField {
                            id: longitude
                            outlined: true
                            leftIconName: "location_on"
                            width: (parent.width - parent.spacing) / 2
                            labelText: I18n.tr("Longitude", "weather location coordinate text field label")
                            text: root.coordinates[1]?.trim() ?? ""
                            keyNavigationBacktab: latitude
                            onAccepted: root.saveCoordinates()
                        }
                    }

                    DButton {
                        text: I18n.tr("Apply", "verb, button that saves custom weather coordinates")
                        enabled: root.validCoordinates && root.coordinatesEdited
                        onClicked: root.saveCoordinates()
                    }
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Weather providers", "Weather data source priority settings")
            tab: "weather"
            settingKey: "weatherProviders"
            tags: ["weather", "provider", "source", "fallback", "priority", "order", "open-meteo", "met norway"]

            headerActions: DActionButton {
                iconName: "restart_alt"
                tooltipText: I18n.tr("Reset to default")
                enabled: !SettingsData.isDefault(["weatherProviders"])
                onClicked: SettingsData.resetToDefault(["weatherProviders"])
            }

            SettingsRow {
                title: I18n.tr("Drag to reorder")
                subtitle: I18n.tr("The next enabled provider is used when one fails.", "weather providers fallback hint")
            }

            SettingsReorderList {
                id: weatherProviderList
                model: WeatherService.providerOrder.split(",")
                onReordered: indices => WeatherService.reorderProviders(indices)

                delegate: SettingsReorderRow {
                    id: providerRow
                    required property string modelData
                    readonly property var provider: WeatherService.providers.find(provider => provider.id === modelData)
                    reorderList: weatherProviderList
                    title: provider?.text ?? ""
                    clickable: true
                    onClicked: WeatherService.setProviderEnabled(modelData, !provider?.enabled)

                    DToggle {
                        hideText: true
                        Accessible.name: providerRow.title
                        checked: providerRow.provider?.enabled ?? false
                        onToggled: checked => WeatherService.setProviderEnabled(providerRow.modelData, checked)
                    }
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Display")
            tab: "weather"
            settingKey: "weatherDisplay"

            SettingsToggleRow {
                readonly property var lockStatus: SettingsData.lockWidgetInstance("lockStatus")

                tab: "weather"
                settingKey: "lockStatusWeather"
                tags: ["weather", "lock", "screen"]
                visible: lockStatus !== null
                text: I18n.tr("Lock screen")
                checked: lockStatus?.config?.showWeather ?? true
                onToggled: checked => SettingsData.updateDesktopWidgetInstanceConfig(lockStatus.id, {
                        showWeather: checked
                    })
            }

            SettingsNavRow {
                title: I18n.tr("Dashboard")
                iconName: "space_dashboard"
                onClicked: keyboard => root.parentModal?.navigateTo("dank_dash", keyboard)
            }

            SettingsNavRow {
                title: I18n.tr("Bar widgets")
                iconName: "widgets"
                onClicked: keyboard => root.parentModal?.navigateTo("dankbar_widgets", keyboard)
            }
        }
    }
}
