pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property string settingKey: ""
    property string icon: ""
    property string title: ""
    property string tip: ""
    property string kdlKey: ""
    property string dependsOn: ""
    // "", "low", "some" or "high", from the fixed cost list below unless a section names one
    property string cost: costOf(settingKey)
    property string costTip: costTipOf(settingKey)
    property bool toggle: typeof value === "boolean"
    // The alternate the hover preview shows; a control or a section names one, otherwise afterOf answers per key.
    property var tryValue: typeof value === "boolean" ? !value : undefined
    readonly property var tryTarget: tryValue !== undefined ? tryValue : actions.afterOf(settingKey)
    // Width the control takes when the row is on one line; a control that fills a stacked row must not feed its stretched width back here.
    property real controlWidth: actions.slotWidth
    default property alias control: actions.control

    readonly property var value: settingKey ? NiriPageService.get(settingKey) : undefined
    readonly property bool modified: settingKey !== "" && NiriPageService.isModified(settingKey)
    readonly property bool isOn: value === true
    readonly property bool nested: dependsOn !== ""
    readonly property bool folded: nested && !NiriPageService.get(dependsOn)
    readonly property bool expert: NiriPageService.expert
    readonly property bool hovered: hover.hovered
    readonly property bool isNew: settingKey !== "" && NiriPageService.isNew(settingKey)
    readonly property bool canTry: tryTarget !== undefined
    readonly property real indent: nested ? Theme.spacingL : 0
    readonly property real plateSize: nested ? Theme.buttonHeightXS : Theme.iconButtonSize
    readonly property real labelMinWidth: Theme.iconButtonSize * 4.5
    readonly property bool stacked: body.width < plateSize + Theme.spacingM * 2 + labelMinWidth + controlWidth + actions.actionsWidth
    readonly property real stackedControlWidth: body.width - label.x - actions.actionsWidth

    function write(v) {
        NiriPageService.set(settingKey, v);
    }

    // A section overrides this like write() when its rows need more than a plain reset
    // (the Advanced risky rows arm the Keep countdown on a reset too).
    function resetValue() {
        NiriPageService.reset(settingKey);
    }

    // The fixed battery cost list, keyed by settingKey (blur, shadows, animations and Alt-Tab
    // previews only). A section never poses one itself.
    readonly property var costList: ({
            "look.blurOn": ["high", I18n.tr("Redraws what is behind each window, every frame.", "niri page battery cost, blur")],
            "look.shadowOn": ["low", I18n.tr("Soft shadows cost little to draw.", "niri page battery cost, shadows")],
            "animations.on": ["some", I18n.tr("Draws extra frames each time a window moves.", "niri page battery cost, animations")],
            "columns.altTabPreviewScale": ["some", I18n.tr("Draws a live picture of every window while Alt-Tab is open.", "niri page battery cost, Alt-Tab previews")]
        })

    function costOf(key) {
        return costList[key]?.[0] ?? "";
    }

    function costTipOf(key) {
        return costList[key]?.[1] ?? "";
    }

    // Bleeds into the card padding so the hover plate reaches past the text.
    x: -Theme.spacingS
    width: (parent?.width ?? 0) + Theme.spacingS * 2
    visible: !folded
    implicitHeight: Math.max(Theme.listItemHeight, body.implicitHeight + Theme.spacingS * 2)

    HoverHandler {
        id: hover
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: root.indent
        radius: Theme.cornerRadiusM
        color: root.hovered ? Theme.surfaceTextHover : Theme.withAlpha(Theme.surfaceTextHover, 0)

        Behavior on color {
            enabled: !SettingsData.reduceMotion
            ColorAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }
    }

    Rectangle {
        visible: root.nested
        x: root.indent
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: Theme.spacingS
        anchors.bottomMargin: Theme.spacingS
        width: Theme.outlineWidthFocused
        radius: width / 2
        color: Theme.outlineVariant
    }

    Item {
        id: body

        x: root.indent + (root.nested ? Theme.spacingM : Theme.spacingS)
        y: Theme.spacingS
        width: root.width - x - Theme.spacingS
        height: implicitHeight
        // A stacked row puts Reset and the control on a second line, right-aligned.
        readonly property real labelLineHeight: Math.max(iconPlate.height, label.implicitHeight)

        implicitHeight: root.stacked ? labelLineHeight + Theme.spacingS + actions.controlsHeight : Math.max(labelLineHeight, actions.controlsHeight)

        Rectangle {
            id: iconPlate

            readonly property bool lit: root.isOn || root.modified

            visible: root.icon !== ""
            width: visible ? root.plateSize : 0
            height: root.plateSize
            y: root.stacked ? 0 : (body.height - height) / 2
            radius: Theme.cornerRadiusM
            color: lit ? Theme.primaryContainer : SettingsMetrics.controlColor

            Behavior on color {
                enabled: !SettingsData.reduceMotion
                ColorAnimation {
                    duration: Theme.mediumDuration
                    easing.type: Theme.standardEasing
                }
            }

            DIcon {
                anchors.centerIn: parent
                name: root.icon
                size: root.nested ? Theme.iconSizeSmall : Theme.iconSizeMedium
                filled: root.isOn
                color: iconPlate.lit ? Theme.onPrimaryContainer : Theme.surfaceVariantText
            }
        }

        Column {
            id: label

            x: iconPlate.visible ? iconPlate.width + Theme.spacingM : 0
            y: root.stacked ? Math.max(0, (iconPlate.height - implicitHeight) / 2) : (body.height - implicitHeight) / 2
            width: root.stacked ? body.width - x : body.width - x - Theme.spacingM - actions.controlsWidth
            spacing: Theme.spacingXXS

            Row {
                id: titleRow
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, titleRow.width - (newPill.visible ? newPill.width + Theme.spacingS : 0) - (modDot.visible ? modDot.width + Theme.spacingS : 0) - (costIcon.visible ? costIcon.width + Theme.spacingS : 0))
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }

                Rectangle {
                    id: newPill

                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.isNew
                    width: newText.implicitWidth + Theme.spacingS * 2
                    height: Theme.iconSizeSmall + Theme.spacingXXS
                    radius: height / 2
                    color: Theme.primaryContainer
                    Accessible.role: Accessible.StaticText
                    Accessible.name: I18n.tr("New", "niri page pill, an option that came with a niri update")

                    StyledText {
                        id: newText
                        anchors.centerIn: parent
                        text: I18n.tr("New", "niri page pill, an option that came with a niri update")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightBold
                        color: Theme.onPrimaryContainer
                    }

                    // Once the pill is on screen the version is seen, and it stops showing next session.
                    onVisibleChanged: {
                        if (visible)
                            NiriPageService.noteSeenVersion();
                    }
                }

                Rectangle {
                    id: modDot
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.modified
                    width: Theme.spacingS
                    height: width
                    radius: width / 2
                    color: Theme.primary
                    Accessible.role: Accessible.StaticText
                    Accessible.name: I18n.tr("Modified")
                }

                DIcon {
                    id: costIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.cost !== ""
                    name: root.cost === "high" ? "battery_alert" : root.cost === "some" ? "battery_3_bar" : "battery_full"
                    size: Theme.iconSizeSmall
                    color: root.cost === "high" ? Theme.warning : Theme.surfaceVariantText

                    HoverHandler {
                        id: costHover
                    }

                    Loader {
                        active: costHover.hovered
                        sourceComponent: DTooltipHost {
                            target: costIcon
                            side: "top"
                            multiline: true
                            Component.onCompleted: Qt.callLater(schedule)
                            text: {
                                const level = root.cost === "high" ? I18n.tr("High battery use") : root.cost === "some" ? I18n.tr("Some battery use") : I18n.tr("Light on battery");
                                return root.costTip ? level + ". " + root.costTip : level;
                            }
                        }
                    }
                }
            }

            StyledText {
                width: parent.width
                visible: root.expert && root.tip !== ""
                text: root.tip
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                width: parent.width
                visible: root.expert && root.kdlKey !== ""
                text: root.kdlKey
                elide: Text.ElideRight
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Loader {
                active: root.hovered && !root.expert && root.tip !== ""
                sourceComponent: DTooltipHost {
                    target: titleText
                    side: "top"
                    multiline: true
                    text: root.tip
                    Component.onCompleted: Qt.callLater(schedule)
                }
            }
        }

        NiriRowActions {
            id: actions
            anchors.fill: parent
            row: root
            labelLineHeight: body.labelLineHeight
        }
    }
}
