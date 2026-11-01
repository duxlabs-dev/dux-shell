import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import "../../../Common/Format.js" as Format

BasePill {
    id: root

    property var widgetData: null

    readonly property bool hideWhenIdle: SettingsData.widgetOption("network_speed_monitor", widgetData, "hideWhenIdle")
    readonly property bool compactMode: SettingsData.widgetOption("network_speed_monitor", widgetData, "compactMode")
    readonly property bool shouldHide: hideWhenIdle && widgetData?.enabled !== false && Math.max(DgopService.networkRxRate, DgopService.networkTxRate) < 1024
    readonly property string reserveRate: compactMode ? "888 MB/s" : "88.8 MB/s"

    width: shouldHide ? 0 : (isVerticalOrientation ? barThickness : visualWidth)
    height: shouldHide ? 0 : (isVerticalOrientation ? visualHeight : barThickness)
    visible: !shouldHide
    opacity: shouldHide ? 0 : 1

    Behavior on width {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    function horizontalRate(rate) {
        if (compactMode)
            return Format.formatRateCompact(rate, false);
        return rate > 0 ? Format.formatRate(rate, 1) : "0 B/s";
    }

    function verticalRate(rate) {
        if (compactMode)
            return Format.formatRateCompact(rate, true);
        if (rate < 1024)
            return rate.toFixed(0);
        if (rate < 1024 * 1024)
            return (rate / 1024).toFixed(0) + "K";
        return (rate / (1024 * 1024)).toFixed(0) + "M";
    }

    Ref {
        service: DgopService
        modules: ["network"]
        active: (root.shouldHide || (root.visible && root.enabled)) && (root.Window.window?.visible ?? false)
    }

    content: Component {
        Item {
            implicitWidth: root.isVerticalOrientation ? root.contentThickness : contentRow.implicitWidth
            implicitHeight: root.isVerticalOrientation ? contentColumn.implicitHeight : root.contentThickness

            Column {
                id: contentColumn
                anchors.centerIn: parent
                spacing: Theme.spacingXXS
                visible: root.isVerticalOrientation

                DIcon {
                    name: "network_check"
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: Theme.widgetIconColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                NumericText {
                    text: root.verticalRate(DgopService.networkRxRate)
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: Theme.info
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                NumericText {
                    text: root.verticalRate(DgopService.networkTxRate)
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: Theme.error
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Row {
                id: contentRow
                anchors.centerIn: parent
                spacing: Theme.spacingS
                visible: !root.isVerticalOrientation

                DIcon {
                    name: "network_check"
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: Theme.widgetIconColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "↓"
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: Theme.info
                    }

                    NumericText {
                        text: root.horizontalRate(DgopService.networkRxRate)
                        reserveText: root.reserveRate
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: root.contentColor
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideNone
                    }
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "↑"
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: Theme.error
                    }

                    NumericText {
                        text: root.horizontalRate(DgopService.networkTxRate)
                        reserveText: root.reserveRate
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: root.contentColor
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideNone
                    }
                }
            }
        }
    }
}
