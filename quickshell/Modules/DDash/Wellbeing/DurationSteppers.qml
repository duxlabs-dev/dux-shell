import QtQuick
import qs.Common
import qs.DCommon.Widgets

Row {
    id: root

    property int minutes: 0
    readonly property int hours: Math.floor(minutes / 60)
    readonly property int remainder: minutes % 60
    readonly property int maxMinutes: 24 * 60 - 1

    signal committed(int minutes)

    function commit(next) {
        committed(Math.max(0, Math.min(maxMinutes, next)));
    }

    spacing: Theme.spacingS

    DNumberStepper {
        text: I18n.tr("%1h", "hours abbreviation, %1 is a number").arg(root.hours)
        incrementEnabled: root.minutes + 60 <= root.maxMinutes
        decrementEnabled: root.hours > 0
        onIncrement: () => root.commit(root.minutes + 60)
        onDecrement: () => root.commit(root.minutes - 60)
    }

    DNumberStepper {
        text: I18n.tr("%1m").arg(root.remainder)
        incrementEnabled: root.minutes < root.maxMinutes
        decrementEnabled: root.minutes > 0
        onIncrement: () => root.commit(root.minutes + 1)
        onDecrement: () => root.commit(root.minutes - 1)
    }
}
