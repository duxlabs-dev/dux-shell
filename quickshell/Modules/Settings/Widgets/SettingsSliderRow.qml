import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property string text: ""
    property string description: ""
    property string minimumLabel: ""
    property real value: 0
    property alias minimum: control.minimum
    property alias maximum: control.maximum
    property alias step: control.step
    property alias showStops: control.showStops
    property alias unit: control.unit
    property alias decimals: control.decimals
    property alias size: control.size
    property alias trackGradient: control.trackGradient

    readonly property bool atMinimum: minimumLabel !== "" && control.currentValue === control.minimum
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

    StyledText {
        text: root.minimumLabel
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        visible: root.atMinimum
        anchors.verticalCenter: parent.verticalCenter
    }

    body: SettingsSliderControl {
        id: control
        width: parent.width
        value: root.value
        enabled: root.enabled
        showValue: !root.atMinimum
        wheelEnabled: root.wheelEnabled
        accessibleName: root.text
        accessibleDescription: root.description
        onSliderValueChanged: newValue => root.sliderValueChanged(newValue)
        onSliderDragFinished: finalValue => root.sliderDragFinished(finalValue)
    }
}
