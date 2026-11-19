pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Common
import qs.DCommon.Widgets
import "../../../Common/BatteryPopoutMetrics.js" as BatteryPopoutMetrics
import "../../../DCommon/Common/Contrast.js" as Contrast

Item {
    id: root

    // { status, time, percentage, level, unknown, charging, limit, icon, rate }; level is the unscaled reading, percentage drives the fill and number
    property var source: ({})
    // [{ icon, value }], shown beside the ring in the non-compact ring layout
    property var facts: []
    property bool factsBeside: false
    property bool showEdit: true
    // Shown below the gauge inside the hero card, e.g. the power profile
    property Component footer: null
    property var metrics: BatteryPopoutMetrics.metrics(SettingsData.density)
    property bool active: false

    signal settingsRequested
    signal editRequested

    readonly property string style: SettingsData.batteryPopoutStyle
    readonly property bool wavy: SettingsData.batteryPopoutWavy
    readonly property bool compact: root.metrics.compact
    readonly property bool unknown: root.source.unknown ?? false
    readonly property real percentage: root.unknown ? 0 : Math.max(0, Math.min(100, root.source.percentage ?? 0))
    readonly property real value: root.unknown ? -1 : root.percentage
    readonly property bool charging: root.source.charging ?? false
    readonly property real limit: root.source.limit ?? 100
    readonly property bool limited: root.limit > 0 && root.limit < 100
    readonly property string status: root.source.status ?? ""
    readonly property string time: root.source.time ?? ""
    readonly property string timeLine: [root.time, root.source.rate ?? ""].filter(part => part !== "").join(" · ")
    readonly property bool besideFacts: root.factsBeside && !root.compact && root.style === "ring"

    readonly property string colorMode: SettingsData.batteryPopoutColor
    readonly property real level: root.unknown ? 0 : Math.max(0, Math.min(100, root.source.level ?? root.source.percentage ?? 0))
    readonly property color accent: BatteryService.colorFor(root.colorMode, root.level, root.charging, Theme.surfaceText)
    readonly property bool lowTone: (root.colorMode === "primary" || root.colorMode === "lowcharging") && root.accent === Theme.error
    readonly property color badgeFill: root.lowTone ? Theme.errorContainer : root.colorMode === "theme" ? Theme.surfaceContainerHighest : Theme.primaryContainer
    readonly property color badgeInk: root.lowTone ? Theme.onErrorContainer : root.colorMode === "theme" ? Theme.surfaceText : Theme.onPrimaryContainer
    readonly property real compactNumberSize: root.metrics.heroNumberSmall ? Theme.fontSizeXXLarge : Theme.fontSizeDisplay
    readonly property real pastLimitShade: 0.28
    readonly property real trackTintAmount: 0.26
    readonly property real ringBadgeTrack: 0.3
    readonly property string badgeKind: SettingsData.batteryPopoutBadge === "ring" ? "ring" : "shape"

    property real shownValue: Math.max(0, root.value)

    function pastLimit(color) {
        return Contrast.mix(color, Qt.rgba(0, 0, 0, 1), root.pastLimitShade);
    }

    implicitHeight: body.height
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

    component HeroNumber: Item {
        id: number

        property real value: -1
        property real pixelSize: Theme.fontSizeDisplayLarge
        property color color: Theme.primary

        implicitWidth: digits.implicitWidth + (unit.visible ? unit.implicitWidth : 0)
        implicitHeight: number.pixelSize

        StyledText {
            id: digits
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
            anchors.left: digits.right
            anchors.baseline: digits.baseline
            visible: number.value >= 0
            text: "%"
            font.pixelSize: Math.round(number.pixelSize / 2)
            color: number.color
        }
    }

    component HeroText: Column {
        id: label

        property string status
        property string sub
        property color statusInk: Theme.surfaceText
        property color subInk: Theme.surfaceVariantText

        spacing: Theme.spacingXXS

        StyledText {
            width: parent.width
            text: label.status
            visible: text !== ""
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: label.statusInk
        }

        StyledText {
            width: parent.width
            text: label.sub
            visible: text !== ""
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: label.subInk
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

        implicitWidth: Theme.iconButtonSize
        implicitHeight: Theme.iconButtonSize

        DMaterialShape {
            visible: !badge.ring
            anchors.fill: parent
            shape: "cookie9"
            color: badge.fill
        }

        BatteryLevelRing {
            visible: badge.ring
            anchors.fill: parent
            value: badge.value
            wavy: false
            moving: false
            fillColor: badge.ringColor
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
        height: item ? item.implicitHeight : 0
        visible: item !== null
    }

    component HeroActions: Row {
        id: actions

        property bool showEdit: true
        property real buttonSize: Theme.iconButtonSize
        property color iconColor: Theme.onSurfaceVariant

        signal settingsClicked
        signal editClicked

        spacing: Theme.spacingXXS

        DActionButton {
            visible: actions.showEdit
            iconName: "edit"
            iconSize: Theme.iconSize
            buttonSize: actions.buttonSize
            iconColor: actions.iconColor
            stateColor: Theme.onSurfaceVariant
            tooltipText: I18n.tr("Widget settings", "battery popout button that opens the battery widget options")
            Accessible.name: I18n.tr("Widget settings", "battery popout button that opens the battery widget options")
            onClicked: actions.editClicked()
        }

        DActionButton {
            iconName: "settings"
            iconSize: Theme.iconSize
            buttonSize: actions.buttonSize
            iconColor: actions.iconColor
            stateColor: Theme.onSurfaceVariant
            tooltipText: I18n.tr("Settings")
            Accessible.name: I18n.tr("Settings")
            onClicked: actions.settingsClicked()
        }
    }

    component FillFace: Item {
        id: face

        property string mode: "card"
        property real value: -1
        property string status
        property string sub
        property real numberSize: Theme.fontSizeDisplayLarge
        property color ink
        property real inset: Theme.spacingM
        property real reserve: 0
        property real actionsWidth: 0

        Item {
            visible: face.mode === "card"
            anchors.fill: parent
            anchors.margins: face.inset

            StyledText {
                anchors.left: parent.left
                anchors.top: parent.top
                width: parent.width - face.reserve
                text: face.status
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: face.ink
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: face.actionsWidth
                anchors.bottom: parent.bottom

                HeroNumber {
                    value: face.value
                    pixelSize: face.numberSize
                    color: face.ink
                }

                StyledText {
                    width: parent.width
                    text: face.sub
                    visible: text !== ""
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: face.ink
                }
            }
        }

        RowLayout {
            visible: face.mode === "cardSmall"
            anchors.fill: parent
            anchors.leftMargin: face.inset
            anchors.rightMargin: Theme.spacingS + face.actionsWidth
            spacing: Theme.spacingM

            HeroNumber {
                value: face.value
                pixelSize: face.numberSize
                color: face.ink
            }

            HeroText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                status: face.status
                sub: face.sub
                statusInk: face.ink
                subInk: face.ink
            }
        }
    }

    Loader {
        id: body

        width: root.width
        height: implicitHeight
        sourceComponent: {
            switch (root.style) {
            case "ring":
                return root.compact ? ringCompact : (root.besideFacts ? ringBeside : ringFull);
            case "card":
                return cardLayout;
            default:
                return root.compact ? lineCompact : lineFull;
            }
        }
    }

    Component {
        id: lineFull

        DCard {
            pad: root.metrics.pad
            restRadius: Theme.cornerRadiusL
            implicitHeight: lineColumn.implicitHeight + pad * 2

            Column {
                id: lineColumn
                width: parent.width
                spacing: root.metrics.gap

                Item {
                    width: parent.width
                    height: lineBadge.height

                    StyledText {
                        anchors.left: parent.left
                        anchors.right: lineActions.visible ? lineActions.left : lineBadge.left
                        anchors.rightMargin: Theme.spacingS
                        text: root.status
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
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
                        showEdit: root.showEdit
                        anchors.right: lineBadge.left
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: root.metrics.button
                        onSettingsClicked: root.settingsRequested()
                        onEditClicked: root.editRequested()
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
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                BatteryLevelBar {
                    value: root.value
                    limit: root.limit
                    charging: root.charging
                    wavy: root.wavy
                    fillColor: root.accent
                    moving: root.active
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

        DCard {
            pad: root.metrics.pad
            restRadius: Theme.cornerRadiusL
            implicitHeight: compactColumn.implicitHeight + pad * 2

            Column {
                id: compactColumn
                width: parent.width
                spacing: root.metrics.gap

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    HeroNumber {
                        value: root.value
                        pixelSize: root.compactNumberSize
                        color: root.accent
                    }

                    HeroText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        status: root.status
                        sub: root.timeLine
                    }

                    HeroActions {
                        showEdit: root.showEdit
                        buttonSize: root.metrics.button
                        onSettingsClicked: root.settingsRequested()
                        onEditClicked: root.editRequested()
                    }
                }

                BatteryLevelBar {
                    value: root.value
                    limit: root.limit
                    charging: root.charging
                    wavy: root.wavy
                    fillColor: root.accent
                    moving: root.active
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

        DCard {
            pad: root.metrics.pad
            restRadius: Theme.cornerRadiusL
            implicitHeight: ringBox.height + (ringFooter.visible ? ringFooter.height + root.metrics.gap : 0) + pad * 2

            BatteryLevelRing {
                id: ringBox
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.metrics.heroRing
                height: width
                value: root.value
                limit: root.limit
                charging: root.charging
                wavy: root.wavy
                fillColor: root.accent
                moving: root.active

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: Theme.spacingXXS

                    HeroNumber {
                        anchors.horizontalCenter: parent.horizontalCenter
                        value: root.value
                        color: root.accent
                    }

                    StyledText {
                        width: parent.width
                        text: root.status
                        visible: text !== ""
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: root.time
                        visible: text !== ""
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            HeroActions {
                showEdit: root.showEdit
                anchors.top: parent.top
                anchors.right: parent.right
                buttonSize: root.metrics.button
                onSettingsClicked: root.settingsRequested()
                onEditClicked: root.editRequested()
            }

            HeroFooter {
                id: ringFooter
                anchors.bottom: parent.bottom
                width: parent.width
                sourceComponent: root.footer
            }
        }
    }

    Component {
        id: ringBeside

        DCard {
            pad: root.metrics.pad
            restRadius: Theme.cornerRadiusL
            implicitHeight: besideRow.implicitHeight + (besideFooter.visible ? besideFooter.height + root.metrics.gap : 0) + pad * 2

            RowLayout {
                id: besideRow
                width: parent.width
                spacing: Theme.spacingXL

                BatteryLevelRing {
                    Layout.preferredWidth: root.metrics.heroRingList
                    Layout.preferredHeight: root.metrics.heroRingList
                    value: root.value
                    limit: root.limit
                    charging: root.charging
                    wavy: root.wavy
                    fillColor: root.accent
                    moving: root.active

                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: Theme.spacingXXS

                        HeroNumber {
                            anchors.horizontalCenter: parent.horizontalCenter
                            value: root.value
                            pixelSize: Theme.fontSizeDisplay
                            color: root.accent
                        }

                        StyledText {
                            width: parent.width
                            text: root.status
                            visible: text !== ""
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
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
            }

            HeroActions {
                showEdit: root.showEdit
                anchors.top: parent.top
                anchors.right: parent.right
                buttonSize: root.metrics.button
                onSettingsClicked: root.settingsRequested()
                onEditClicked: root.editRequested()
            }

            HeroFooter {
                id: besideFooter
                anchors.bottom: parent.bottom
                width: parent.width
                sourceComponent: root.footer
            }
        }
    }

    Component {
        id: ringCompact

        DCard {
            pad: root.metrics.pad
            restRadius: Theme.cornerRadiusL
            implicitHeight: ringRow.implicitHeight + (ringCompactFooter.visible ? ringCompactFooter.height + root.metrics.gap : 0) + pad * 2

            RowLayout {
                id: ringRow
                width: parent.width
                spacing: Theme.spacingM

                BatteryLevelRing {
                    Layout.preferredWidth: root.metrics.heroSmall
                    Layout.preferredHeight: root.metrics.heroSmall
                    value: root.value
                    limit: root.limit
                    charging: root.charging
                    wavy: root.wavy
                    fillColor: root.accent
                    moving: root.active

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

                HeroActions {
                    showEdit: root.showEdit
                    buttonSize: root.metrics.button
                    onSettingsClicked: root.settingsRequested()
                    onEditClicked: root.editRequested()
                }
            }

            HeroFooter {
                id: ringCompactFooter
                anchors.bottom: parent.bottom
                width: parent.width
                sourceComponent: root.footer
            }
        }
    }

    Component {
        id: cardLayout

        DCard {
            id: card
            pad: root.metrics.pad
            restRadius: Theme.cornerRadiusL
            implicitHeight: cardTrack.height + (cardFooter.visible ? cardFooter.height + root.metrics.gap : 0) + pad * 2

            ClippingRectangle {
                id: cardTrack

                readonly property real limitX: width * root.limit / 100
                readonly property string faceMode: root.compact ? "cardSmall" : "card"
                readonly property color baseTint: Contrast.mix(card.surfaceColor, root.accent, root.trackTintAmount)
                readonly property color ink: Contrast.readableOnAll(root.limited ? [root.accent, baseTint, root.pastLimit(baseTint)] : [root.accent, baseTint], [Theme.surfaceText, Theme.surface])
                // One ink has to read on fill and track: a track too far from the ink takes on more of the accent.
                readonly property color trackTint: {
                    let amount = root.trackTintAmount;
                    for (let step = 0; step < 8; step++) {
                        const tint = Contrast.mix(card.surfaceColor, root.accent, amount);
                        const past = root.limited ? root.pastLimit(tint) : tint;
                        if (Contrast.worstRatio(cardTrack.ink, [tint, past]) >= 3)
                            return tint;
                        amount = Math.min(1, amount + 0.1);
                    }
                    return Contrast.mix(card.surfaceColor, root.accent, amount);
                }
                // The badge sits on the fill or on the track, so it has to stand out from both
                readonly property color badgeFill: Contrast.readableOnAll([root.accent, cardTrack.trackTint], [root.badgeFill, cardTrack.ink], 3)
                readonly property color badgeInk: Contrast.readableOn(cardTrack.badgeFill, [root.badgeInk, Theme.surface, Theme.surfaceText])

                width: parent.width
                height: root.compact ? root.metrics.fillSmall : root.metrics.fill
                radius: Theme.cornerRadiusM
                color: cardTrack.trackTint

                Behavior on color {
                    enabled: !Theme.reduceMotion
                    DColorAnim {}
                }

                Rectangle {
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
                    color: Qt.rgba(0, 0, 0, root.pastLimitShade)
                }

                FillFace {
                    anchors.fill: parent
                    mode: cardTrack.faceMode
                    value: root.value
                    status: root.status
                    sub: root.time
                    numberSize: root.compact ? root.compactNumberSize : Theme.fontSizeDisplayLarge
                    ink: cardTrack.ink
                    reserve: root.compact ? 0 : cardBadge.width + Theme.spacingS
                    actionsWidth: root.metrics.button + (root.showEdit ? root.metrics.button + Theme.spacingXXS : 0)
                }

                Rectangle {
                    visible: root.limited
                    anchors.left: parent.left
                    anchors.leftMargin: cardTrack.limitX - width / 2
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Theme.spacingXS
                    color: Theme.surfaceText
                }

                HeroBadge {
                    id: cardBadge
                    visible: !root.compact
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingS
                    kind: root.badgeKind
                    icon: root.source.icon ?? ""
                    fill: cardTrack.badgeFill
                    ink: cardTrack.badgeInk
                    value: root.value
                    ringColor: cardTrack.ink
                    ringTrack: Theme.withAlpha(cardTrack.ink, root.ringBadgeTrack)
                }

                HeroActions {
                    showEdit: root.showEdit
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    y: root.compact ? (cardTrack.height - height) / 2 : cardTrack.height - height - Theme.spacingS
                    buttonSize: root.metrics.button
                    iconColor: cardTrack.ink
                    onSettingsClicked: root.settingsRequested()
                    onEditClicked: root.editRequested()
                }
            }

            HeroFooter {
                id: cardFooter
                anchors.bottom: parent.bottom
                width: parent.width
                sourceComponent: root.footer
            }
        }
    }
}
