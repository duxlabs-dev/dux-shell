import QtQuick
import qs.Common
import qs.Services

MonitorPill {
    id: root

    signal gpuTempClicked

    readonly property int selectedGpuIndex: SettingsData.widgetOption("gpuTemp", widgetData, "selectedGpuIndex")
    readonly property real displayTemp: DgopService.widgetGpu(selectedGpuIndex, widgetData?.pciId)?.temperature || 0

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

    readonly property int availableGpuCount: DgopService.availableGpus?.length ?? 0
    // Deferred: saving the widget's GPU rewrites the bar config this widget is being built from.
    onAvailableGpuCountChanged: Qt.callLater(root.adoptFirstGpu)

    function adoptFirstGpu() {
        if (widgetData?.pciId)
            return;
        const pciId = DgopService.availableGpus?.[0]?.pciId;
        if (!pciId)
            return;
        updateWidgetPciId(pciId);
        DgopService.addGpuPciId(pciId);
    }

    Component.onCompleted: {
        if (widgetData?.pciId)
            DgopService.addGpuPciId(widgetData.pciId);
    }
    Component.onDestruction: {
        if (widgetData && widgetData.pciId) {
            DgopService.removeGpuPciId(widgetData.pciId);
        }
    }
}
