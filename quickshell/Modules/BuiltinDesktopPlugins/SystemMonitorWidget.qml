import QtQuick
import qs.Common
import qs.Modules.Sysmon
import "../../Services/SysmonCatalog.js" as SysmonCatalog

Item {
    id: root

    property real widgetWidth: 320
    property real widgetHeight: 480
    property real defaultWidth: 320
    property real defaultHeight: 480
    property real minWidth: {
        if (metricCount === 0)
            return 80;
        if (metricCount === 1)
            return 100;
        return 160;
    }
    property real minHeight: {
        if (metricCount === 0)
            return 60;
        if (metricCount === 1)
            return 80;
        if (metricCount <= 2)
            return 120;
        return 180;
    }

    property string instanceId: ""
    property var instanceData: null

    readonly property var cfg: instanceData?.config ?? ({})
    readonly property var config: SysmonCatalog.normalizeConfig(cfg, SysmonCatalog.defaultDesktopConfig())
    readonly property int metricCount: config.metrics.filter(m => m.on).length
    readonly property real transparency: cfg.transparency ?? 0.8
    readonly property string background: config.background
    readonly property bool monitoringActive: visible && enabled && (Window.window?.visible ?? false)

    readonly property color accentColor: {
        switch (cfg.colorMode) {
        case "secondary":
            return Theme.secondary;
        case "custom":
            return cfg.customColor ?? "#ffffff";
        default:
            return Theme.primary;
        }
    }

    enabled: instanceData?.enabled ?? true

    Rectangle {
        anchors.fill: parent
        visible: root.background === "card"
        radius: Theme.cornerRadiusXL
        color: Theme.withAlpha(Theme.hostSurface, root.transparency)
    }

    MonitorContent {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        config: root.config
        active: root.monitoringActive
        accentColor: root.accentColor
        tileColor: Theme.withAlpha(Theme.cardSurface, root.transparency)
        halo: root.background === "none" && root.config.textShadow
    }
}
