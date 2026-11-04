import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

NiriRow {
    id: root

    property real from: 0
    property real to: 100
    property real stepSize: 1
    property int decimals: 0
    property string unit: ""

    // DSlider only holds integers, so fractional settings travel scaled by 10^decimals.
    readonly property real factor: Math.pow(10, decimals)
    // A row may map a sentinel (width -1 = niri's default) to where the slider should sit
    property real numValue: Number(value)
    readonly property real naturalSliderWidth: Theme.iconButtonSize * 5

    function snap(v) {
        const steps = Math.round((v - from) / stepSize);
        return Math.round((from + steps * stepSize) * factor) / factor;
    }

    function format(v) {
        return v.toFixed(decimals) + unit;
    }

    toggle: false
    tryValue: snap(numValue > (from + to) / 2 ? from + (to - from) / 4 : to - (to - from) / 4)
    controlWidth: naturalSliderWidth + Theme.spacingS + chip.width

    onNumValueChanged: slider.value = Math.round(numValue * factor)

    DSlider {
        id: slider

        anchors.verticalCenter: parent.verticalCenter
        width: root.stacked ? Math.max(0, root.stackedControlWidth - chip.width - Theme.spacingS) : root.naturalSliderWidth
        size: "xs"
        // One step of lead before `from` keeps low values (ring width 2) off the track's rounded start;
        // the lead is never a value, the handle snaps back to `from`
        readonly property int floor: Math.round(root.from * root.factor)
        minimum: floor - step
        maximum: Math.round(root.to * root.factor)
        step: Math.max(1, Math.round(root.stepSize * root.factor))
        showValue: false
        trackColor: SettingsMetrics.controlColor
        Accessible.name: root.title
        Component.onCompleted: value = Math.round(root.numValue * root.factor)
        onSliderValueChanged: newValue => {
            if (newValue < floor)
                value = floor;
        }
        onSliderDragFinished: finalValue => {
            const next = finalValue / root.factor;
            if (next !== root.numValue)
                root.write(next);
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
            text: root.format(slider.value / root.factor)
            reserveText: root.format(root.from).length > root.format(root.to).length ? root.format(root.from) : root.format(root.to)
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightBold
            color: Theme.surfaceText
        }
    }
}
