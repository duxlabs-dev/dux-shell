import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash

DashCardComponent {
    id: root

    readonly property string period: options.period ?? "day"
    readonly property var span: spanFor(clock.date, period)
    readonly property real progress: Math.max(0, Math.min(1, (clock.date - span.start) / (span.end - span.start)))
    readonly property bool wide: width >= DashMetrics.gridRowUnit * 2
    readonly property bool tall: height >= DashMetrics.gridRowUnit * 2
    readonly property string periodText: {
        switch (period) {
        case "week":
            return I18n.trFor("dashCardExample", "This week");
        case "month":
            return I18n.trFor("dashCardExample", "This month");
        case "year":
            return I18n.trFor("dashCardExample", "This year");
        }
        return I18n.trFor("dashCardExample", "Today");
    }
    readonly property string remainingText: {
        const minutes = Math.ceil((span.end - clock.date) / 60000);
        if (minutes < 60)
            return I18n.trFor("dashCardExample", "%1 min left").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 48)
            return I18n.trFor("dashCardExample", "%1 h left").arg(hours);
        return I18n.trFor("dashCardExample", "%1 days left").arg(Math.floor(hours / 24));
    }

    tone: options.tone ?? ""

    function weekStart() {
        const setting = SettingsData.firstDayOfWeek;
        return (setting >= 0 && setting < 7 ? setting : Qt.locale().firstDayOfWeek) % 7;
    }

    function spanFor(now, period) {
        const year = now.getFullYear();
        const month = now.getMonth();
        const day = now.getDate();
        switch (period) {
        case "week":
            {
                const first = day - (now.getDay() - weekStart() + 7) % 7;
                return {
                    start: new Date(year, month, first),
                    end: new Date(year, month, first + 7)
                };
            }
        case "month":
            return {
                start: new Date(year, month, 1),
                end: new Date(year, month + 1, 1)
            };
        case "year":
            return {
                start: new Date(year, 0, 1),
                end: new Date(year + 1, 0, 1)
            };
        }
        return {
            start: new Date(year, month, day),
            end: new Date(year, month, day + 1)
        };
    }

    SystemClock {
        id: clock
        enabled: root.live
        precision: SystemClock.Minutes
    }

    StyledText {
        id: label
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        text: root.periodText
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: root.mutedColor
        elide: Text.ElideRight
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        NumericText {
            isMonospace: false
            text: Math.floor(root.progress * 100) + "%"
            font.pixelSize: root.tall ? Theme.fontSizeDisplay : root.wide ? Theme.fontSizeXXLarge : Theme.fontSizeXLarge
            font.weight: Theme.fontWeightMedium
            color: root.accentColor
        }

        StyledText {
            width: parent.width
            visible: root.options.remaining !== false && (root.wide || root.tall)
            text: root.remainingText
            font.pixelSize: Theme.fontSizeSmall
            color: root.mutedColor
            elide: Text.ElideRight
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.spacingS
        radius: height / 2
        color: root.chipColor

        Rectangle {
            width: Math.max(height, parent.width * root.progress)
            height: parent.height
            radius: height / 2
            color: root.accentColor
        }
    }
}
