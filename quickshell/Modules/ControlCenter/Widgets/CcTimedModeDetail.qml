pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.DCommon.Widgets
import "../../../Common/Format.js" as Format

Item {
    id: root

    property string title: ""
    property bool active: false
    property real untilMs: 0
    property string iconName: ""
    property string toggleText: ""
    property string offDescription: ""
    property var presets: []
    default property alias extraContent: column.data

    signal toggled(bool checked)
    signal presetSelected(var preset)

    property real nowMs: Date.now()

    implicitHeight: column.height

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Timer {
        interval: CcMetrics.dndRefreshInterval
        repeat: true
        running: root.visible && root.active && root.untilMs > 0
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
    }

    function formatRemaining(ms) {
        return Format.formatRemaining(ms, "", I18n.tr("%1 min left", "time remaining on a timed mode, %1 is minutes"), I18n.tr("%1 h left", "time remaining on a timed mode, %1 is hours"), I18n.tr("%1 h %2 m left", "time remaining on a timed mode, %1 is hours, %2 is minutes"));
    }

    DFlickable {
        anchors.fill: parent
        contentHeight: column.height
        clip: true

        Column {
            id: column
            width: parent.width
            spacing: CcMetrics.detailContentGap

            CcGroup {
                CcToggleRow {
                    iconName: root.iconName
                    iconColor: root.active ? Theme.primary : Theme.surfaceText
                    text: root.toggleText
                    description: {
                        if (!root.active)
                            return root.offDescription;
                        if (root.untilMs <= 0)
                            return I18n.tr("On indefinitely");
                        const remaining = Math.max(0, root.untilMs - root.nowMs);
                        return root.formatRemaining(remaining) + " · " + I18n.tr("until %1", "lowercase, follows the remaining time after a separator, %1 is a clock time").arg(Format.formatUntil(root.untilMs, SettingsData.use24HourClock));
                    }
                    checked: root.active
                    onToggled: checked => root.toggled(checked)
                }
            }

            CcGroup {
                Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: root.presets

                        DButton {
                            required property var modelData

                            buttonHeight: Theme.buttonHeightXS
                            iconName: modelData.icon || ""
                            iconSize: Theme.iconSizeSmall
                            text: modelData.label
                            backgroundColor: Theme.chipSurface
                            textColor: Theme.surfaceText
                            onClicked: root.presetSelected(modelData)
                        }
                    }
                }
            }
        }
    }
}
