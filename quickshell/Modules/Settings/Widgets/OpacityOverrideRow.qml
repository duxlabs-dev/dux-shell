import QtQuick
import qs.Common

SettingsToggleSliderRow {
    id: root

    required property var config
    property bool isDock: false
    readonly property bool overridden: config?.followInterfaceStyle === false
    readonly property real transparency: config?.transparency ?? 1

    function update(patch) {
        if (!config)
            return;
        if (isDock)
            SettingsData.updateDockConfig(config.id, patch);
        else
            SettingsData.updateBarConfig(config.id, patch);
    }

    text: I18n.tr("Override", "verb, toggle to override the global setting for this item")
    description: I18n.tr("Opacity")
    sliderText: I18n.tr("Opacity")
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
