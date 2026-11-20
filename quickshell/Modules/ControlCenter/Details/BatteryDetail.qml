import QtQuick
import qs.Common
import qs.Modules.DBar.Popouts
import qs.Services

BatteryPopoutContent {
    readonly property string title: BatteryService.batteryAvailable || BatteryService.hasPeripherals ? I18n.tr("Battery") : I18n.tr("Power")

    active: Window.window?.visible ?? false
    contentPadding: 0
    showEdit: false
    onSettingsOpening: PopoutService.closeControlCenter()
}
