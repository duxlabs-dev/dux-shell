import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

MonitorPill {
    id: root

    property bool isHovered: mouseArea.containsMouse
    readonly property string mountPath: SettingsData.widgetOption("diskUsage", widgetData, "mountPath")
    readonly property int diskUsageMode: SettingsData.widgetOption("diskUsage", widgetData, "diskUsageMode")
    readonly property bool showMountPath: SettingsData.widgetOption("diskUsage", widgetData, "showMountPath")
    readonly property var selectedMount: {
        const mounts = DgopService.diskMounts;
        if (!mounts || mounts.length === 0)
            return null;
        const wanted = mountPath || "/";
        return mounts.find(entry => entry.mount === wanted) ?? mounts.find(entry => entry.mount === "/") ?? mounts[0] ?? null;
    }
    readonly property real diskUsagePercent: parseFloat((selectedMount?.percent ?? "").replace("%", "")) || 0

    function valueText(suffix) {
        if (!diskUsagePercent || !selectedMount)
            return "--" + suffix;
        switch (diskUsageMode) {
        case 1:
            return selectedMount.size || "--";
        case 2:
            return selectedMount.avail || "--";
        case 3:
            return (selectedMount.avail || "--") + " / " + (selectedMount.size || "--");
        default:
            return diskUsagePercent.toFixed(0) + suffix;
        }
    }

    widgetType: "diskUsage"
    dgopModules: ["diskmounts"]
    iconName: "storage"
    level: diskUsagePercent
    warnLevel: 75
    dangerLevel: 90
    verticalText: valueText("")
    horizontalLabel: showMountPath ? (selectedMount?.mount ?? "--") : ""
    horizontalText: valueText("%")
    reserveText: {
        switch (diskUsageMode) {
        case 3:
            return "888.8G / 888.8G";
        case 1:
        case 2:
            return "888.8G";
        default:
            return "100%";
        }
    }

    Loader {
        id: tooltipLoader
        active: false
        sourceComponent: DTooltip {}
    }

    MouseArea {
        id: mouseArea
        z: 1
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        hoverEnabled: root.isVerticalOrientation
        onEntered: {
            if (root.isVerticalOrientation && root.selectedMount) {
                tooltipLoader.active = true;
                if (tooltipLoader.item) {
                    const localPos = mapToItem(null, width / 2, height / 2);
                    const currentScreen = root.parentScreen || Screen;
                    const adjustedY = localPos.y + root.minTooltipY;
                    const tooltipX = root.axis?.edge === "left" ? (root.barThickness + root.barSpacing + Theme.spacingXS) : (currentScreen.width - root.barThickness - root.barSpacing - Theme.spacingXS);
                    const isLeft = root.axis?.edge === "left";
                    tooltipLoader.item.show(root.selectedMount.mount, tooltipX, adjustedY, currentScreen, isLeft, !isLeft);
                }
            }
        }
        onExited: {
            if (tooltipLoader.item) {
                tooltipLoader.item.hide();
            }
            tooltipLoader.active = false;
        }
    }
}
