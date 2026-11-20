import QtQuick
import qs.Modules.Settings.Widgets
import "../../../Services/SysmonCatalog.js" as SysmonCatalog

DesktopWidgetInstanceSettings {
    id: root

    readonly property var config: SysmonCatalog.normalizeConfig(cfg, SysmonCatalog.defaultDesktopConfig())

    showOptions: false
    backgroundOption: true
    backgroundConfig: config
    opacityUsed: SysmonCatalog.usesOpacity(config)
    configFixups: cfg.background === "tiles" ? {
        "background": config.background,
        "barStyle": config.barStyle,
        "listStyle": config.listStyle,
        "textShadow": config.textShadow
    } : ({})

    cards: SettingsMonitorConfig {
        config: root.config
        processes: true
        onConfigEdited: (key, value) => root.updateConfig(key, value)
    }
}
