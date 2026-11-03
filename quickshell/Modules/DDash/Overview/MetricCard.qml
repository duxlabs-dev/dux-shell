import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash

Card {
    id: root

    clipContent: true

    property bool live: Window.window?.visible ?? false
    property var dgopModules: []
    property bool dgopRefHeld: false
    property string label: ""
    property string iconName: "monitoring"
    property string valueText: "--"
    property string supportingText: ""
    property string badgeText: ""
    property string badgeIcon: "device_thermostat"
    property real usage: -1
    property real warnUsage: DashMetrics.cpuWarnPercent / 100
    property real criticalUsage: DashMetrics.cpuCriticalPercent / 100
    property var trend: []
    property var secondaryTrend: []
    property real trendMaximum: 100
    property bool showTrend: true

    readonly property bool wide: width >= DashMetrics.gridRowUnit * 2
    readonly property bool tall: height >= DashMetrics.gridRowUnit * 2
    readonly property bool hero: wide && tall
    readonly property bool compact: !wide && !tall
    readonly property bool trendVisible: showTrend && trend.length > 1 && !compact
    readonly property bool hasBadge: badgeText !== ""
    readonly property real gaugeSize: hero ? DashMetrics.gaugeSizeHero : DashMetrics.gaugeSize
    readonly property real gaugeIconSize: hero ? Theme.iconSize : (compact ? Theme.iconSizeSmall : Theme.iconSizeMedium)
    readonly property color levelColor: {
        if (usage >= criticalUsage)
            return Theme.error;
        if (usage >= warnUsage)
            return Theme.warning;
        return accentColor;
    }

    tone: options.tone ?? ""
    pad: Theme.spacingM

    function syncDgopRef(wanted) {
        if (wanted === dgopRefHeld || dgopModules.length === 0)
            return;
        dgopRefHeld = wanted;
        if (wanted) {
            DgopService.addRef(dgopModules);
            return;
        }
        DgopService.removeRef(dgopModules);
    }

    onLiveChanged: syncDgopRef(live)
    Component.onCompleted: syncDgopRef(live)
    Component.onDestruction: syncDgopRef(false)

    component MetricBadge: Row {
        spacing: Theme.spacingXXS

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.badgeIcon
            size: Theme.iconSizeSmall
            color: root.mutedColor
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.badgeText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
        }
    }

    DSparkline {
        anchors.left: root.wide ? valueText.right : parent.left
        anchors.leftMargin: root.wide ? Theme.spacingM : -root.pad
        anchors.right: parent.right
        anchors.rightMargin: root.wide ? 0 : -root.pad
        y: root.wide ? parent.height + root.pad - height : (narrowBadge.visible ? narrowBadge.y + narrowBadge.height : header.height) + Theme.spacingS
        height: root.wide ? root.height * DashMetrics.tileTrendRatio : Math.max(0, valueText.y - Theme.spacingXS - y)
        visible: root.trendVisible
        values: root.trend
        secondaryValues: root.secondaryTrend
        maximum: root.trendMaximum
        insetBottom: root.wide ? root.pad : lineWidth
        lineColor: root.accentColor
        secondaryLineColor: root.tinted ? root.mutedColor : Theme.tertiary
        lineWidth: Theme.outlineWidthFocused
        fillOpacity: DashMetrics.tileTrendFillAlpha
    }

    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: gauge.height

        MetricGauge {
            id: gauge

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.gaugeSize
            height: root.gaugeSize
            usage: root.usage
            iconName: root.iconName
            iconSize: root.gaugeIconSize
            iconColor: root.accentColor
            ringColor: root.levelColor
            trackColor: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)
            discColor: root.chipColor
        }

        StyledText {
            anchors.left: gauge.right
            anchors.leftMargin: Theme.spacingS
            anchors.right: headerBadge.visible ? headerBadge.left : parent.right
            anchors.rightMargin: headerBadge.visible ? Theme.spacingS : 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.pixelSize: root.hero ? Theme.fontSizeLarge : Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
            elide: Text.ElideRight
        }

        MetricBadge {
            id: headerBadge

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasBadge && root.wide
        }
    }

    MetricBadge {
        id: narrowBadge

        anchors.left: parent.left
        anchors.top: header.bottom
        anchors.topMargin: Theme.spacingXS
        visible: root.hasBadge && root.tall && !root.wide
    }

    StyledText {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Theme.spacingXS
        text: root.supportingText
        font.pixelSize: Theme.fontSizeSmall
        color: root.mutedColor
        elide: Text.ElideRight
        visible: root.hero && text !== ""
    }

    TextMetrics {
        id: valueMetrics

        font: valueText.font
        text: root.valueText
    }

    StyledText {
        id: valueText

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: root.wide ? Math.min(Math.ceil(valueMetrics.advanceWidth), parent.width) : parent.width
        wrapMode: Text.NoWrap
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: Theme.fontSizeLarge
        text: root.valueText
        font.pixelSize: root.hero ? Theme.fontSizeDisplay : (root.compact ? DashMetrics.tileValueSizeCompact : Theme.fontSizeXXLarge)
        font.weight: Theme.fontWeightMedium
        color: root.contentColor
        elide: Text.ElideRight
    }
}
