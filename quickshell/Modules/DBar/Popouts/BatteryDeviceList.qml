pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "../../../Common/BatteryDevices.js" as BatteryDevices
import "../../../DCommon/Common/Contrast.js" as Contrast

Item {
    id: root

    property var devices: []

    readonly property var items: Array.isArray(root.devices) ? root.devices : []
    readonly property int count: root.items.length
    readonly property string layoutName: SettingsData.batteryPopoutDevicesLayout
    readonly property string colorMode: SettingsData.batteryPopoutColor
    readonly property bool wavy: SettingsData.batteryPopoutWavy

    readonly property int fadeDuration: Theme.expressiveDurations.expressiveEffects
    readonly property int collapseDuration: Theme.expressiveDurations.expressiveSlowEffects

    // Off until the popout has laid out after opening, so nothing fades in on open.
    readonly property bool open: root.Window.window?.visible ?? false
    property bool settled: false
    readonly property bool animate: root.settled && !Theme.reduceMotion

    implicitHeight: body.implicitHeight
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    function settle() {
        root.settled = false;
        if (root.open)
            Qt.callLater(() => root.settled = root.open);
    }

    onOpenChanged: root.settle()
    Component.onCompleted: root.settle()

    function accent(device) {
        return BatteryService.colorFor(root.colorMode, device.percentage, device.charging, Theme.surfaceText);
    }

    function valueColor(device) {
        return device.low && (root.colorMode === "primary" || root.colorMode === "lowcharging") ? Theme.error : Theme.surfaceText;
    }

    function level(device) {
        return device.unknown ? 0 : device.percentage;
    }

    function percentText(device) {
        return device.unknown ? "–" : device.percentage + "%";
    }

    function accessibleName(device) {
        const state = device.charging ? ", " + I18n.tr("Charging", "device battery state") : device.low ? ", " + I18n.tr("Low Battery", "device battery state") : "";
        return device.name + ": " + root.percentText(device) + state;
    }

    function tileColumns(count) {
        return count <= 3 ? Math.max(1, count) : 2;
    }

    Loader {
        id: body
        width: root.width
        sourceComponent: root.count === 0 || root.layoutName === "bars" ? barsComp : root.layoutName === "compact" ? tilesComp : root.layoutName === "chips" ? chipsComp : root.layoutName === "list" ? rowsComp : gridComp
    }

    component LevelEase: NumberAnimation {
        duration: Theme.expressiveDurations.expressiveSlowEffects
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.expressiveSlowEffects
    }

    component DeviceGlyph: BatteryDeviceIcon {
        id: glyph

        required property var device
        required property color accent
        property bool badges: true

        iconName: glyph.device.icon
        color: glyph.accent
        badgeName: glyph.badges ? BatteryDevices.badgeFor(glyph.device) : ""
        cutWidth: BatteryPopoutMetrics.badgeCut
    }

    component LevelRing: Item {
        id: ring

        required property var device
        required property color accent
        required property color cut
        property real glyphSize: Theme.iconSize
        property real startAngle: -90
        property real spanAngle: 360

        DCircularWavyProgress {
            anchors.fill: parent
            anchors.margins: Theme.spacingXS
            progress: root.level(ring.device) / 100
            color: ring.accent
            strokeWidth: BatteryPopoutMetrics.gaugeStroke
            trackStrokeWidth: BatteryPopoutMetrics.gaugeStroke
            gapSize: BatteryPopoutMetrics.ringGap
            startAngle: ring.startAngle
            spanAngle: ring.spanAngle
            wavy: BatteryPopoutMetrics.waveOn(root.wavy, ring.device.charging, root.level(ring.device))
            waveSpeed: 0

            Behavior on progress {
                enabled: !Theme.reduceMotion
                LevelEase {}
            }
        }

        DeviceGlyph {
            anchors.centerIn: parent
            device: ring.device
            accent: ring.accent
            cutColor: ring.cut
            size: ring.glyphSize
        }
    }

    Component {
        id: gridComp

        DCard {
            id: gridCard

            readonly property int columns: Math.max(1, Math.min(root.count, BatteryPopoutMetrics.gridMaxColumns))

            implicitHeight: gridContent.implicitHeight + pad * 2
            pad: BatteryPopoutMetrics.pad
            restRadius: Theme.cornerRadiusL

            Grid {
                id: gridContent

                readonly property real cellWidth: (width - columnSpacing * (gridCard.columns - 1)) / gridCard.columns

                width: parent.width
                columns: gridCard.columns
                columnSpacing: Theme.spacingXS
                rowSpacing: Theme.spacingXS

                Repeater {
                    model: ScriptModel {
                        values: root.items
                        objectProp: "key"
                    }

                    delegate: Item {
                        id: cell

                        required property var modelData
                        readonly property color accent: root.accent(cell.modelData)

                        width: gridContent.cellWidth
                        implicitHeight: cellName.y + cellName.implicitHeight
                        Accessible.role: Accessible.StaticText
                        Accessible.name: root.accessibleName(cell.modelData)

                        LevelRing {
                            id: cellRing
                            x: (parent.width - width) / 2
                            width: BatteryPopoutMetrics.deviceRing
                            height: width
                            device: cell.modelData
                            accent: cell.accent
                            cut: gridCard.color
                            glyphSize: BatteryPopoutMetrics.gridGlyph
                            startAngle: 135
                            spanAngle: 270
                        }

                        StyledText {
                            id: cellLevel
                            x: (parent.width - width) / 2
                            y: cellRing.height - BatteryPopoutMetrics.numberLift
                            text: cell.modelData.unknown ? "–" : String(cell.modelData.percentage)
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            font.features: {
                                "tnum": 1
                            }
                            color: Theme.surfaceText
                        }

                        StyledText {
                            id: cellName
                            y: cellLevel.y + cellLevel.implicitHeight
                            width: parent.width
                            text: cell.modelData.name
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.onSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // Floored cells keep a spanning last tile inside the row.
    Component {
        id: tilesComp

        Flow {
            id: tiles

            readonly property int columns: root.tileColumns(root.count)
            readonly property real cellWidth: Math.floor((width - spacing * (columns - 1)) / columns)

            spacing: Theme.groupedListGap

            Repeater {
                model: ScriptModel {
                    values: root.items
                    objectProp: "key"
                }

                delegate: DCard {
                    id: tile

                    required property var modelData
                    required property int index
                    readonly property color accent: root.accent(tile.modelData)
                    readonly property int span: tile.index === root.count - 1 ? tiles.columns - tile.index % tiles.columns : 1
                    readonly property var radii: BatteryPopoutMetrics.cornerRadii(tile.index, root.count, tiles.columns, Theme.groupedListOuterRadius, Theme.groupedListOuterRadius)

                    width: tiles.cellWidth * tile.span + tiles.spacing * (tile.span - 1)
                    height: tileRow.implicitHeight + pad * 2
                    pad: BatteryPopoutMetrics.tile
                    restRadius: Theme.groupedListInnerRadius
                    topLeftRadius: tile.radii.topLeft
                    topRightRadius: tile.radii.topRight
                    bottomLeftRadius: tile.radii.bottomLeft
                    bottomRightRadius: tile.radii.bottomRight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: root.accessibleName(tile.modelData)

                    Row {
                        id: tileRow
                        width: parent.width
                        spacing: Theme.spacingM

                        LevelRing {
                            id: tileRing
                            anchors.verticalCenter: parent.verticalCenter
                            width: BatteryPopoutMetrics.compactRing
                            height: width
                            device: tile.modelData
                            accent: tile.accent
                            cut: tile.color
                            glyphSize: BatteryPopoutMetrics.compactGlyph
                        }

                        Column {
                            width: parent.width - tileRing.width - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                width: parent.width
                                text: root.percentText(tile.modelData)
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                font.features: {
                                    "tnum": 1
                                }
                                color: root.valueColor(tile.modelData)
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: tile.modelData.name
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.onSurfaceVariant
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: chipsComp

        Flow {
            id: chips

            spacing: Theme.spacingXS

            Repeater {
                model: ScriptModel {
                    values: root.items
                    objectProp: "key"
                }

                delegate: DDetailChip {
                    id: chip

                    required property var modelData
                    readonly property color accent: root.accent(chip.modelData)

                    implicitHeight: BatteryPopoutMetrics.chip
                    maximumWidth: chips.width
                    value: root.percentText(chip.modelData)
                    valueColor: root.valueColor(chip.modelData)
                    Accessible.name: root.accessibleName(chip.modelData)

                    leading: DeviceGlyph {
                        device: chip.modelData
                        accent: chip.accent
                        cutColor: chip.color
                        size: BatteryPopoutMetrics.compactGlyph
                    }
                }
            }
        }
    }

    Component {
        id: rowsComp

        Column {
            id: rows

            spacing: Theme.groupedListGap

            Repeater {
                model: ScriptModel {
                    values: root.items
                    objectProp: "key"
                }

                delegate: DCard {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property color accent: root.accent(row.modelData)
                    readonly property var radii: BatteryPopoutMetrics.cornerRadii(row.index, root.count, 1, Theme.groupedListOuterRadius, Theme.groupedListOuterRadius)
                    readonly property int levelValue: root.level(row.modelData)

                    width: rows.width
                    height: Math.max(BatteryPopoutMetrics.row, rowContent.implicitHeight + Theme.spacingXS * 2)
                    pad: Theme.spacingM
                    restRadius: Theme.groupedListInnerRadius
                    topLeftRadius: row.radii.topLeft
                    topRightRadius: row.radii.topRight
                    bottomLeftRadius: row.radii.bottomLeft
                    bottomRightRadius: row.radii.bottomRight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: root.accessibleName(row.modelData)

                    Row {
                        id: rowContent
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingM

                        DeviceGlyph {
                            id: rowGlyph
                            anchors.verticalCenter: parent.verticalCenter
                            device: row.modelData
                            accent: row.accent
                            cutColor: row.color
                        }

                        Column {
                            width: parent.width - rowPercent.implicitWidth - rowGlyph.implicitWidth - parent.spacing * 2
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                text: row.modelData.name
                                font.weight: Theme.fontWeightMedium
                                color: Theme.surfaceText
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }

                            M3WaveProgress {
                                width: parent.width
                                height: BatteryPopoutMetrics.barStroke + Theme.spacingS
                                value: row.levelValue / 100
                                lineWidth: BatteryPopoutMetrics.barStroke
                                wavelength: BatteryPopoutMetrics.wavelength
                                amp: BatteryPopoutMetrics.waveAmpThin
                                isPlaying: BatteryPopoutMetrics.waveOn(root.wavy, row.modelData.charging, row.levelValue)
                                fillColor: row.accent
                                trackColor: Theme.secondaryContainer
                                trackGap: BatteryPopoutMetrics.trackGap
                                roundEnds: true
                                showPlayhead: false
                                showStopDot: true
                                mirrored: I18n.isRtl

                                Behavior on value {
                                    enabled: !Theme.reduceMotion
                                    LevelEase {}
                                }
                            }
                        }

                        StyledText {
                            id: rowPercent
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.percentText(row.modelData)
                            font.weight: Theme.fontWeightMedium
                            font.features: {
                                "tnum": 1
                            }
                            color: root.valueColor(row.modelData)
                        }
                    }
                }
            }
        }
    }

    // Removed rows fade out before the list collapses; added rows fade in while it grows.
    Component {
        id: barsComp

        DCard {
            id: barsBox

            readonly property real targetHeight: pad * 2 + (root.count > 0 ? barList.contentHeight : BatteryPopoutMetrics.row)
            property real shownHeight: 0
            property bool shrinking: false

            implicitHeight: barsBox.shownHeight
            pad: Theme.spacingS
            restRadius: Theme.groupedListOuterRadius
            Component.onCompleted: barsBox.shownHeight = barsBox.targetHeight
            onTargetHeightChanged: {
                barsBox.shrinking = barsBox.targetHeight < barsBox.shownHeight;
                barsBox.shownHeight = barsBox.targetHeight;
            }

            // Growth is left to the popout's own resize, so the window is at its new size while added rows fade in.
            Behavior on shownHeight {
                enabled: root.animate && barsBox.shrinking
                SequentialAnimation {
                    PauseAnimation {
                        duration: root.fadeDuration
                    }
                    LevelEase {
                        duration: root.collapseDuration
                    }
                }
            }

            Item {
                width: parent.width
                height: BatteryPopoutMetrics.row
                visible: root.count === 0
                opacity: root.count === 0 ? 1 : 0
                Accessible.role: Accessible.StaticText
                Accessible.name: emptyText.text

                Behavior on opacity {
                    enabled: root.animate
                    SequentialAnimation {
                        PauseAnimation {
                            duration: root.fadeDuration + root.collapseDuration
                        }
                        NumberAnimation {
                            duration: root.fadeDuration
                        }
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "devices_off"
                        size: Theme.iconSizeSmall
                        color: Theme.onSurfaceVariant
                    }

                    StyledText {
                        id: emptyText
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("No devices", "battery popout: no connected peripherals")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                    }
                }
            }

            DListView {
                id: barList

                // A removed row only fades while it is still inside the view, so the view keeps the old height until the collapse.
                width: parent.width
                height: Math.max(barList.contentHeight, barsBox.shownHeight - barsBox.pad * 2)
                interactive: false
                wheelEnabled: false
                showScrollBar: false
                fadeEdges: false
                rowFadeEnabled: false
                spacing: Theme.spacingXS

                model: ScriptModel {
                    values: root.items
                    objectProp: "key"
                }

                add: Transition {
                    enabled: root.animate
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: root.fadeDuration
                    }
                }

                remove: Transition {
                    enabled: root.animate
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: root.fadeDuration
                    }
                }

                // Opacity is restored here too, or a row displaced mid fade-in stays translucent.
                addDisplaced: Transition {
                    enabled: root.animate
                    LevelEase {
                        property: "y"
                        duration: root.collapseDuration
                    }
                    NumberAnimation {
                        property: "opacity"
                        to: 1
                        duration: root.fadeDuration
                    }
                }

                removeDisplaced: Transition {
                    enabled: root.animate
                    SequentialAnimation {
                        PauseAnimation {
                            duration: root.fadeDuration
                        }
                        LevelEase {
                            property: "y"
                            duration: root.collapseDuration
                        }
                    }
                    NumberAnimation {
                        property: "opacity"
                        to: 1
                        duration: root.fadeDuration
                    }
                }

                delegate: Rectangle {
                    id: bar

                    required property var modelData
                    readonly property color accent: root.accent(bar.modelData)
                    readonly property color track: Theme.secondaryContainer
                    readonly property color fill: Contrast.mix(bar.track, bar.accent, BatteryPopoutMetrics.barFillMix)
                    readonly property color ink: Contrast.readableOnAll([bar.fill, bar.track], [Theme.surfaceText, Theme.surface])
                    readonly property real inset: (bar.height - Theme.iconSize) / 2
                    property real shown: root.level(bar.modelData)

                    width: barList.width
                    height: BatteryPopoutMetrics.row
                    radius: bar.height / 2
                    color: bar.track
                    Accessible.role: Accessible.StaticText
                    Accessible.name: root.accessibleName(bar.modelData)

                    Behavior on shown {
                        enabled: !Theme.reduceMotion
                        LevelEase {}
                    }

                    // Never narrower than a circle, so a low device still shows its level behind the icon.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        visible: bar.shown > 0
                        width: Math.max(bar.height, bar.width * bar.shown / 100)
                        radius: bar.radius
                        color: bar.fill
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: bar.inset
                        anchors.rightMargin: bar.inset
                        spacing: Theme.spacingM

                        DeviceGlyph {
                            device: bar.modelData
                            accent: bar.ink
                            badges: false
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: bar.modelData.name
                            font.weight: Theme.fontWeightMedium
                            color: bar.ink
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: root.percentText(bar.modelData)
                            font.weight: Theme.fontWeightMedium
                            font.features: {
                                "tnum": 1
                            }
                            color: bar.ink
                        }

                        Rectangle {
                            visible: bar.modelData.charging
                            Layout.preferredWidth: BatteryPopoutMetrics.boltCircle
                            Layout.preferredHeight: BatteryPopoutMetrics.boltCircle
                            radius: width / 2
                            color: bar.accent

                            DIcon {
                                anchors.centerIn: parent
                                name: "bolt"
                                size: Theme.iconSizeSmall
                                filled: true
                                color: Contrast.readableOn(bar.accent, [Theme.surface, Theme.surfaceText])
                            }
                        }
                    }
                }
            }
        }
    }
}
