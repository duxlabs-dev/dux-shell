import QtQuick
import qs.Common
import qs.Modules.DDash
import qs.Modules.Sysmon
import "../../../Services/SysmonCatalog.js" as SysmonCatalog

Card {
    id: root

    property bool live: Window.window?.visible ?? false

    readonly property var config: Object.assign(SysmonCatalog.normalizeConfig(DashRegistry.cardConfig(entryId, instanceId), SysmonCatalog.defaultDashConfig()), {
        "background": "card",
        "showTopProcesses": false
    })
    // A single tile is the card itself, without padding or a surface of its own.
    readonly property bool soloTile: config.layout === "tiles" && config.metrics.filter(m => m.on).length === 1

    entryId: "sysmon"
    tone: typeof config.tone === "string" ? config.tone : ""
    clipContent: true
    pad: soloTile ? 0 : Theme.spacingM

    MonitorContent {
        anchors.fill: parent
        config: root.config
        active: root.live
        accentColor: root.accentColor
        contentColor: root.contentColor
        mutedColor: root.mutedColor
        tileColor: root.soloTile ? "transparent" : root.chipColor
        trendSecondaryColor: root.tinted ? root.mutedColor : Theme.tertiary
        tileRadius: root.soloTile ? DashMetrics.cardRadius : Theme.cornerRadiusS
    }
}
