pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    readonly property bool isSettingsRow: true
    readonly property bool transparentSlot: true
    readonly property bool inGroup: parent?.isSettingsGroupHost ?? false
    readonly property bool isFirstInGroup: inGroup ? parent.isEdge(root, true) : true

    property string startTitle: ""
    property int startHour: 7
    property int startMinute: 0
    property string endTitle: ""
    property int endHour: 19
    property int endMinute: 0
    property bool is24Hour: false
    property bool showEnd: true

    signal startChanged(int hour, int minute)
    signal endChanged(int hour, int minute)

    property bool _editingStart: true

    function formatTime(hour, minute) {
        const m = (minute < 10 ? "0" : "") + minute;
        if (is24Hour)
            return (hour < 10 ? "0" : "") + hour + ":" + m;
        const h = hour % 12 === 0 ? 12 : hour % 12;
        return (h < 10 ? "0" : "") + h + ":" + m + " " + (hour >= 12 ? I18n.tr("PM", "12 hour clock suffix after noon in time setting") : I18n.tr("AM", "12 hour clock suffix before noon in time setting"));
    }

    function edit(start) {
        _editingStart = start;
        pickerLoader.active = true;
        const picker = pickerLoader.item;
        if (!picker)
            return;
        picker.hour = start ? startHour : endHour;
        picker.minute = start ? startMinute : endMinute;
        picker.title = start ? startTitle : endTitle;
        picker.open();
    }

    width: parent?.width ?? 0
    height: halves.implicitHeight

    Rectangle {
        x: SettingsMetrics.rowPaddingH
        z: 1
        width: parent.width - SettingsMetrics.rowPaddingH * 2
        height: Theme.dividerWidth
        visible: SettingsMetrics.continuousGroups && root.inGroup && !root.isFirstInGroup
        color: SettingsMetrics.groupDividerColor
    }

    Row {
        id: halves
        width: parent.width
        spacing: Theme.groupedListGap

        Repeater {
            model: root.showEnd ? 2 : 1

            SettingsRow {
                required property int index
                readonly property bool isStart: index === 0

                width: root.showEnd ? (root.width - Theme.groupedListGap) / 2 : root.width
                paintBackground: true
                inGroup: root.inGroup
                dividerBefore: false
                topRadius: Theme.groupedListOuterRadius
                bottomRadius: Theme.groupedListOuterRadius
                title: isStart ? root.startTitle : root.endTitle
                subtitle: root.formatTime(isStart ? root.startHour : root.endHour, isStart ? root.startMinute : root.endMinute)
                subtitleColor: Theme.surfaceText
                clickable: true
                enabled: root.enabled
                onClicked: root.edit(isStart)

                DIcon {
                    name: "schedule"
                    size: Theme.iconSize
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Loader {
        id: pickerLoader
        active: false

        sourceComponent: DTimePicker {
            parent: root.Window.contentItem
            is24Hour: root.is24Hour
            onAccepted: (hour, minute) => {
                if (root._editingStart) {
                    root.startChanged(hour, minute);
                    return;
                }
                root.endChanged(hour, minute);
            }
        }
    }
}
