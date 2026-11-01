pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash
import "../../../DCommon/Common/WheelInput.js" as WheelInput

Item {
    id: root

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    property bool daily: false
    property int startIndex: 0
    property int visibleCount: daily ? DashMetrics.dailyVisibleCount : DashMetrics.chartHourlyCount

    signal pageRequested(int delta)

    readonly property var source: (daily ? WeatherService.weather.forecast : WeatherService.weather.hourlyForecast) ?? []
    readonly property int maxStart: Math.max(0, source.length - visibleCount)
    readonly property int start: Math.max(0, Math.min(maxStart, startIndex))
    readonly property var slice: source.slice(start, start + visibleCount)
    readonly property var temps: slice.map(f => Number(daily ? f.tempMax : f.temp) || 0)
    readonly property var lows: daily ? slice.map(f => Number(f.tempMin) || 0) : []
    readonly property int nowIndex: (daily ? 0 : (WeatherService.weather.currentHourIndex ?? new Date().getHours())) - start
    readonly property real columnWidth: slice.length > 0 ? (width - Theme.spacingM * 2) / slice.length : 0
    readonly property real chartTop: Theme.spacingM + header.height + Theme.spacingS
    readonly property real chartBottom: height - Theme.spacingM - footer.height - Theme.spacingS

    function visualIndex(index) {
        return I18n.isRtl ? slice.length - 1 - index : index;
    }

    function step(delta) {
        const next = Math.max(0, Math.min(maxStart, start + delta));
        if (next === start)
            return false;
        startIndex = next;
        return true;
    }

    function labelFor(f, index) {
        if (daily)
            return WeatherService.formatForecastDay(f.rawDate || f.rawSunrise, start + index);
        if (!f.rawTime)
            return f.time ?? "--";
        return new Date(f.rawTime).toLocaleTimeString(I18n.locale(), SettingsData.use24HourClock ? "HH:mm" : "h AP");
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.slice.length === 0
        text: I18n.tr("Forecast Not Available")
        color: Theme.onSurfaceVariant
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            if (!WheelInput.isHorizontal(wheel) || root.maxStart === 0) {
                wheel.accepted = false;
                return;
            }
            const delta = WheelInput.dominantDelta(wheel.angleDelta);
            const step = delta > 0 ? -1 : 1;
            const next = root.start + step;
            if (delta !== 0 && next >= 0 && next <= root.maxStart)
                root.pageRequested(step);
            wheel.accepted = true;
        }
    }

    Rectangle {
        x: Theme.spacingM + root.visualIndex(root.nowIndex) * root.columnWidth
        y: Theme.spacingS
        width: root.columnWidth
        height: parent.height - Theme.spacingS * 2
        radius: Theme.cornerRadiusM
        color: Theme.withAlpha(Theme.primary, Theme.stateLayerHover)
        visible: root.nowIndex >= 0 && root.nowIndex < root.slice.length
    }

    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingM
        height: Theme.iconSize + Theme.fontSizeSmall * 2 + Theme.spacingXS * 2

        Repeater {
            model: root.slice

            Column {
                id: column

                required property var modelData
                required property int index

                readonly property bool current: index === root.nowIndex

                x: root.visualIndex(index) * root.columnWidth
                width: root.columnWidth
                spacing: Theme.spacingXXS

                StyledText {
                    width: parent.width
                    text: root.labelFor(column.modelData, column.index)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: column.current ? Theme.fontWeightBold : Theme.fontWeightMedium
                    color: column.current ? Theme.primary : Theme.onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                DIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: WeatherService.getWeatherIcon(column.modelData.wCode || 0, column.modelData.isDay ?? true)
                    size: Theme.iconSize
                    color: column.current ? Theme.primary : Theme.onSurfaceVariant
                }

                StyledText {
                    width: parent.width
                    text: WeatherService.formatTemp(root.daily ? column.modelData.tempMax : column.modelData.temp) ?? "--"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: column.current ? Theme.primary : Theme.surfaceText
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }

    DSparkline {
        x: Theme.spacingM + root.columnWidth / 2
        y: root.chartTop
        width: Math.max(0, root.width - Theme.spacingM * 2 - root.columnWidth)
        height: Math.max(0, root.chartBottom - root.chartTop)
        values: I18n.isRtl ? root.temps.slice().reverse() : root.temps
        secondaryValues: I18n.isRtl ? root.lows.slice().reverse() : root.lows
        autoRange: true
        showDots: true
        dotRadius: DashMetrics.chartDotRadius
        lineWidth: Theme.outlineWidthFocused
        lineColor: Theme.primary
        secondaryLineColor: Theme.tertiary
        fillOpacity: 0
        edgeExtension: root.columnWidth / 2
        insetTop: dotRadius * 2
        insetBottom: dotRadius * 2
    }

    Item {
        id: footer

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingM
        height: Theme.fontSizeSmall + Theme.spacingXS

        Repeater {
            model: root.slice

            Item {
                id: footerColumn
                required property var modelData
                required property int index

                x: root.visualIndex(index) * root.columnWidth
                width: root.columnWidth
                height: footer.height

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingXXS

                    DIcon {
                        visible: !root.daily
                        name: "rainy"
                        size: Theme.iconSizeSmall
                        color: Theme.onSurfaceVariant
                    }

                    StyledText {
                        text: root.daily ? (WeatherService.formatTemp(footerColumn.modelData.tempMin) ?? "--") : (WeatherService.formatPercent(footerColumn.modelData.precipitationProbability) ?? "--")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: footerColumn.index === root.nowIndex ? Theme.fontWeightBold : Theme.fontWeightMedium
                        color: footerColumn.index === root.nowIndex ? Theme.primary : Theme.onSurfaceVariant
                    }
                }
            }
        }
    }
}
