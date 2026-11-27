import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.ProcessList
import qs.Modules.Sysmon

Grid {
    id: root

    property var value: ({})
    property string style: "icon"
    property bool vertical: false
    property string labelText: ""
    property real iconSize: Theme.iconSize
    property real textSize: Theme.fontSizeSmall
    // The number's size; a vertical pill shares one fitted size across its values.
    property real numberSize: textSize
    // A vertical pill's content may use its whole thickness.
    property real thickness: 0
    property real dpr: 1
    property color color: Theme.widgetIconColor
    property color textColor: Theme.widgetTextColor

    readonly property color tone: value.muted ? Theme.surfaceVariantText : value.level >= 2 ? Theme.tempDanger : value.level === 1 ? Theme.tempWarning : color
    readonly property bool glyph: style !== "icon" && !value.plain
    readonly property real fraction: value.fraction ?? 0
    readonly property real glyphHeight: iconSize - Theme.spacingXXS
    readonly property real ringSize: Math.min(iconSize + Theme.spacingXXS, thickness)
    readonly property real labelRatio: 0.875
    readonly property real labelRatioVertical: 0.75
    readonly property real labelMaxEms: 10
    readonly property real ringStrokeRatio: 1 / 8
    readonly property real graphWidthRatio: 2
    readonly property real meterWidthRatioVertical: 2 / 3
    readonly property real labelSize: Math.round(textSize * (vertical ? labelRatioVertical : labelRatio))
    readonly property real labelMaxWidth: textSize * labelMaxEms
    readonly property real meterWidthVertical: Math.round(iconSize * meterWidthRatioVertical)
    readonly property real meterFillMix: 0.5
    readonly property color meterTrack: Theme.withAlpha(tone, Theme.stateLayerFocus)
    readonly property color meterFill: Theme.blend(tone, Theme.surface, meterFillMix)
    readonly property string meterReserve: root.value.reserve ?? ""
    readonly property color numberColor: {
        if (value.muted)
            return Theme.surfaceVariantText;
        if (vertical && value.dir)
            return value.dir === "down" ? Theme.info : Theme.error;
        return textColor;
    }

    columns: vertical ? 1 : children.length
    spacing: vertical ? Theme.hairline(dpr) : Theme.spacingXS
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
    Accessible.ignored: true

    DeviceIcon {
        visible: !!root.value.icon && !(root.glyph && root.style === "ring")
        name: root.value.icon ?? ""
        size: root.value.main ? root.iconSize : root.iconSize - Theme.spacingXS
        color: root.value.main || root.value.level > 0 ? root.tone : Theme.surfaceVariantText
    }

    StyledText {
        visible: root.labelText !== ""
        width: Math.min(Math.ceil(implicitWidth), root.vertical ? root.thickness - Theme.spacingXS : root.labelMaxWidth)
        text: root.labelText
        font.pixelSize: root.labelSize
        font.weight: Theme.fontWeightMedium
        color: root.value.muted ? Theme.surfaceVariantText : root.color
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        horizontalAlignment: Text.AlignHCenter
    }

    DRingGauge {
        id: ring
        visible: root.glyph && root.style === "ring"
        // The ring is drawn edge to edge; the side inset matches the built-in margin of an icon glyph.
        width: root.ringSize + (root.vertical ? 0 : 2 * Theme.spacingXXS)
        height: root.ringSize
        value: root.fraction
        strokeWidth: Math.max(Theme.spacingXXS, root.ringSize * root.ringStrokeRatio)
        trackGap: Theme.spacingXS
        ringColor: root.tone
        trackColor: Theme.withAlpha(root.tone, Theme.tonalTintAlpha)
        // Hidden glyphs still get every sample; animating them would keep the bar redrawing.
        animated: MonitorMetrics.animationsEnabled && visible
        animationDuration: MonitorMetrics.meterDuration

        DeviceIcon {
            anchors.centerIn: parent
            visible: !!root.value.icon
            name: root.value.icon ?? ""
            size: Math.round(ring.innerSize - Theme.spacingXS)
            color: root.tone
        }
    }

    Rectangle {
        id: graph
        visible: root.glyph && root.style === "graph"
        width: root.vertical ? Math.min(root.iconSize + Theme.spacingXS, root.thickness) : root.iconSize * root.graphWidthRatio
        height: root.vertical ? root.iconSize - Theme.spacingXS : root.glyphHeight
        radius: Theme.cornerRadiusXS
        color: Theme.withAlpha(root.tone, Theme.stateLayerFocus)
        clip: true

        DSparkline {
            anchors.fill: parent
            anchors.leftMargin: graph.radius
            anchors.rightMargin: graph.radius
            values: parent.visible ? (root.value.history ?? []) : []
            historyLength: values.length
            maximum: root.value.maximum ?? 0
            lineColor: root.tone
            lineWidth: Theme.outlineWidthFocused
        }
    }

    StyledText {
        visible: !root.vertical && !!root.value.dir
        text: root.value.dir === "down" ? "↓" : "↑"
        font.pixelSize: root.textSize
        color: root.value.dir === "down" ? Theme.info : Theme.error
    }

    Rectangle {
        id: meterH
        visible: root.glyph && root.style === "meter" && !root.vertical
        width: meterText.width + Theme.spacingXS * 2
        height: root.glyphHeight
        radius: Theme.cornerRadiusXS
        color: root.meterTrack

        // A fill shorter than the corner radius is cut from a full-radius bar, so its start stays rounded.
        Item {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // Whole device pixels keep the fill edge crisp.
            width: Theme.snap(meterH.width * root.fraction, root.dpr)
            clip: true

            MeterBehavior on width {
                enabled: MonitorMetrics.animationsEnabled && meterH.visible
            }

            Rectangle {
                readonly property real endRadius: Math.max(0, meterH.radius - (meterH.width - parent.width))
                readonly property bool rtl: LayoutMirroring.enabled

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(parent.width, 2 * meterH.radius)
                topLeftRadius: rtl ? endRadius : meterH.radius
                bottomLeftRadius: topLeftRadius
                topRightRadius: rtl ? meterH.radius : endRadius
                bottomRightRadius: topRightRadius
                color: root.meterFill
            }
        }

        NumericText {
            id: meterText
            anchors.centerIn: parent
            width: reservedWidth
            text: root.value.text ?? ""
            reserveText: root.meterReserve
            font.pixelSize: root.textSize
            font.weight: Theme.fontWeightBold
            color: root.textColor
        }
    }

    Rectangle {
        id: meterV
        visible: root.glyph && root.style === "meter" && root.vertical
        width: root.meterWidthVertical
        height: root.iconSize + Theme.spacingXXS
        radius: Theme.cornerRadiusXS
        color: root.meterTrack

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.snap(meterV.height * root.fraction, root.dpr)
            clip: true

            MeterBehavior on height {
                enabled: MonitorMetrics.animationsEnabled && meterV.visible
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(parent.height, 2 * meterV.radius)
                bottomLeftRadius: meterV.radius
                bottomRightRadius: meterV.radius
                topLeftRadius: Math.max(0, meterV.radius - (meterV.height - parent.height))
                topRightRadius: topLeftRadius
                color: root.tone
            }
        }
    }

    NumericText {
        visible: !(root.glyph && root.style === "meter" && !root.vertical)
        width: root.vertical ? root.thickness : reservedWidth
        text: (root.vertical ? root.value.vtext : root.value.text) ?? ""
        reserveText: root.vertical ? "" : root.value.reserve ?? ""
        // A rate sits against its arrow; the reserved slack goes after it.
        horizontalAlignment: !root.vertical && root.value.dir ? Text.AlignLeft : Text.AlignHCenter
        font.pixelSize: root.vertical ? root.value.vsize ?? root.numberSize : root.numberSize
        color: root.numberColor
    }
}
