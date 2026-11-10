import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

RowLayout {
    spacing: Theme.spacingS

    PerformanceCard {
        Layout.fillWidth: true
        Layout.fillHeight: true
        compact: true
        title: I18n.tr("CPU", "processor label in system monitor")
        icon: "memory"
        value: DgopService.cpuUsage.toFixed(1) + "%"
        extraInfo: DgopService.cpuTemperature > 0 ? DgopService.cpuTemperature.toFixed(0) + "°C" : ""
        history: DgopService.cpuHistory
        accentColor: Theme.primary
    }

    PerformanceCard {
        Layout.fillWidth: true
        Layout.fillHeight: true
        compact: true
        title: I18n.tr("Memory")
        icon: "developer_board"
        value: DgopService.formatSystemMemory(DgopService.usedMemoryKB) + " / " + DgopService.formatSystemMemory(DgopService.totalMemoryKB)
        extraInfo: DgopService.totalSwapKB > 0 ? I18n.tr("Swap", "swap memory label in system monitor") + ": " + DgopService.formatSystemMemory(DgopService.usedSwapKB) : ""
        history: DgopService.memoryHistory
        accentColor: Theme.secondary
    }
}
