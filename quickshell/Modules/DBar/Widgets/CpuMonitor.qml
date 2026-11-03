import qs.Services

MonitorPill {
    id: root

    signal cpuClicked

    readonly property real usage: DgopService.cpuUsage

    widgetType: "cpuUsage"
    dgopModules: ["cpu"]
    iconName: "memory"
    level: usage
    warnLevel: 60
    dangerLevel: 80
    verticalText: usage ? usage.toFixed(0) : "--"
    horizontalText: usage ? usage.toFixed(0) + "%" : "--%"
    reserveText: "100%"
    sortKey: "cpu"
    onActivated: cpuClicked()
}
