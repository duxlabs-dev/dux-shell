import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets

RowLayout {
    spacing: Theme.spacingS

    SystemLogo {
        Layout.preferredWidth: Theme.iconSize
        Layout.preferredHeight: Theme.iconSize
        colorOverride: Theme.primary
    }

    StyledText {
        Layout.fillWidth: true
        text: (DgopService.hostname || "localhost") + " · " + (DgopService.distribution || "Linux") + " · " + I18n.tr("Uptime") + ": " + (DgopService.shortUptime ? DgopService.shortUptime.slice(2).trim() : "--") + " · " + I18n.tr("%1 procs", "short for processes, %1 is a count").arg(DgopService.processCount)
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.onSurfaceVariant
        elide: Text.ElideRight
    }

    Repeater {
        model: DgopService.availableGpus.filter(gpu => (SessionData.enabledGpuPciIds || []).includes(gpu.pciId) && gpu.temperature > 0)
        NumericText {
            required property var modelData
            text: I18n.tr("GPU %1", "%1 is a temperature").arg(modelData.temperature.toFixed(0) + "°C")
            reserveText: I18n.tr("GPU %1", "%1 is a temperature").arg("100°C")
            font.pixelSize: Theme.fontSizeSmall
            color: modelData.temperature > 85 ? Theme.error : Theme.onSurfaceVariant
        }
    }
}
