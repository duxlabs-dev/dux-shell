import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    property bool vertical: false
    property bool live: visible && enabled
    property string displayMode: "both"
    property bool dateFirst: false
    property real fontSize: Theme.fontSizeMedium
    property real availableWidth: fontSize * 2
    property color textColor: Theme.surfaceText
    property color dateColor: textColor
    property color separatorColor: Theme.outlineButton
    property bool segmented: false
    property var locale: I18n.locale()
    property date date: systemClock.date

    readonly property string timeText: date.toLocaleTimeString(locale, SettingsData.getEffectiveTimeFormat())
    readonly property string dateText: date.toLocaleDateString(locale, SettingsData.getEffectiveDateFormat())
    readonly property var timeLines: vertical ? stackedTime() : [timeText]
    readonly property var dateLines: vertical ? stackedDate() : [dateText]
    readonly property bool showTime: displayMode !== "date"
    readonly property bool showDate: displayMode !== "time"
    readonly property bool split: segmented && !vertical && showTime && showDate
    readonly property real splitOffset: split ? layout.x + separator.x + separator.width / 2 : 0

    implicitWidth: vertical ? availableWidth : layout.implicitWidth
    implicitHeight: layout.implicitHeight

    function pad(value) {
        return String(value).padStart(2, "0");
    }

    function stackedTime() {
        const hours = date.getHours();
        const lines = [pad(SettingsData.use24HourClock ? hours : (hours % 12 || 12)), pad(date.getMinutes())];
        if (SettingsData.showSeconds)
            lines.push(pad(date.getSeconds()));
        if (!SettingsData.use24HourClock)
            lines.push(hours >= 12 ? locale.pmText : locale.amText);
        return lines;
    }

    function stackedDate() {
        const format = locale.dateFormat(Locale.ShortFormat);
        const day = pad(date.getDate());
        const month = pad(date.getMonth() + 1);
        return format.indexOf("d") < format.indexOf("M") ? [day, month] : [month, day];
    }

    component StackedLines: Column {
        id: stack

        property var lines: []
        property color color: root.textColor

        width: root.vertical ? root.availableWidth : implicitWidth

        Repeater {
            model: stack.lines.length

            NumericText {
                required property int index
                anchors.horizontalCenter: parent.horizontalCenter
                text: stack.lines[index]
                color: stack.color
                font.pixelSize: root.fontSize
            }
        }
    }

    Grid {
        id: layout

        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, layout.visibleChildren.length)
        spacing: root.vertical ? 0 : Theme.spacingS
        verticalItemAlignment: Grid.AlignVCenter

        Loader {
            sourceComponent: root.dateFirst && root.showDate || !root.showTime ? dateComponent : timeComponent
        }

        Item {
            id: separator
            visible: root.showTime && root.showDate
            width: root.vertical ? root.availableWidth : (root.split ? Theme.groupedListGap : dot.implicitWidth)
            height: root.vertical ? Theme.spacingM : root.fontSize

            Rectangle {
                visible: root.vertical
                anchors.centerIn: parent
                width: parent.width * 0.6
                height: 1
                color: root.separatorColor
            }

            StyledText {
                id: dot
                visible: !root.vertical && !root.split
                anchors.centerIn: parent
                text: "•"
                color: root.separatorColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Loader {
            active: root.showTime && root.showDate
            visible: active
            sourceComponent: root.dateFirst ? timeComponent : dateComponent
        }
    }

    Component {
        id: timeComponent

        StackedLines {
            lines: root.timeLines
        }
    }

    Component {
        id: dateComponent

        StackedLines {
            lines: root.dateLines
            color: root.dateColor
        }
    }

    SystemClock {
        id: systemClock
        enabled: root.live
        precision: SettingsData.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Connections {
        target: SessionService
        function onSessionResumed() {
            systemClock.enabled = false;
            systemClock.enabled = Qt.binding(() => root.live);
        }
    }
}
