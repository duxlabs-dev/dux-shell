pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Common as DCommon
import qs.DCommon.Widgets
import qs.Widgets

DOSD {
    id: root

    property int remainingSeconds: Math.max(1, BreakReminderService.warningSeconds)
    readonly property string label: formatLabel(remainingSeconds)
    readonly property real horizontalPadding: Theme.spacingL
    readonly property real itemSpacing: Theme.spacingM
    readonly property real labelWidth: {
        const maxSeconds = Math.max(1, BreakReminderService.warningSeconds);
        let widest = 0;
        for (let s = 1; s <= maxSeconds; s++)
            widest = Math.max(widest, DCommon.Fonts.textWidth(labelMeasurer.font, formatLabel(s)));
        return Theme.pxCeil(widest, dpr);
    }

    function formatLabel(seconds) {
        const lead = I18n.duration(seconds);
        if (BreakReminderService.kind === "long")
            return I18n.tr("Long break in %1", "break reminder heads-up, %1 is a duration like 5 seconds").arg(lead);
        return I18n.tr("Short break in %1", "break reminder heads-up, %1 is a duration like 5 seconds").arg(lead);
    }

    function updateRemaining() {
        remainingSeconds = Math.max(1, Math.ceil((BreakReminderService.warningEndsAt - Date.now()) / 1000));
    }

    osdKind: "breakReminder"
    osdWidth: Math.min(screenWidth - Theme.spacingM * 2, Theme.pxCeil(horizontalPadding * 2 + Theme.buttonHeightS * 3 + itemSpacing * 2 + Theme.spacingXS + labelWidth + 1, dpr))
    osdHeight: Theme.osdHeight
    autoHideInterval: Math.max(1, BreakReminderService.warningSeconds) * 1000
    enableMouseInteraction: true

    Timer {
        interval: 250
        repeat: true
        running: root.shouldBeVisible && root.remainingSeconds > 1
        onTriggered: root.updateRemaining()
    }

    Connections {
        target: BreakReminderService

        function onWarningShown() {
            root.updateRemaining();
            root.show();
        }

        function onWarningDismissed() {
            if (root.shouldBeVisible)
                root.hide();
        }
    }

    StyledText {
        id: labelMeasurer
        visible: false
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        font.features: {
            "tnum": 1
        }
    }

    content: Item {
        anchors.fill: parent

        RowLayout {
            anchors {
                fill: parent
                leftMargin: root.horizontalPadding
                rightMargin: root.horizontalPadding
            }
            spacing: root.itemSpacing

            OsdIcon {
                Layout.alignment: Qt.AlignVCenter
                iconName: "self_improvement"
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                font.features: {
                    "tnum": 1
                }
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.spacingXS

                OsdIcon {
                    interactive: true
                    tonal: false
                    iconName: "snooze"
                    iconColor: Theme.surfaceVariantText
                    label: I18n.tr("Snooze", "break reminder action, delay the break by a few minutes")
                    onHoveredChanged: root.setChildHovered(hovered)
                    onClicked: {
                        BreakReminderService.snooze();
                        root.hide();
                    }
                }

                OsdIcon {
                    interactive: true
                    tonal: false
                    iconName: "skip_next"
                    iconColor: Theme.surfaceVariantText
                    label: I18n.tr("Skip")
                    onHoveredChanged: root.setChildHovered(hovered)
                    onClicked: {
                        BreakReminderService.skip();
                        root.hide();
                    }
                }
            }
        }
    }
}
