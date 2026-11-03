pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Widgets

DOSD {
    id: root

    property string iconName: ""
    property string insetIconName: ""
    property string endIconName: ""
    property string endIconLabel: ""
    property bool iconInteractive: false
    property string iconLabel: ""
    property color iconColor: Theme.onPrimary
    property color fillColor: Theme.primary
    property int value: 0
    property int minimum: 0
    property int maximum: 100
    property string unit: "%"
    property string displayText: ""
    property bool available: true

    signal levelRequested(int level)
    signal iconClicked

    readonly property real osdValueReserve: endIconName.length > 0 || SettingsData.osdAlwaysShowValue ? Theme.buttonHeightM : 0

    function showEndIconTooltip(item) {
        endIconTooltip.active = true;
        const tip = endIconTooltip.item;
        if (!tip)
            return;
        const pos = item.mapToItem(null, 0, 0);
        const left = windowX + pos.x;
        const top = windowY + pos.y;
        const gap = Theme.spacingS;
        tip.text = endIconLabel;
        switch (alignY) {
        case 1:
            tip.show(endIconLabel, left + item.width / 2, top - gap - tip.implicitHeight, screen);
            return;
        case -1:
            tip.show(endIconLabel, left + item.width / 2, top + item.height + gap, screen);
            return;
        }
        if (alignX === 1)
            tip.show(endIconLabel, left - gap, top + item.height / 2, screen, false, true);
        else
            tip.show(endIconLabel, left + item.width + gap, top + item.height / 2, screen, true, false);
    }

    function hideEndIconTooltip() {
        endIconTooltip.item?.hide();
        endIconTooltip.active = false;
    }

    onVisibleChanged: {
        if (!visible)
            hideEndIconTooltip();
    }

    function requestLevel(level) {
        if (!available)
            return;
        levelRequested(level);
        resetHideTimer();
    }

    osdWidth: isVerticalLayout ? Theme.osdHeight : Math.min(Theme.osdLevelWidth + osdValueReserve, screenWidth - Theme.spacingM * 2)
    osdHeight: isVerticalLayout ? Math.min(Theme.osdLevelVerticalHeight, screenHeight - Theme.spacingM * 2) : Theme.buttonHeightS + Theme.spacingS * 2
    autoHideInterval: 3000
    sheetWidth: CcMetrics.sheetWidthFor(CcMetrics.minimumColumns)
    enableMouseInteraction: true

    Loader {
        id: endIconTooltip
        active: false
        sourceComponent: DTooltip {}
    }

    content: OsdLevelRow {
        vertical: root.isVerticalLayout
        sliderSize: root.isVerticalLayout ? "m" : "s"
        iconName: root.iconName
        insetIconName: root.insetIconName
        endIconName: root.endIconName
        endIconInteractive: root.sheet !== null
        endIconLabel: root.endIconLabel
        iconInteractive: root.iconInteractive
        iconLabel: root.iconLabel
        iconColor: root.iconColor
        iconBackgroundColor: root.fillColor === Theme.error ? Theme.errorContainer : root.fillColor
        fillColor: root.fillColor
        value: root.value
        minimum: root.minimum
        maximum: root.maximum
        unit: root.unit
        displayText: root.displayText
        sliderEnabled: root.available
        onIconClicked: root.iconClicked()
        onEndIconClicked: {
            root.hideEndIconTooltip();
            root.expand();
        }
        onEndIconHoveredChanged: {
            if (endIconHovered && root.sheet)
                root.showEndIconTooltip(endIconItem);
            else
                root.hideEndIconTooltip();
        }
        onHoverChanged: hovered => root.setChildHovered(hovered)
        onSliderValueChanged: newValue => root.requestLevel(newValue)
    }
}
