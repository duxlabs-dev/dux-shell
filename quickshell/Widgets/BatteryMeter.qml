pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    property real thickness: 14
    property bool vertical: false
    property bool showNumber: true
    property bool showBolt: true
    property string meterStyle: "solid"
    property bool levelColors: false
    property real maxDiameter: 0
    property bool hovered: false
    property color colorOverride: "transparent"

    readonly property bool outlined: root.meterStyle === "outline"
    readonly property bool ring: root.meterStyle === "ring"
    // Duo: an open arc around the network glyph, signal dots in the gap.
    readonly property bool duo: root.meterStyle === "duo"
    readonly property bool circular: root.ring || root.duo
    readonly property real arcStart: root.duo ? 150 : -90
    readonly property real arcSpan: root.duo ? 240 : 360
    readonly property real chargeTarget: SettingsData.batteryScaleToChargeLimit ? 100 : Math.max(root.level, Math.min(100, SettingsData.batteryChargeLimit))
    readonly property real unit: root.thickness / 14
    readonly property real level: Math.max(0, Math.min(100, BatteryService.displayBatteryLevel))
    readonly property bool charging: BatteryService.batteryAvailable && BatteryService.isCharging
    readonly property bool lowState: BatteryService.batteryAvailable && BatteryService.isLowBattery && !BatteryService.isCharging
    readonly property color fillColor: {
        if (root.colorOverride.a > 0)
            return root.colorOverride;
        if (!BatteryService.batteryAvailable)
            return Theme.surfaceVariant;
        if (root.levelColors)
            return BatteryService.levelColor;
        if (root.lowState)
            return Theme.error;
        return Theme.isLightColor(Theme.primary) === Theme.isLightColor(Theme.surface) ? Theme.surfaceText : Theme.primary;
    }
    readonly property color dimColor: Theme.withAlpha(root.fillColor, root.hovered ? 0.6 : 0.48)
    readonly property color trackColor: {
        if (root.duo)
            return Theme.withAlpha(root.fillColor, root.hovered ? 0.3 : 0.16);
        if (root.ring)
            return Theme.withAlpha(root.fillColor, root.hovered ? 0.4 : 0.26);
        if (root.outlined)
            return root.hovered ? Theme.withAlpha(Theme.surfaceVariant, 0.45) : "transparent";
        return root.dimColor;
    }
    readonly property color inkColor: {
        if (Theme.isLightColor(root.fillColor))
            return Theme.isLightColor(Theme.surface) ? Theme.surfaceText : Theme.surface;
        return Theme.isLightColor(Theme.surface) ? Theme.surface : Theme.surfaceText;
    }
    readonly property int glyphWeight: Theme.fontWeight
    readonly property string numberText: Math.round(root.level).toString()
    readonly property bool boltVisible: root.charging && root.showBolt && !root.duo
    readonly property bool numberInside: !root.vertical && root.showNumber && BatteryService.batteryAvailable
    readonly property bool ringNumberVisible: root.ring && root.showNumber && !root.boltVisible && BatteryService.batteryAvailable
    readonly property real strokeWidth: root.outlined ? 1.5 * root.unit : 0
    readonly property real textCanvasLeft: 1.5 * root.unit
    readonly property real textCanvasWidth: root.bodyLength - root.textCanvasLeft - 1.5 * root.unit
    readonly property real textNeed: fitMetrics.advanceWidth
    property real fontSize: Theme.fontSizeSmall
    readonly property real baseTextSize: root.fontSize
    readonly property real ringDiameter: {
        const natural = Math.round(19 * root.unit);
        if (root.maxDiameter <= 0)
            return natural;
        return Math.min(natural, Math.round(root.maxDiameter));
    }
    readonly property real ringStroke: Math.max(1, Math.round(root.ringDiameter * 2 / 19))
    readonly property real ringRadius: (root.ringDiameter - root.ringStroke) / 2
    readonly property real ringInnerRadius: Math.max(1, (root.ringDiameter - 2 * root.ringStroke) / 2)
    readonly property real ringChordWidth: 2 * Math.sqrt(Math.max(1, Math.pow(root.ringInnerRadius, 2) - Math.pow(fitMetrics.tightBoundingRect.height / 2, 2)))
    readonly property real ringTextSize: root.textNeed > 0 ? Math.min(root.baseTextSize, root.baseTextSize * root.ringChordWidth / root.textNeed) : root.baseTextSize
    readonly property real textSize: root.circular ? root.ringTextSize : root.baseTextSize
    readonly property real textBaseline: root.height / 2 - digitInk.tightBoundingRect.y - digitInk.tightBoundingRect.height / 2
    readonly property real boltBadgeSize: Math.round((root.circular ? 12 : 9) * root.unit)
    readonly property real boltBadgeWidth: Math.round(root.boltBadgeSize * (8 / 13))
    readonly property real bodyLength: Math.max(Math.round(25 * root.unit), Math.ceil(root.numberInside ? root.textNeed + root.textCanvasLeft + 1.5 * root.unit : 0))
    readonly property real capGap: Math.max(1, Math.round(root.unit))
    readonly property real capOffset: root.bodyLength + root.capGap
    readonly property real capBreadth: Math.max(1, Math.round(1.25 * root.unit))
    readonly property real capSpan: Math.round(6 * root.unit)

    implicitWidth: root.circular ? root.ringDiameter : root.vertical ? Math.round(14 * root.unit) : root.capOffset + (root.boltVisible ? root.boltBadgeWidth : root.capBreadth)
    implicitHeight: root.circular ? root.ringDiameter : root.vertical ? root.capOffset + root.capBreadth : Math.round(14 * root.unit)

    StyledTextMetrics {
        id: fitMetrics

        font.weight: root.glyphWeight
        font.pixelSize: Math.max(1, root.baseTextSize)
        text: root.numberText.replace(/\d/g, Fonts.widestDigit(fitMetrics.font))
    }

    StyledTextMetrics {
        id: digitInk

        font.weight: root.glyphWeight
        font.pixelSize: Math.max(1, root.textSize)
        text: "0"
    }

    component Bolt: Shape {
        id: bolt

        property color fillColor

        width: root.boltBadgeWidth
        height: root.boltBadgeSize
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: bolt.fillColor
            strokeColor: "transparent"
            startX: bolt.width * (1 / 3)
            startY: bolt.height
            PathLine {
                x: bolt.width * (1 / 3)
                y: bolt.height * (7.5 / 13)
            }
            PathLine {
                x: 0
                y: bolt.height * (7.5 / 13)
            }
            PathLine {
                x: bolt.width * (2 / 3)
                y: 0
            }
            PathLine {
                x: bolt.width * (2 / 3)
                y: bolt.height * (5.5 / 13)
            }
            PathLine {
                x: bolt.width
                y: bolt.height * (5.5 / 13)
            }
            PathLine {
                x: bolt.width * (1 / 3)
                y: bolt.height
            }
        }
    }

    Component {
        id: ringGauge

        Shape {
            id: gauge

            property real sweep: root.level / 100 * root.arcSpan

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            Behavior on sweep {
                NumberAnimation {
                    duration: Theme.mediumDuration
                    easing.type: Theme.standardEasing
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.trackColor
                strokeWidth: root.ringStroke
                capStyle: ShapePath.FlatCap

                PathAngleArc {
                    centerX: root.ringDiameter / 2
                    centerY: root.ringDiameter / 2
                    radiusX: root.ringRadius
                    radiusY: root.ringRadius
                    startAngle: root.arcStart
                    sweepAngle: root.arcSpan
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.duo && root.charging ? Theme.withAlpha(root.fillColor, 0.45) : "transparent"
                strokeWidth: root.ringStroke
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: root.ringDiameter / 2
                    centerY: root.ringDiameter / 2
                    radiusX: root.ringRadius
                    radiusY: root.ringRadius
                    startAngle: root.arcStart + gauge.sweep
                    sweepAngle: Math.max(0, (root.chargeTarget - root.level) / 100 * root.arcSpan)
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.level > 0 ? root.fillColor : "transparent"
                strokeWidth: root.ringStroke
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: root.ringDiameter / 2
                    centerY: root.ringDiameter / 2
                    radiusX: root.ringRadius
                    radiusY: root.ringRadius
                    startAngle: root.arcStart
                    sweepAngle: gauge.sweep
                }
            }
        }
    }

    Loader {
        active: root.circular
        anchors.centerIn: parent
        width: root.ringDiameter
        height: root.ringDiameter
        sourceComponent: ringGauge
    }

    Loader {
        active: root.duo
        anchors.centerIn: parent
        width: root.ringDiameter
        height: root.ringDiameter
        sourceComponent: duoFace
    }

    Component {
        id: duoFace

        Item {
            id: face

            readonly property string networkIcon: {
                if (NetworkService.wifiToggling)
                    return "sync";
                switch (NetworkService.networkStatus) {
                case "ethernet":
                    return "lan";
                case "cellular":
                    return "network_cell";
                case "vpn":
                    return NetworkService.ethernetConnected ? "lan" : (NetworkService.cellularConnected ? "network_cell" : NetworkService.wifiSignalIcon);
                }
                return NetworkService.wifiEnabled && NetworkService.wifiAvailable ? NetworkService.wifiSignalIcon : "wifi_off";
            }
            // Inner pair first so a partial signal stays symmetric.
            readonly property int litDots: NetworkService.wifiConnected ? (NetworkService.wifiSignalStrength > 50 ? 4 : 2) : 0
            readonly property real dotSize: Math.max(2, Math.round(root.ringStroke * 1.25))
            readonly property int glyphInset: Math.round(root.ringDiameter * 0.2)

            DIcon {
                id: glyph

                x: face.glyphInset
                y: face.glyphInset
                name: face.networkIcon
                size: root.ringDiameter - 2 * face.glyphInset
                color: NetworkService.networkStatus !== "disconnected" ? Theme.surfaceText : Theme.surfaceTextMedium

                DBlink {
                    target: glyph
                    running: face.visible && (NetworkService.wifiToggling || NetworkService.isWifiConnecting)
                }
            }

            Repeater {
                model: 4

                Rectangle {
                    id: dot

                    required property int index
                    readonly property real angle: (54 + dot.index * 24) * Math.PI / 180
                    readonly property bool lit: dot.index === 1 || dot.index === 2 ? face.litDots >= 2 : face.litDots >= 4

                    x: root.ringDiameter / 2 + Math.cos(dot.angle) * root.ringRadius - width / 2
                    y: root.ringDiameter / 2 + Math.sin(dot.angle) * root.ringRadius - height / 2
                    width: face.dotSize
                    height: face.dotSize
                    radius: width / 2
                    color: dot.lit ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.16)
                }
            }
        }
    }

    NumericText {
        visible: root.ringNumberVisible
        x: (root.width - width) / 2
        y: root.textBaseline - baselineOffset
        text: root.numberText
        color: Theme.surfaceText
        font.weight: root.glyphWeight
        font.pixelSize: Math.max(1, root.textSize)
    }

    Rectangle {
        id: cap

        x: root.vertical ? (root.width - root.capSpan) / 2 : root.capOffset
        y: root.vertical ? 0 : (root.height - root.capSpan) / 2
        width: root.vertical ? root.capSpan : root.capBreadth
        height: root.vertical ? root.capBreadth : root.capSpan
        radius: root.capBreadth / 2
        visible: !root.circular && (root.vertical || !root.boltVisible)
        color: root.outlined ? root.fillColor : root.dimColor
    }

    Rectangle {
        id: frame

        x: 0
        y: root.vertical ? root.height - root.bodyLength : 0
        width: root.vertical ? root.width : root.bodyLength
        height: root.vertical ? root.bodyLength : root.height
        radius: 4 * root.unit
        visible: !root.circular
        color: root.trackColor
        border.width: root.strokeWidth
        border.color: root.fillColor
    }

    ClippingRectangle {
        id: interior

        x: frame.x + root.strokeWidth
        y: frame.y + root.strokeWidth
        width: frame.width - root.strokeWidth * 2
        height: frame.height - root.strokeWidth * 2
        radius: Math.max(0, frame.radius - root.strokeWidth)
        visible: !root.circular
        color: "transparent"

        Rectangle {
            id: fill

            x: 0
            y: root.vertical ? parent.height - height : 0
            width: root.vertical ? parent.width : Math.round(parent.width * root.level / 100)
            height: root.vertical ? Math.round(parent.height * root.level / 100) : parent.height
            color: root.outlined ? Theme.withAlpha(root.fillColor, 0.32) : root.fillColor

            Behavior on width {
                enabled: !root.vertical
                NumberAnimation {
                    duration: Theme.mediumDuration
                    easing.type: Theme.standardEasing
                }
            }

            Behavior on height {
                enabled: root.vertical
                NumberAnimation {
                    duration: Theme.mediumDuration
                    easing.type: Theme.standardEasing
                }
            }
        }
    }

    component Glyphs: Item {
        id: glyphs

        property color ink

        width: root.width
        height: root.height

        NumericText {
            visible: root.numberInside
            x: root.textCanvasLeft + (root.textCanvasWidth - width) / 2
            y: root.textBaseline - baselineOffset
            text: root.numberText
            color: glyphs.ink
            font.weight: root.glyphWeight
            font.pixelSize: Math.max(1, root.textSize)
        }
    }

    Glyphs {
        visible: root.numberInside && !root.circular
        ink: Theme.surfaceText
    }

    Item {
        x: interior.x + fill.x
        y: interior.y + fill.y
        width: fill.width
        height: fill.height
        clip: true
        visible: root.numberInside && !root.outlined && !root.circular

        Glyphs {
            x: -parent.x
            y: -parent.y
            ink: root.inkColor
        }
    }

    Bolt {
        visible: root.boltVisible
        x: root.circular || root.vertical ? (root.width - width) / 2 : root.capOffset
        y: !root.circular && root.vertical ? frame.y + (frame.height - height) / 2 : (root.height - height) / 2
        fillColor: Theme.surfaceText
    }
}
