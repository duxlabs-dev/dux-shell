import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.DesktopWidgetSettings

DesktopWidgetInstanceSettings {
    id: root

    showAppearance: false

    SettingsDropdownRow {
        text: I18n.tr("Lock screen content")
        options: [I18n.tr("Count only", "lock screen notification mode option"), I18n.tr("App names", "lock screen notification mode option"), I18n.tr("Full content", "lock screen notification mode option")]
        currentValue: options[(root.cfg.mode ?? 1) - 1] ?? options[0]
        onValueChanged: value => {
            const idx = options.indexOf(value);
            if (idx < 0)
                return;
            root.updateConfig("mode", idx + 1);
        }
    }
}
