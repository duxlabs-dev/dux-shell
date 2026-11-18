pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Common as DCommon
import qs.DCommon.Widgets
import qs.Modules.DDash.Overview
import qs.Modules.ProcessList
import qs.Modules.Sysmon

Item {
    id: root

    property var row: ({})
    property string style: "classic"
    property string size: "sm"
    property bool solo: false
    property color accentColor: Theme.primary
    property color tileColor: Theme.surfaceContainer
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property bool halo: false
    property real radius: Theme.cornerRadiusL

    readonly property real pad: Theme.spacingM
    readonly property bool sm: size === "sm"
    readonly property bool wide: !sm
    readonly property bool big: size === "big"
    readonly property bool tall: big || (solo && height >= MonitorMetrics.wideThreshold)
    readonly property bool compact: sm && !tall
    readonly property bool asleep: row.asleep === true
    readonly property bool missing: row.missing === true
    readonly property var main: row.values?.[0] ?? null
    readonly property var extras: asleep ? [] : (row.values ?? []).slice(1)
    readonly property real fraction: asleep || missing ? 0 : Math.min(Math.max(main?.fraction ?? 0, 0), 1)
    readonly property color levelColor: MonitorMetrics.levelColor(main?.level, accentColor)
    readonly property string valueText: asleep ? I18n.tr("Idle", "device state") : missing ? "—" : (main?.text ?? "—")
    readonly property string shortValueText: missing ? "—" : (main?.shortText ?? valueText)
    readonly property var trend: missing || asleep ? ({}) : (row.trend ?? {})
    readonly property bool hasTrend: (trend.values?.length ?? 0) > 1
    readonly property real extrasLineHeight: Math.max(Theme.iconSizeSmall, extrasProbe.implicitHeight)
    readonly property real valueSize: big ? Theme.fontSizeDisplay : compact && solo ? MonitorMetrics.tileValueSizeCompact : Theme.fontSizeXXLarge

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true
    Accessible.role: Accessible.StaticText
    Accessible.name: (row.name ?? "") + " " + valueText

    component Glyph: Loader {
        property bool gauge: false

        sourceComponent: gauge ? gaugeGlyph : iconGlyph
    }

    Component {
        id: gaugeGlyph

        MetricGauge {
            width: root.big ? MonitorMetrics.gaugeSizeHero : MonitorMetrics.gaugeSize
            height: width
            usage: root.missing ? -1 : root.fraction
            ringColor: root.levelColor
            trackColor: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)
            discColor: Theme.foregroundColor(Theme.chipSurface, false)

            DeviceIcon {
                anchors.centerIn: parent
                name: root.row.icon ?? ""
                size: root.big ? Theme.iconSize : root.compact ? Theme.iconSizeSmall : Theme.iconSizeMedium
                color: root.accentColor
            }
        }
    }

    Component {
        id: iconGlyph

        DeviceIcon {
            name: root.row.icon ?? ""
            size: Theme.iconSizeMedium
            color: root.levelColor
        }
    }

    StyledText {
        id: extrasProbe
        visible: false
        text: "0"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
    }

    // Measured on each kind's widest sample, so the choice holds while values change.
    function fitExtras(values, available) {
        const font = extrasProbe.font;
        const digit = DCommon.Fonts.widestDigit(font);
        const widths = short => values.map(v => Theme.iconSizeSmall + Theme.spacingXXS + Math.ceil(DCommon.Fonts.textWidth(font, (MonitorMetrics.reserveFor(v?.kind ?? "", short) || (short ? v?.shortText : "") || v?.text || "—").replace(/\d/g, digit))));
        const total = list => list.reduce((sum, w) => sum + w, 0) + Theme.spacingS * Math.max(0, list.length - 1);
        if (total(widths(false)) <= available)
            return {
                "count": values.length,
                "short": false
            };
        const short = widths(true);
        let count = short.length;
        while (count > 0 && total(short.slice(0, count)) > available)
            count--;
        return {
            "count": count,
            "short": true
        };
    }

    component Extras: Row {
        id: extrasHost

        property var values: root.extras
        property real available: parent?.width ?? 0
        readonly property var fit: root.fitExtras(values, available)

        spacing: Theme.spacingS

        Repeater {
            model: extrasHost.visible ? extrasHost.fit.count : 0

            Row {
                id: extra

                required property int index
                readonly property var modelData: extrasHost.values[index] ?? ({})
                readonly property bool flagged: (modelData.level ?? 0) > 0

                spacing: Theme.spacingXXS

                DeviceIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: extra.modelData.icon ?? ""
                    size: Theme.iconSizeSmall
                    color: extra.flagged ? MonitorMetrics.levelColor(extra.modelData?.level, root.accentColor) : root.mutedColor
                }

                MonitorText {
                    halo: root.halo
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.missing ? "—" : ((extrasHost.fit.short ? extra.modelData.shortText : undefined) ?? extra.modelData.text ?? "—")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: extra.flagged ? MonitorMetrics.levelColor(extra.modelData?.level, root.accentColor) : root.contentColor
                }
            }
        }
    }

    component Header: Item {
        property bool gauge: false
        property bool showBadge: false
        property var badgeValues: root.extras

        anchors.left: parent.left
        anchors.right: parent.right
        height: glyph.height

        Glyph {
            id: glyph

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            gauge: parent.gauge
        }

        MonitorText {
            halo: root.halo
            anchors.left: glyph.right
            anchors.leftMargin: Theme.spacingS
            anchors.right: badge.visible ? badge.left : parent.right
            anchors.rightMargin: badge.visible ? Theme.spacingS : 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.row.name ?? ""
            Accessible.ignored: true
            font.pixelSize: root.big && parent.gauge ? Theme.fontSizeLarge : Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
        }

        Extras {
            id: badge

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            values: parent.badgeValues
            available: parent.width - glyph.width - Theme.spacingS * 2
            visible: parent.showBadge && fit.count > 0
        }
    }

    component Value: MonitorText {
        halo: root.halo
        Accessible.ignored: true
        wrapMode: Text.NoWrap
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: Theme.fontSizeLarge
        text: root.valueText
        font.pixelSize: root.valueSize
        font.weight: Theme.fontWeightMedium
        color: root.contentColor
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
    }

    component Trend: MetricChart {
        values: root.trend.values ?? []
        secondaryValues: root.trend.secondaryValues ?? []
        historyLength: values.length
        maximum: root.trend.maximum ?? 0
        color: root.levelColor
        secondaryColor: root.mutedColor
        curved: true
        grid: false
        gridColor: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)
        fillOpacity: MonitorMetrics.tileTrendFillAlpha
        insetBottom: Theme.outlineWidthFocused
    }

    component Meter: Item {
        id: meterBar

        property real fraction: root.fraction
        property color color: root.levelColor
        property real thickness: MonitorMetrics.meterThickness

        readonly property real gap: fraction > 0 && fraction < 1 ? Theme.spacingXS : 0
        readonly property real active: width * shown

        property real shown: fraction

        width: parent.width
        height: thickness

        MeterBehavior on shown {}

        Rectangle {
            anchors.left: parent.left
            width: parent.active
            height: parent.height
            radius: Theme.fullRadius(width, height)
            color: parent.color
            visible: width > 0
        }

        Rectangle {
            id: track

            anchors.right: parent.right
            width: Math.max(0, parent.width - parent.active - parent.gap)
            height: parent.height
            radius: Theme.fullRadius(width, height)
            color: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)
            visible: width > 0

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: (parent.height - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.spacingXS
                height: width
                radius: width / 2
                color: meterBar.color
                visible: track.width >= track.height
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.tileColor
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        Loader {
            anchors.fill: parent
            anchors.margins: root.pad
            sourceComponent: {
                if (root.asleep)
                    return idleBody;
                switch (root.style) {
                case "meter":
                    return meterBody;
                case "ring":
                    return root.big ? ringBigBody : root.wide ? ringWideBody : ringSmallBody;
                case "graph":
                    return graphBody;
                }
                return stackBody;
            }
        }
    }

    Component {
        id: idleBody

        Item {
            Header {
                gauge: root.style === "classic"
            }

            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                spacing: Theme.spacingXS

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "bedtime"
                    size: Theme.iconSize
                    color: root.mutedColor
                }

                MonitorText {
                    halo: root.halo
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.valueText
                    Accessible.ignored: true
                    font.pixelSize: Theme.fontSizeXLarge
                    font.weight: Theme.fontWeightMedium
                    color: root.mutedColor
                }
            }
        }
    }

    // Classic and Icon: in small tiles of a grid the value sits under the name, elsewhere at the bottom.
    Component {
        id: stackBody

        Item {
            id: stack

            readonly property bool valueOnTop: root.sm && !root.solo
            readonly property bool showTrend: !!root.row.graph && root.hasTrend && (root.wide || root.tall || !root.solo)

            Header {
                id: header

                gauge: root.style === "classic"
                showBadge: root.wide
            }

            Extras {
                id: upperExtras

                anchors.left: parent.left
                y: header.height + Theme.spacingXS
                visible: root.sm && root.solo && root.extras.length > 0 && (root.tall || y + root.extrasLineHeight + Theme.spacingXS <= value.y)
            }

            MonitorText {
                halo: root.halo
                anchors.left: parent.left
                anchors.right: parent.right
                y: header.height + Theme.spacingXS
                text: root.row.detail ?? ""
                font.pixelSize: Theme.fontSizeSmall
                color: root.mutedColor
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
                visible: root.big && text !== ""
            }

            TextMetrics {
                id: valueMetrics

                font: value.font
                text: root.valueText
            }

            Value {
                id: value

                anchors.left: parent.left
                y: stack.valueOnTop ? header.height + Theme.spacingXS : parent.height - height
                width: root.wide ? Math.min(Math.ceil(valueMetrics.advanceWidth), stack.showTrend ? parent.width * (1 - MonitorMetrics.tileTrendRatio) - Theme.spacingM : parent.width) : parent.width
            }

            Extras {
                id: lowerExtras

                anchors.left: parent.left
                y: value.y + value.height + Theme.spacingXXS
                visible: stack.valueOnTop && root.extras.length > 0
            }

            Trend {
                readonly property real startY: stack.valueOnTop ? (lowerExtras.visible ? lowerExtras.y + lowerExtras.height : value.y + value.height) + Theme.spacingS : (upperExtras.visible ? upperExtras.y + upperExtras.height : header.height) + Theme.spacingS

                visible: stack.showTrend
                anchors.left: root.wide ? value.right : parent.left
                anchors.leftMargin: root.wide ? Theme.spacingM : -root.pad
                anchors.right: parent.right
                anchors.rightMargin: root.wide ? 0 : -root.pad
                y: root.wide ? parent.height + root.pad - height : startY
                height: root.wide ? root.height * MonitorMetrics.tileTrendRatio : Math.max(0, (stack.valueOnTop ? parent.height + root.pad : value.y - Theme.spacingXS) - startY)
                insetBottom: root.wide ? root.pad : Theme.outlineWidthFocused
            }
        }
    }

    // Wide tiles give the first extra its own meter and badge the rest; without room the badge takes all, small tiles drop them.
    Component {
        id: meterBody

        Item {
            id: meter

            readonly property real room: height - header.height - Theme.spacingS - value.height - mainMeter.height - column.spacing
            readonly property bool extraMeter: root.wide && root.extras.length > 0 && room >= (extraLabel.height + MonitorMetrics.barThicknessExtra + column.spacing * 2)
            readonly property bool extrasLine: root.sm && root.extras.length > 0 && room >= root.extrasLineHeight + column.spacing

            Header {
                id: header

                showBadge: root.wide
                badgeValues: meter.extraMeter ? root.extras.slice(1) : root.extras
            }

            Column {
                id: column

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: Theme.spacingS

                Extras {
                    id: extrasRow

                    visible: meter.extrasLine
                }

                Value {
                    id: value

                    width: parent.width
                }

                Meter {
                    id: mainMeter

                    thickness: root.big ? MonitorMetrics.meterThicknessBig : MonitorMetrics.meterThickness
                }

                Item {
                    width: parent.width
                    height: extraLabel.height
                    visible: meter.extraMeter

                    MonitorText {
                        id: extraLabel
                        halo: root.halo

                        anchors.left: parent.left
                        anchors.right: extraValue.left
                        anchors.rightMargin: Theme.spacingS
                        text: root.extras[0]?.label ?? ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.mutedColor
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideRight
                    }

                    MonitorText {
                        id: extraValue
                        halo: root.halo

                        anchors.right: parent.right
                        text: root.missing ? "—" : (root.extras[0]?.text ?? "—")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: root.contentColor
                    }
                }

                Meter {
                    visible: meter.extraMeter
                    fraction: root.missing ? 0 : Math.min(Math.max(root.extras[0]?.fraction ?? 0, 0), 1)
                    color: MonitorMetrics.levelColor(root.extras[0]?.level, root.accentColor)
                    thickness: MonitorMetrics.barThicknessExtra
                }
            }
        }
    }

    component Ring: DRingGauge {
        property real token: MonitorMetrics.ringSizeSmall
        property real room: token
        readonly property real textWidth: innerSize - strokeWidth * 2

        width: Math.min(token, room)
        height: width
        value: root.fraction
        trackGap: Theme.spacingXS
        ringColor: root.levelColor
        trackColor: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)
        animated: MonitorMetrics.animationsEnabled
        animationDuration: MonitorMetrics.meterDuration
    }

    component RingValue: MonitorText {
        Accessible.ignored: true
        halo: root.halo
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.NoWrap
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: root.contentColor
    }

    Component {
        id: ringSmallBody

        Item {
            Column {
                id: column

                anchors.centerIn: parent
                width: parent.width
                spacing: Theme.spacingXS

                Ring {
                    id: ring

                    anchors.horizontalCenter: parent.horizontalCenter
                    strokeWidth: MonitorMetrics.ringStrokeSmall
                    room: Math.min(column.width, column.parent.height - name.height - column.spacing - (extrasRow.visible ? extrasRow.height + column.spacing : 0))

                    Column {
                        anchors.centerIn: parent
                        width: parent.width

                        DeviceIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: root.row.icon ?? ""
                            size: Theme.iconSizeSmall
                            color: root.levelColor
                        }

                        RingValue {
                            width: ring.textWidth
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.shortValueText
                            font.pixelSize: Theme.fontSizeLarge
                        }
                    }
                }

                MonitorText {
                    id: name
                    halo: root.halo

                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.row.name ?? ""
                    Accessible.ignored: true
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: root.mutedColor
                    elide: Text.ElideRight
                }

                Extras {
                    id: extrasRow

                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.extras.length > 0 && column.parent.height - MonitorMetrics.ringSizeSmall - name.height - column.spacing * 2 >= root.extrasLineHeight
                }
            }
        }
    }

    Component {
        id: ringWideBody

        Item {
            Ring {
                id: ring

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                token: MonitorMetrics.ringSizeWide
                room: parent.height
                strokeWidth: MonitorMetrics.ringStrokeWide

                RingValue {
                    width: ring.textWidth
                    anchors.centerIn: parent
                    text: root.shortValueText
                    font.pixelSize: Theme.fontSizeXLarge
                }
            }

            Column {
                anchors.left: ring.right
                anchors.leftMargin: Theme.spacingL
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                MonitorText {
                    halo: root.halo
                    width: parent.width
                    text: root.row.name ?? ""
                    Accessible.ignored: true
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: root.contentColor
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                }

                Extras {
                    visible: root.extras.length > 0
                }

                MonitorText {
                    halo: root.halo
                    width: parent.width
                    text: root.main?.label ?? ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.mutedColor
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }
        }
    }

    Component {
        id: ringBigBody

        Item {
            Header {
                id: header

                showBadge: true
            }

            Ring {
                id: ring

                anchors.horizontalCenter: parent.horizontalCenter
                y: header.height + (parent.height - header.height - height) / 2
                token: MonitorMetrics.ringSizeBig
                room: Math.min(parent.width, parent.height - header.height - Theme.spacingS * 2)
                strokeWidth: MonitorMetrics.ringStrokeBig

                Column {
                    anchors.centerIn: parent
                    width: parent.width

                    RingValue {
                        width: ring.textWidth
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.valueText
                        font.pixelSize: Theme.fontSizeDisplay
                    }

                    MonitorText {
                        halo: root.halo
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.main?.label ?? ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.mutedColor
                    }
                }
            }
        }
    }

    Component {
        id: graphBody

        Item {
            id: graph

            readonly property var extra: root.extras[0] ?? null
            readonly property bool extraLine: root.big && (extra?.history?.length ?? 0) > 1 && extra.maximum === root.trend.maximum

            Header {
                id: header

                showBadge: root.wide
            }

            Value {
                id: value

                anchors.left: parent.left
                y: header.height + Theme.spacingXS
                width: parent.width
            }

            Extras {
                id: extrasRow

                anchors.left: parent.left
                y: value.y + value.height + Theme.spacingXXS
                visible: root.sm && root.extras.length > 0
            }

            Trend {
                readonly property real textBottom: (extrasRow.visible ? extrasRow.y + extrasRow.height : value.y + value.height) + Theme.spacingS

                visible: root.hasTrend
                anchors.left: parent.left
                anchors.leftMargin: -root.pad
                anchors.right: parent.right
                anchors.rightMargin: -root.pad
                y: root.sm ? textBottom : Math.max(textBottom, root.height / 2 - root.pad)
                height: Math.max(0, parent.height + root.pad - y)
                secondaryValues: graph.extraLine ? graph.extra.history : (root.trend.secondaryValues ?? [])
                fillOpacity: Theme.tonalTintAlpha
                grid: root.big
            }
        }
    }
}
