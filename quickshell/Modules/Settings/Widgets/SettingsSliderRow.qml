import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property string text: ""
    property string description: ""
    property string minimumLabel: ""
    property string valueLabel: ""
    property string accessibleName: text
    property real value: 0
    property alias minimum: control.minimum
    property alias maximum: control.maximum
    property alias step: control.step
    property alias showStops: control.showStops
    property alias unit: control.unit
    property alias decimals: control.decimals
    property alias size: control.size
    property alias trackGradient: control.trackGradient

    readonly property alias atMinimum: valueLabel.atMinimum
    readonly property alias currentValue: control.currentValue
    readonly property alias dragging: control.dragging
    readonly property int stepAmount: control.stepAmount

    signal sliderValueChanged(int newValue)
    signal sliderDragFinished(int finalValue)

    function nudge(direction) {
        control.nudge(direction);
    }

    function resync() {
        control.resync();
    }

    title: text
    subtitle: description
    trailingOnTitleLine: true

    SettingsSliderValue {
        id: valueLabel
        slider: control
        minimumLabel: root.minimumLabel
        label: root.valueLabel
        anchors.verticalCenter: parent.verticalCenter
    }

    body: SettingsSliderControl {
        id: control
        width: parent.width
        value: root.value
        enabled: root.enabled
        wheelEnabled: root.wheelEnabled
        accessibleName: root.accessibleName
        accessibleDescription: root.description
        onSliderValueChanged: newValue => root.sliderValueChanged(newValue)
        onSliderDragFinished: finalValue => root.sliderDragFinished(finalValue)
    }
}
