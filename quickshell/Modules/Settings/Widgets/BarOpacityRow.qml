import QtQuick
import qs.Common

SettingsToggleSliderRow {
    id: root

    required property var barConfig
    readonly property bool overridden: barConfig?.followInterfaceStyle === false
    readonly property real transparency: barConfig?.transparency ?? 1

    function update(patch) {
        if (barConfig)
            SettingsData.updateBarConfig(barConfig.id, patch);
    }

    text: I18n.tr("Opacity")
    description: I18n.tr("Override")
    checked: overridden
    value: Math.round(transparency * 100)
    minimum: 0
    maximum: 100
    modified: overridden
    valueModified: transparency !== 1
    onResetRequested: update({
        followInterfaceStyle: true,
        transparency: 1
    })
    onValueResetRequested: update({
        transparency: 1
    })
    onToggled: checked => update({
            followInterfaceStyle: !checked
        })
    onSliderDragFinished: finalValue => update({
            transparency: finalValue / 100
        })
}
