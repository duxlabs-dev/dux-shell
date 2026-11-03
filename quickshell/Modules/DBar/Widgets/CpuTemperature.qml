import qs.Services

MonitorPill {
    id: root

    signal cpuTempClicked

    readonly property real temperature: DgopService.cpuTemperature
    readonly property bool hasReading: temperature >= 0

    widgetType: "cpuTemp"
    dgopModules: ["cpu"]
    iconName: "device_thermostat"
    level: temperature
    warnLevel: 69
    dangerLevel: 85
    verticalText: hasReading ? Math.round(temperature).toString() : "--"
    horizontalText: hasReading ? Math.round(temperature) + "°" : "--°"
    reserveText: "88°"
    sortKey: "cpu"
    onActivated: cpuTempClicked()
}
