import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root

    required property var pill
    readonly property DTooltip tip: loader.item as DTooltip

    function show(text, from = root.pill) {
        loader.active = true;
        if (!tip)
            return;
        const screen = pill.parentScreen || Screen;
        if (pill.isVerticalOrientation) {
            const pos = from.mapToItem(null, from.width / 2, from.height / 2);
            const isLeft = pill.axis?.edge === "left";
            const x = isLeft ? (pill.barThickness + pill.barSpacing + Theme.spacingXS) : (screen.width - pill.barThickness - pill.barSpacing - Theme.spacingXS);
            tip.show(text, x, pos.y + pill.minTooltipY, screen, isLeft, !isLeft);
            return;
        }
        const pos = from.mapToItem(null, from.width / 2, 0);
        let y = pill.barThickness + pill.barSpacing + Theme.spacingXS;
        if (pill.axis?.edge === "bottom") {
            const tooltipHeight = Theme.fontSizeSmall * 1.5 + Theme.spacingS * 2;
            y = screen.height - pill.barThickness - pill.barSpacing - Theme.spacingXS - tooltipHeight;
        }
        tip.show(text, pos.x, y, screen, false, false);
    }

    function hide() {
        tip?.hide();
        loader.active = false;
    }

    Loader {
        id: loader
        active: false
        sourceComponent: DTooltip {}
    }
}
