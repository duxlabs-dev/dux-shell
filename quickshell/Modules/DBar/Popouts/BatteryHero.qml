pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Common
import qs.DCommon.Widgets
import "../../../DCommon/Common/Contrast.js" as Contrast

Item {
    id: root

    // level is the unscaled reading; percentage drives the fill and number
    property var source: ({})
    property var facts: []
    property bool factsBeside: false
    property bool showEdit: true
    property Component footer: null
    property bool active: false
    property real topRadius: Theme.cornerRadiusL
    property real bottomRadius: Theme.cornerRadiusL

    signal settingsRequested
    signal editRequested

    readonly property string style: SettingsData.batteryPopoutStyle
    readonly property bool wavy: SettingsData.batteryPopoutWavy
    readonly property bool compact: BatteryPopoutMetrics.compact
    readonly property bool unknown: root.source.unknown ?? false
    readonly property real percentage: root.unknown ? 0 : Math.max(0, Math.min(100, root.source.percentage ?? 0))
    readonly property real value: root.unknown ? -1 : root.percentage
    readonly property bool charging: root.source.charging ?? false
    readonly property real limit: root.source.limit ?? 100
    // At or above the limit the gauges show the plain level.
    readonly property bool limited: root.limit > 0 && root.limit < 100 && root.level < root.limit
    readonly property bool towardLimit: root.charging && root.limited
    readonly property string status: root.towardLimit ? I18n.tr("Charging to %1", "battery popout title while charging toward the charge limit, %1 is the limit like 80%").arg(Math.round(root.limit) + "%") : (root.source.status ?? "")
    readonly property string time: root.source.time ?? ""
    readonly property string timeLine: [root.time, root.source.rate ?? ""].filter(part => part !== "").join(" · ")

    readonly property string colorMode: SettingsData.batteryPopoutColor
    readonly property real level: root.unknown ? 0 : Math.max(0, Math.min(100, root.source.level ?? root.source.percentage ?? 0))
    readonly property color accent: BatteryService.colorFor(root.colorMode, root.level, root.charging, Theme.surfaceText, root.source.pluggedIn ?? false)
    readonly property bool lowTone: (root.colorMode === "primary" || root.colorMode === "lowcharging") && root.accent === Theme.error
    readonly property color badgeFill: root.lowTone ? Theme.errorContainer : root.colorMode === "theme" ? Theme.surfaceContainerHighest : Theme.primaryContainer
    readonly property color badgeInk: root.lowTone ? Theme.onErrorContainer : root.colorMode === "theme" ? Theme.surfaceText : Theme.onPrimaryContainer
    readonly property string badgeKind: SettingsData.batteryPopoutBadge === "ring" ? "ring" : "shape"
    readonly property bool waveOn: BatteryPopoutMetrics.waveOn(root.wavy, root.charging, root.level)

    property real shownValue: Math.max(0, root.value)

    function pastLimit(color) {
        return Contrast.mix(color, Theme.scrimColor, BatteryPopoutMetrics.pastLimitShade);
    }

    implicitHeight: body.height
    Accessible.role: Accessible.ProgressBar
    Accessible.name: [root.status, root.value >= 0 ? Math.round(root.value) + "%" : "–"].filter(part => part !== "").join(": ")
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Behavior on shownValue {
        enabled: !Theme.reduceMotion
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveSlowEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveSlowEffects
        }
    }

    component HeroCard: DCard {
        pad: BatteryPopoutMetrics.pad
        restRadius: Theme.cornerRadiusL
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
    }

    component HeroNumber: Item {
        id: number

        property real value: -1
        property real pixelSize: Theme.fontSizeDisplayLarge
        property color color: Theme.primary

        implicitWidth: digits.implicitWidth + (unit.visible ? unit.implicitWidth : 0)
        implicitHeight: number.pixelSize

        StyledText {
            id: digits
            Accessible.ignored: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: number.value >= 0 ? Math.round(number.value).toString() : "–"
            font.pixelSize: number.pixelSize
            font.weight: Theme.fontWeightMedium
            font.features: {
                "tnum": 1
            }
            color: number.color
        }

        StyledText {
            id: unit
            Accessible.ignored: true
            anchors.left: digits.right
            anchors.baseline: digits.baseline
            visible: number.value >= 0
            text: "%"
            font.pixelSize: Math.round(number.pixelSize / 2)
            font.weight: Theme.fontWeight
            color: number.color
        }
    }

    component HeroText: Column {
        id: label

        property string status
        property string sub
        property color statusInk: Theme.surfaceText
        property color subInk: Theme.surfaceVariantText
        property real statusSize: Theme.fontSizeMedium
        property int statusWeight: Theme.fontWeightMedium
        property int alignment: Text.AlignLeft

        spacing: Theme.spacingXXS

        StyledText {
            width: parent.width
            text: label.status
            visible: text !== ""
            horizontalAlignment: label.alignment
            elide: Text.ElideRight
            font.pixelSize: label.statusSize
            font.weight: label.statusWeight
            color: label.statusInk
        }

        StyledText {
            width: parent.width
            text: label.sub
            visible: text !== ""
            horizontalAlignment: label.alignment
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: label.subInk
        }
    }

    component HeroLine: M3WaveProgress {
        property bool hatch: false

        implicitHeight: lineWidth + 2 * amp
        value: root.shownValue / 100
        limit: root.limit / 100
        lineWidth: BatteryPopoutMetrics.heroStroke
        wavelength: BatteryPopoutMetrics.wavelength
        amp: BatteryPopoutMetrics.waveAmp
        isPlaying: root.waveOn
        trackGap: BatteryPopoutMetrics.trackGap
        roundEnds: true
        showPlayhead: false
        showStopDot: true
        pastLimit: hatch ? "hatch" : "dim"
        hatchColor: Theme.withAlpha(Theme.onSurface, Theme.stateLayerHover)
        hatchPeriod: BatteryPopoutMetrics.hatchPeriod
        mirrored: I18n.isRtl
        fillColor: root.unknown ? "transparent" : root.accent
        stopDotColor: root.accent
        trackColor: Theme.secondaryContainer
    }

    component HeroRing: DCircularWavyProgress {
        progress: root.shownValue / 100
        limit: root.limit / 100
        showLimitMarker: true
        wavy: root.waveOn
        waveSpeed: root.active ? wavelength : 0
        gapSize: BatteryPopoutMetrics.ringGap
        strokeWidth: BatteryPopoutMetrics.gaugeStroke
        trackStrokeWidth: BatteryPopoutMetrics.gaugeStroke
        color: root.unknown ? "transparent" : root.accent
        trackColor: Theme.secondaryContainer
    }

    component RingCenter: Column {
        id: center

        property real numberSize: Theme.fontSizeDisplayLarge
        property bool beside: false

        anchors.centerIn: parent
        width: parent.width - 2 * (BatteryPopoutMetrics.gaugeStroke + Theme.spacingM)
        spacing: Theme.spacingXXS

        HeroNumber {
            anchors.horizontalCenter: parent.horizontalCenter
            value: root.value
            pixelSize: center.numberSize
            color: root.accent
        }

        HeroText {
            width: parent.width
            status: root.status
            sub: center.beside ? "" : root.time
            statusSize: center.beside ? Theme.fontSizeSmall : Theme.fontSizeMedium
            statusWeight: center.beside ? Theme.fontWeight : Theme.fontWeightMedium
            alignment: Text.AlignHCenter
        }
    }

    component HeroBadge: Item {
        id: badge

        property string kind: "shape"
        property string icon
        property color fill
        property color ink
        property real value: -1
        property color ringColor
        property color ringTrack
        readonly property bool ring: badge.kind === "ring"

        implicitWidth: badge.ring ? BatteryPopoutMetrics.badge : Theme.iconButtonSize
        implicitHeight: implicitWidth

        DMaterialShape {
            visible: !badge.ring
            anchors.fill: parent
            shape: "cookie9"
            color: badge.fill
        }

        DCircularWavyProgress {
            visible: badge.ring
            anchors.fill: parent
            progress: Math.max(0, badge.value) / 100
            wavy: false
            strokeWidth: BatteryPopoutMetrics.gaugeStroke
            trackStrokeWidth: BatteryPopoutMetrics.gaugeStroke
            color: badge.value >= 0 ? badge.ringColor : "transparent"
            trackColor: badge.ringTrack
        }

        DIcon {
            anchors.centerIn: parent
            name: badge.icon
            size: Theme.iconSizeMedium
            color: badge.ring ? badge.ringColor : badge.ink
            filled: true
        }
    }

    component HeroFooter: Loader {
        height: (item as Item)?.implicitHeight ?? 0
        visible: item !== null
    }

    component HeroActions: Row {
        id: actions

        property bool showEdit: root.showEdit
        property real buttonSize: BatteryPopoutMetrics.button
        property color iconColor: Theme.onSurfaceVariant
        // Over the card fill each button picks its own ink, since the fill edge can run between them.
        property var inkFor: null

        spacing: Theme.spacingXXS

        DActionButton {
            id: editButton
            visible: actions.showEdit
            iconName: "edit"
            iconSize: Theme.iconSize
            buttonSize: actions.buttonSize
            iconColor: actions.inkFor ? actions.inkFor(editButton) : actions.iconColor
            stateColor: Theme.onSurfaceVariant
            tooltipText: I18n.tr("Widget settings", "battery popout button that opens the battery widget options")
            onClicked: root.editRequested()
        }

        DActionButton {
            id: settingsButton
            iconName: "settings"
            iconSize: Theme.iconSize
            buttonSize: actions.buttonSize
            iconColor: actions.inkFor ? actions.inkFor(settingsButton) : actions.iconColor
            stateColor: Theme.onSurfaceVariant
            tooltipText: I18n.tr("Settings")
            onClicked: root.settingsRequested()
        }
    }

    component FillFace: Item {
        id: fillFace

        property var face: ({})
        property color ink
        property real inset: Theme.spacingM

        Item {
            visible: fillFace.face.mode === "card"
            anchors.fill: parent
            anchors.margins: fillFace.inset

            StyledText {
                anchors.left: parent.left
                anchors.top: parent.top
                width: parent.width - fillFace.face.reserve
                text: fillFace.face.status
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: fillFace.ink
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: fillFace.face.actionsWidth
                anchors.bottom: parent.bottom

                HeroNumber {
                    value: fillFace.face.value
                    pixelSize: fillFace.face.numberSize
                    color: fillFace.ink
                }

                StyledText {
                    width: parent.width
                    text: fillFace.face.sub
                    visible: text !== ""
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: fillFace.ink
                }
            }
        }

        RowLayout {
            visible: fillFace.face.mode === "cardSmall"
            anchors.fill: parent
            anchors.leftMargin: fillFace.inset
            anchors.rightMargin: Theme.spacingS + fillFace.face.actionsWidth
            spacing: Theme.spacingM

            HeroNumber {
                value: fillFace.face.value
                pixelSize: fillFace.face.numberSize
                color: fillFace.ink
            }

            HeroText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                status: fillFace.face.status
                sub: fillFace.face.sub
                statusInk: fillFace.ink
                subInk: fillFace.ink
            }
        }
    }

    Loader {
        id: body

        width: root.width
        height: implicitHeight
        sourceComponent: {
            switch (root.style) {
            case "compact":
                return lineCompact;
            case "ring":
                return root.compact ? ringCompact : (root.factsBeside ? ringBeside : ringFull);
            case "card":
                return cardLayout;
            default:
                return root.compact ? lineCompact : lineFull;
            }
        }
    }

    Component {
        id: lineFull

        HeroCard {
            implicitHeight: lineColumn.implicitHeight + pad * 2

            Column {
                id: lineColumn
                width: parent.width
                spacing: BatteryPopoutMetrics.gap

                Item {
                    width: parent.width
                    height: lineBadge.height

                    StyledText {
                        anchors.left: parent.left
                        anchors.right: lineActions.left
                        anchors.rightMargin: Theme.spacingS
                        text: root.status
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceVariantText
                    }

                    HeroBadge {
                        id: lineBadge
                        anchors.right: parent.right
                        kind: root.badgeKind
                        icon: root.source.icon ?? ""
                        fill: root.badgeFill
                        ink: root.badgeInk
                        value: root.value
                        ringColor: root.accent
                        ringTrack: Theme.secondaryContainer
                    }

                    HeroActions {
                        id: lineActions
                        anchors.right: lineBadge.left
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Item {
                    width: parent.width
                    height: lineNumber.implicitHeight - lineBadge.height / 2

                    HeroNumber {
                        id: lineNumber
                        y: -lineBadge.height / 2
                        value: root.value
                        color: root.accent
                    }
                }

                StyledText {
                    width: parent.width
                    text: root.time
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                HeroLine {
                    width: parent.width
                }

                HeroFooter {
                    width: parent.width
                    sourceComponent: root.footer
                }
            }
        }
    }

    Component {
        id: lineCompact

        HeroCard {
            id: compactCard

            readonly property bool framed: root.style !== "compact"

            implicitHeight: compactColumn.implicitHeight + pad * 2
            pad: framed ? BatteryPopoutMetrics.pad : 0
            color: framed ? surfaceColor : "transparent"
            border.width: framed ? Theme.layerOutlineWidth : 0

            Column {
                id: compactColumn
                width: parent.width
                spacing: BatteryPopoutMetrics.gap

                RowLayout {
                    width: parent.width
                    spacing: compactCard.framed ? Theme.spacingM : Theme.spacingL

                    HeroNumber {
                        value: root.value
                        pixelSize: compactCard.framed || BatteryPopoutMetrics.dense ? BatteryPopoutMetrics.smallNumberSize : Theme.fontSizeDisplayLarge
                        color: root.accent
                    }

                    HeroText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        status: root.status
                        sub: root.timeLine
                    }

                    HeroActions {
                        Layout.alignment: compactCard.framed ? Qt.AlignVCenter : Qt.AlignTop
                    }
                }

                HeroLine {
                    width: parent.width
                    hatch: !compactCard.framed
                }

                HeroFooter {
                    width: parent.width
                    sourceComponent: root.footer
                }
            }
        }
    }

    Component {
        id: ringFull

        HeroCard {
            implicitHeight: ringColumn.implicitHeight + pad * 2

            Column {
                id: ringColumn
                width: parent.width
                spacing: BatteryPopoutMetrics.gap

                HeroRing {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: BatteryPopoutMetrics.heroRing
                    height: width

                    RingCenter {}
                }

                HeroFooter {
                    width: parent.width
                    sourceComponent: root.footer
                }
            }

            HeroActions {
                anchors.top: parent.top
                anchors.right: parent.right
            }
        }
    }

    Component {
        id: ringBeside

        HeroCard {
            implicitHeight: ringBesideColumn.implicitHeight + pad * 2

            Column {
                id: ringBesideColumn
                width: parent.width
                spacing: BatteryPopoutMetrics.gap

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingXL

                    HeroRing {
                        Layout.preferredWidth: BatteryPopoutMetrics.heroRingBeside
                        Layout.preferredHeight: BatteryPopoutMetrics.heroRingBeside

                        RingCenter {
                            numberSize: Theme.fontSizeDisplay
                            beside: true
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingS

                        Repeater {
                            model: root.facts

                            Row {
                                id: fact

                                required property var modelData

                                width: parent.width
                                spacing: Theme.spacingS

                                DIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: fact.modelData.icon
                                    size: Theme.iconSizeMedium
                                    color: root.accent
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Theme.iconSizeMedium - parent.spacing
                                    text: fact.modelData.value
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                }
                            }
                        }
                    }

                    HeroActions {
                        Layout.alignment: Qt.AlignTop
                    }
                }

                HeroFooter {
                    width: parent.width
                    sourceComponent: root.footer
                }
            }
        }
    }

    Component {
        id: ringCompact

        HeroCard {
            implicitHeight: ringCompactColumn.implicitHeight + pad * 2

            Column {
                id: ringCompactColumn
                width: parent.width
                spacing: BatteryPopoutMetrics.gap

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    HeroRing {
                        Layout.preferredWidth: BatteryPopoutMetrics.heroSmall
                        Layout.preferredHeight: BatteryPopoutMetrics.heroSmall

                        HeroNumber {
                            anchors.centerIn: parent
                            value: root.value
                            pixelSize: Theme.fontSizeLarge
                            color: root.accent
                        }
                    }

                    HeroText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        status: root.status
                        sub: root.timeLine
                    }

                    HeroActions {}
                }

                HeroFooter {
                    width: parent.width
                    sourceComponent: root.footer
                }
            }
        }
    }

    Component {
        id: cardLayout

        HeroCard {
            id: card
            implicitHeight: cardLayoutColumn.implicitHeight + pad * 2

            Column {
                id: cardLayoutColumn
                width: parent.width
                spacing: BatteryPopoutMetrics.gap

                ClippingRectangle {
                    id: cardTrack

                    readonly property real limitX: width * root.limit / 100
                    readonly property string faceMode: root.compact ? "cardSmall" : "card"
                    readonly property color trackTint: Contrast.mix(card.surfaceColor, root.accent, BatteryPopoutMetrics.trackTintAmount)
                    // The text is drawn once per surface: fill ink over the fill, track ink everywhere else.
                    readonly property color fillInk: Contrast.readableOn(root.accent, [Theme.surfaceText, Theme.surface])
                    readonly property color trackInk: Contrast.readableOnAll(root.limited ? [cardTrack.trackTint, root.pastLimit(cardTrack.trackTint)] : [cardTrack.trackTint], [Theme.surfaceText, Theme.surface])
                    readonly property var face: ({
                            mode: cardTrack.faceMode,
                            value: root.value,
                            status: root.status,
                            sub: root.timeLine,
                            numberSize: root.compact ? BatteryPopoutMetrics.smallNumberSize : Theme.fontSizeDisplayLarge,
                            reserve: root.compact ? 0 : cardBadge.width + Theme.spacingS,
                            actionsWidth: BatteryPopoutMetrics.button + (root.showEdit ? BatteryPopoutMetrics.button + Theme.spacingXXS : 0)
                        })

                    function inkAt(item) {
                        // Summing x (not mapToItem) keeps the binding live while the layout settles.
                        let center = item.width / 2;
                        for (let it = item; it && it !== cardTrack; it = it.parent)
                            center += it.x;
                        return center >= fill.x && center <= fill.x + fill.width ? cardTrack.fillInk : cardTrack.trackInk;
                    }

                    width: parent.width
                    height: BatteryPopoutMetrics.cardFill
                    radius: Theme.cornerRadiusM
                    color: cardTrack.trackTint

                    Behavior on color {
                        enabled: !Theme.reduceMotion
                        DColorAnim {}
                    }

                    Rectangle {
                        id: fill
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * root.shownValue / 100
                        color: root.accent

                        Behavior on color {
                            enabled: !Theme.reduceMotion
                            DColorAnim {}
                        }
                    }

                    Rectangle {
                        visible: root.limited
                        anchors.left: parent.left
                        anchors.leftMargin: cardTrack.limitX
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        color: Theme.withAlpha(Theme.scrimColor, BatteryPopoutMetrics.pastLimitShade)
                    }

                    FillFace {
                        anchors.fill: parent
                        face: cardTrack.face
                        ink: cardTrack.trackInk
                    }

                    Item {
                        id: fillClip
                        anchors.fill: fill
                        clip: true

                        FillFace {
                            x: -fillClip.x
                            width: cardTrack.width
                            height: cardTrack.height
                            face: cardTrack.face
                            ink: cardTrack.fillInk
                        }
                    }

                    HeroBadge {
                        id: cardBadge

                        readonly property color surfaceInk: cardTrack.inkAt(cardBadge)

                        visible: !root.compact
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingS
                        kind: root.badgeKind
                        icon: root.source.icon ?? ""
                        fill: Contrast.readableOnAll([root.accent, cardTrack.trackTint], [root.badgeFill, cardBadge.surfaceInk], 3)
                        ink: Contrast.readableOn(cardBadge.fill, [root.badgeInk, Theme.surface, Theme.surfaceText])
                        value: root.value
                        ringColor: cardBadge.surfaceInk
                        ringTrack: Theme.withAlpha(cardBadge.surfaceInk, BatteryPopoutMetrics.ringBadgeTrack)
                    }

                    HeroActions {
                        id: cardActions
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        y: root.compact ? (cardTrack.height - height) / 2 : cardTrack.height - height - Theme.spacingS
                        inkFor: item => cardTrack.inkAt(item)
                    }
                }

                HeroFooter {
                    width: parent.width
                    sourceComponent: root.footer
                }
            }
        }
    }
}
