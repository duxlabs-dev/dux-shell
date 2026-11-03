import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash

Card {
    id: root

    property bool live: Window.window?.visible ?? false

    readonly property bool showSeconds: options.seconds === true
    readonly property bool showDate: options.date === true
    readonly property string hourText: {
        const hours = systemClock.date.getHours();
        if (SettingsData.use24HourClock)
            return String(hours).padStart(2, "0");
        const display = hours % 12 === 0 ? 12 : hours % 12;
        return String(display).padStart(2, "0");
    }
    readonly property string minuteText: String(systemClock.date.getMinutes()).padStart(2, "0")
    readonly property string secondText: String(systemClock.date.getSeconds()).padStart(2, "0")
    readonly property string dateText: showDate ? systemClock.date.toLocaleDateString(I18n.locale(), SettingsData.getEffectiveDateFormat("ddd, MMM d")) : ""
    readonly property color supportingColor: tinted ? contentColor : mutedColor
    readonly property real supportLine: Theme.fontSizeMedium * 1.5

    entryId: "clock"
    tone: options.tone ?? ""
    pad: Theme.spacingL

    Loader {
        anchors.fill: parent
        sourceComponent: root.options.style === "analog" ? analogFace : digitalFace
    }

    Component {
        id: digitalFace

        DClockFace {
            hours: root.hourText
            minutes: root.minuteText
            seconds: root.showSeconds ? root.secondText : ""
            dateText: root.dateText
            weight: root.options.weight
            color: root.accentColor
            supportingColor: root.supportingColor
        }
    }

    Component {
        id: analogFace

        Item {
            id: face

            readonly property real span: Math.min(width, height)
            readonly property bool insideDate: root.dateText !== "" && span > Theme.buttonHeightM * 2 && dialMetrics.advanceWidth <= span * 0.5
            readonly property bool sideDate: root.dateText !== "" && !insideDate && width - height >= dateMetrics.advanceWidth + Theme.spacingS
            readonly property bool belowDate: root.dateText !== "" && !insideDate && !sideDate
            readonly property real dialSize: belowDate ? Math.min(width, height - root.supportLine - Theme.spacingS) : span
            readonly property real groupWidth: sideDate ? dialSize + Theme.spacingS + dateMetrics.advanceWidth : dialSize
            readonly property real groupHeight: belowDate ? dialSize + Theme.spacingS + root.supportLine : dialSize

            DAnalogClock {
                id: dial
                x: (face.width - face.groupWidth) / 2
                y: (face.height - face.groupHeight) / 2
                width: face.dialSize
                height: face.dialSize
                hours: systemClock.date.getHours()
                minutes: systemClock.date.getMinutes()
                seconds: systemClock.date.getSeconds()
                showSeconds: root.showSeconds
                showNumbers: root.options.numbers === true
                numbersOutside: root.tinted
                dateText: face.insideDate ? root.dateText : ""
                color: root.tinted ? root.onAccentColor : root.accentColor
                numberColor: root.accentColor
                backgroundColor: root.tinted ? root.accentColor : root.chipColor
                facePadding: 0
            }

            StyledText {
                id: dateLabel
                visible: face.sideDate || face.belowDate
                x: face.sideDate ? dial.x + dial.width + Theme.spacingS : 0
                y: face.sideDate ? (face.height - height) / 2 : dial.y + dial.height + Theme.spacingS
                width: face.sideDate ? dateMetrics.advanceWidth : face.width
                height: root.supportLine
                text: root.dateText
                color: root.supportingColor
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                minimumPixelSize: Theme.fontSizeSmall
                fontSizeMode: Text.HorizontalFit
                horizontalAlignment: face.sideDate ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            TextMetrics {
                id: dateMetrics
                font: dateLabel.font
                text: root.dateText
            }

            TextMetrics {
                id: dialMetrics
                font.family: dateLabel.font.family
                font.pixelSize: Theme.fontSizeSmall
                text: root.dateText
            }
        }
    }

    SystemClock {
        id: systemClock
        enabled: root.live
        precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            if (!root.live)
                return;
            systemClock.enabled = false;
            systemClock.enabled = true;
        }
    }
}
