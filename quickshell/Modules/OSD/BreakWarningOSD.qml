pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DOSD {
    id: root

    readonly property string label: {
        const lead = I18n.duration(BreakReminderService.warningSeconds);
        if (BreakReminderService.kind === "long")
            return I18n.tr("Long break in %1", "break reminder heads-up, %1 is a duration like 5 seconds").arg(lead);
        return I18n.tr("Short break in %1", "break reminder heads-up, %1 is a duration like 5 seconds").arg(lead);
    }
    readonly property real horizontalPadding: Theme.spacingL
    readonly property real itemSpacing: Theme.spacingM
    readonly property real labelWidth: Theme.pxCeil(labelMeasurer.implicitWidth, dpr)

    osdKind: "breakReminder"
    osdWidth: Math.min(screenWidth - Theme.spacingM * 2, Theme.pxCeil(horizontalPadding * 2 + Theme.buttonHeightS * 3 + itemSpacing * 2 + Theme.spacingXS + labelWidth + 1, dpr))
    osdHeight: Theme.osdHeight
    autoHideInterval: Math.max(1, BreakReminderService.warningSeconds) * 1000
    enableMouseInteraction: true

    Connections {
        target: BreakReminderService

        function onWarningShown() {
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
        wrapMode: Text.NoWrap
        text: root.label
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
