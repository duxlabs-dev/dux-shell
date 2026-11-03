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
    property alias showValue: slider.showValue
    property alias unit: slider.unit
    property alias decimals: slider.decimals
    property alias size: slider.size
    property alias trackGradient: slider.trackGradient
    readonly property alias currentValue: slider.value
    property bool wheelEnabled: false
    property string accessibleName: ""
    property string accessibleDescription: ""
    property bool showReset: false

    readonly property int stepAmount: Math.max(1, step)

    signal sliderValueChanged(int newValue)
    signal sliderDragFinished(int finalValue)
    signal resetRequested

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
        Accessible.name: root.accessibleName
        Accessible.description: root.accessibleDescription
        size: "s"
        width: parent.width - (Theme.iconButtonSize + parent.spacing) * 2
        anchors.verticalCenter: parent.verticalCenter
        enabled: root.enabled
        wheelEnabled: root.wheelEnabled
        insetIcon: root.showReset ? "restart_alt" : ""
        insetIconPosition: "end"
        insetIconClickable: true
        insetIconTooltip: I18n.tr("Reset to default")
        onInsetIconClicked: root.resetRequested()
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
