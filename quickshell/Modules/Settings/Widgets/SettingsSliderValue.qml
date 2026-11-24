import QtQuick
import qs.Common
import qs.DCommon.Common as DCommon
import qs.DCommon.Widgets

NumericText {
    id: root

    required property SettingsSliderControl slider
    property string minimumLabel: ""
    property string label: ""
    property bool shown: true

    readonly property bool atMinimum: minimumLabel !== "" && slider.currentValue === slider.minimum
    readonly property real restOpacity: enabled ? 1 : SettingsMetrics.disabledOpacity

    opacity: shown ? restOpacity : 0
    text: {
        if (atMinimum)
            return minimumLabel;
        if (label !== "")
            return label;
        return slider.valueText;
    }
    reserveText: slider.widestValueText
    width: Math.max(reservedWidth, Math.ceil(DCommon.Fonts.textWidth(font, minimumLabel)))
    horizontalAlignment: Text.AlignRight
    font.pixelSize: Theme.fontSizeSmall
    color: Theme.surfaceVariantText
    Accessible.ignored: true
}
