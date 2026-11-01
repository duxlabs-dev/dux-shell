import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

// NiriSlider's look for a SettingsData value where 0 means "niri's default": the slider shows `fallback` then.
Row {
    id: root

    property int value: 0
    property int fallback: 0
    property int from: 0
    property int to: 100
    property int stepSize: 1
    property string unit: ""
    readonly property real naturalSliderWidth: Theme.iconButtonSize * 5
    readonly property real naturalWidth: naturalSliderWidth + spacing + chip.width
    // Width to fill in a stacked row, 0 for the natural width
    property real fillWidth: 0
    property string accessibleName: ""

    readonly property int shown: value > 0 ? value : fallback

    signal moved(int value)

    spacing: Theme.spacingS

    onShownChanged: slider.value = shown

    DSlider {
        id: slider

        anchors.verticalCenter: parent.verticalCenter
        width: root.fillWidth > 0 ? Math.max(0, root.fillWidth - chip.width - root.spacing) : root.naturalSliderWidth
        size: "xs"
        minimum: root.from
        maximum: root.to
        step: root.stepSize
        showValue: false
        trackColor: SettingsMetrics.controlColor
        Accessible.name: root.accessibleName
        Component.onCompleted: value = root.shown
        onSliderDragFinished: finalValue => {
            if (finalValue !== root.shown)
                root.moved(finalValue);
        }
    }

    Rectangle {
        id: chip
        anchors.verticalCenter: parent.verticalCenter
        width: chipText.reservedWidth + Theme.spacingS * 2
        height: chipText.implicitHeight + Theme.spacingXS
        radius: height / 2
        color: SettingsMetrics.controlColor

        NumericText {
            id: chipText
            anchors.centerIn: parent
            isMonospace: false
            text: slider.value + root.unit
            reserveText: root.to + root.unit
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightBold
            color: Theme.surfaceText
        }
    }
}
