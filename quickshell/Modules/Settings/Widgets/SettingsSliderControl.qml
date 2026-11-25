import QtQuick
import qs.Common
import qs.DCommon.Widgets

Row {
    id: root

    property real value: 0
    property alias minimum: slider.minimum
    property alias maximum: slider.maximum
    property alias step: slider.step
    property alias showStops: slider.showStops
    property alias unit: slider.unit
    property alias decimals: slider.decimals
    property alias size: slider.size
    property alias trackGradient: slider.trackGradient
    readonly property alias currentValue: slider.value
    readonly property alias dragging: slider.isDragging
    property bool wheelEnabled: false
    property string accessibleName: ""
    property string accessibleDescription: ""

    readonly property int stepAmount: Math.max(1, step)
    readonly property string valueText: slider.formatValue(slider.value)
    readonly property string widestValueText: {
        const low = slider.formatValue(minimum);
        const high = slider.formatValue(maximum);
        return low.length > high.length ? low : high;
    }

    signal sliderValueChanged(int newValue)
    signal sliderDragFinished(int finalValue)

    function nudge(direction) {
        const next = Math.max(minimum, Math.min(maximum, slider.value + direction * stepAmount));
        if (next === slider.value)
            return;
        slider.value = next;
        sliderValueChanged(next);
        sliderDragFinished(next);
    }

    function resync() {
        slider.value = Math.round(value);
    }

    onValueChanged: resync()
    spacing: Theme.spacingS
    leftPadding: -SettingsMetrics.sliderButtonBleed
    rightPadding: -SettingsMetrics.sliderButtonBleed

    DActionButton {
        buttonSize: Theme.iconButtonSize
        iconName: "remove"
        Accessible.name: I18n.tr("Decrease", "verb, minus button next to a settings slider")
        iconSize: Theme.iconSizeMedium
        iconColor: Theme.surfaceVariantText
        enabled: root.enabled && slider.value > slider.minimum
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.nudge(-1)
    }

    DSlider {
        id: slider
        upDownKeysStep: false
        showValue: false
        Accessible.name: root.accessibleName
        Accessible.description: root.accessibleDescription
        size: "s"
        width: parent.width - (Theme.iconButtonSize + parent.spacing - SettingsMetrics.sliderButtonBleed) * 2
        anchors.verticalCenter: parent.verticalCenter
        enabled: root.enabled
        wheelEnabled: root.wheelEnabled
        Component.onCompleted: value = Math.round(root.value)
        onSliderValueChanged: newValue => root.sliderValueChanged(newValue)
        onSliderDragFinished: finalValue => root.sliderDragFinished(finalValue)
    }

    DActionButton {
        buttonSize: Theme.iconButtonSize
        iconName: "add"
        Accessible.name: I18n.tr("Increase", "verb, plus button next to a settings slider")
        iconSize: Theme.iconSizeMedium
        iconColor: Theme.surfaceVariantText
        enabled: root.enabled && slider.value < slider.maximum
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.nudge(1)
    }
}
