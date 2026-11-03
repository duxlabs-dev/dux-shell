import QtQuick
import qs.Common
import qs.Services

MonitorPill {
    id: root

    signal gpuTempClicked

    readonly property int selectedGpuIndex: SettingsData.widgetOption("gpuTemp", widgetData, "selectedGpuIndex")
    readonly property real displayTemp: {
        const gpus = DgopService.availableGpus;
        if (!gpus || selectedGpuIndex < 0 || selectedGpuIndex >= gpus.length)
            return 0;
        return gpus[selectedGpuIndex].temperature || 0;
    }

    widgetType: "gpuTemp"
    dgopModules: ["gpu"]
    iconName: "auto_awesome_mosaic"
    level: displayTemp
    warnLevel: 65
    dangerLevel: 80
    verticalText: displayTemp ? Math.round(displayTemp).toString() : "--"
    horizontalText: displayTemp ? Math.round(displayTemp) + "°" : "--°"
    reserveText: "88°"
    sortKey: "cpu"
    onActivated: gpuTempClicked()

    function updateWidgetPciId(pciId) {
        const sections = ["left", "center", "right"];
        const defaultBar = SettingsData.getPrimaryBarConfig();
        if (!defaultBar)
            return;
        for (let s = 0; s < sections.length; s++) {
            const sectionId = sections[s];
            let widgets = [];
            if (sectionId === "left") {
                widgets = (defaultBar.leftWidgets || []).slice();
            } else if (sectionId === "center") {
                widgets = (defaultBar.centerWidgets || []).slice();
            } else if (sectionId === "right") {
                widgets = (defaultBar.rightWidgets || []).slice();
            }
            for (let i = 0; i < widgets.length; i++) {
                const widget = widgets[i];
                if (typeof widget === "object" && widget.id === "gpuTemp" && (!widget.pciId || widget.pciId === "")) {
                    widgets[i] = {
                        "id": widget.id,
                        "enabled": widget.enabled !== undefined ? widget.enabled : true,
                        "selectedGpuIndex": 0,
                        "pciId": pciId
                    };
                    if (sectionId === "left") {
                        SettingsData.setDankBarLeftWidgets(widgets);
                    } else if (sectionId === "center") {
                        SettingsData.setDankBarCenterWidgets(widgets);
                    } else if (sectionId === "right") {
                        SettingsData.setDankBarRightWidgets(widgets);
                    }
                    return;
                }
            }
        }
    }

    Component.onCompleted: {
        if (widgetData && widgetData.pciId) {
            DgopService.addGpuPciId(widgetData.pciId);
        } else {
            autoSaveTimer.running = true;
        }
    }
    Component.onDestruction: {
        if (widgetData && widgetData.pciId) {
            DgopService.removeGpuPciId(widgetData.pciId);
        }
    }

    Timer {
        id: autoSaveTimer

        interval: 100
        running: false
        onTriggered: {
            if (DgopService.availableGpus && DgopService.availableGpus.length > 0) {
                const firstGpu = DgopService.availableGpus[0];
                if (firstGpu && firstGpu.pciId) {
                    updateWidgetPciId(firstGpu.pciId);
                    DgopService.addGpuPciId(firstGpu.pciId);
                }
            }
        }
    }
}
