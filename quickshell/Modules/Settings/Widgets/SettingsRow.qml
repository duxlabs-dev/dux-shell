pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

T.Control {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property bool isSettingsRow: true
    property Item groupItem: root

    property string tab: ""
    property var tags: []
    property string settingKey: ""

    property string title: ""
    property bool singleLineTitle: false
    property string subtitle: ""
    property color subtitleColor: supportingContentColor
    property string iconName: ""
    property bool iconBox: false
    property bool clickable: false
    property bool showChevron: false
    property string trailingBadge: ""
    property bool trailingOnTitleLine: false
    property color trailingBadgeColor: supportingContentColor
    property bool paintBackground: !(parent?.isSettingsGroupHost ?? false)
    property real paddingH: SettingsMetrics.rowPaddingH
    property real paddingV: SettingsMetrics.rowPaddingV
    readonly property Item groupHost: groupItem.parent?.isSettingsGroupHost ? groupItem.parent : groupItem.parent?.parent?.isSettingsGroupHost ? groupItem.parent.parent : null
    readonly property color slotColor: groupHost?.slotColor ?? SettingsMetrics.rowColor
    property color rowColor: slotColor
    property bool active: false
    property color selectedRowColor: Theme.selectedContainer
    property color selectedContentColor: Theme.onSelectedContainer
    readonly property color contentColor: active ? selectedContentColor : Theme.surfaceText
    readonly property color supportingContentColor: active ? selectedContentColor : Theme.surfaceVariantText
    property color iconColor: active ? Theme.accentOnSelectedContainer : Theme.primary
    property color titleColor: contentColor

    property var resetStore: SettingsData
    property var resetKeys: settingKey !== "" && resetStore === SettingsData && SettingsData.hasSetting(settingKey) ? [settingKey] : []
    property bool modified: resetKeys.length > 0 && resetStore?.isDefault(resetKeys) === false
    property bool resetByKeys: true
    property bool resetInHeader: true

    default property alias trailing: trailingSlot.data
    property alias leading: leadingSlot.data
    property alias body: bodySlot.data
    property alias supporting: supportingSlot.data

    readonly property bool hasBody: bodySlot.height > 0
    readonly property bool hasText: title !== "" || subtitle !== ""
    readonly property bool isHighlighted: settingKey !== "" && SettingsSearchService.highlightSection === settingKey
    property bool highlighted: isHighlighted
    property bool inGroup: groupHost !== null
    readonly property bool isFirstInGroup: _edge(true)
    readonly property bool isLastInGroup: _edge(false)
    property bool dividerBefore: inGroup && !isFirstInGroup
    property real topRadius: isFirstInGroup ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
    property real bottomRadius: isLastInGroup ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
    property real topLeftRadius: topRadius
    property real topRightRadius: topRadius
    property real bottomLeftRadius: bottomRadius
    property real bottomRightRadius: bottomRadius
    property real minHeight: subtitle !== "" ? SettingsMetrics.rowMinHeightTwoLine : SettingsMetrics.rowMinHeight
    // Keyboard focus on the row or any control inside it tints the row, so navigation reads without a focus ring
    readonly property Item activeItem: Window.activeFocusItem
    readonly property bool focusWithin: (activeItem?.visualFocus ?? false) && _contains(activeItem)
    readonly property real headerBand: paddingV * 2 + headerLine.height
    readonly property real bodyGap: clickable ? paddingV : Theme.spacingM
    readonly property bool headerHovered: rowHover.hovered && (!hasBody || rowHover.point.position.y < headerBand)
    readonly property bool resetChipHovered: resetChipLoader.item?.hovered ?? false

    function _contains(item) {
        for (let p = item; p; p = p.parent) {
            if (p === root)
                return true;
        }
        return false;
    }

    signal clicked(bool keyboard)
    signal resetRequested

    onResetRequested: {
        if (resetByKeys)
            resetStore.resetToDefault(resetKeys);
    }

    focusPolicy: clickable ? Qt.StrongFocus : Qt.NoFocus
    Accessible.role: clickable ? Accessible.Button : Accessible.NoRole
    Accessible.name: title
    Accessible.description: subtitle
    Accessible.onPressAction: {
        if (clickable && enabled)
            clicked(true);
    }

    Keys.onPressed: event => {
        if (!clickable || !enabled)
            return;
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.clicked(true);
            event.accepted = true;
            break;
        }
    }

    function _edge(first) {
        if (!groupHost)
            return true;
        const container = groupItem.parent;
        if (container === groupHost)
            return groupHost.isEdge(groupItem, first);
        return groupHost.isEdge(container, first) && _edgeInContainer(first);
    }

    function _edgeInContainer(first) {
        const siblings = groupItem.parent?.visibleChildren;
        if (!siblings)
            return true;
        let seen = null;
        for (let i = 0; i < siblings.length; i++) {
            const c = siblings[i];
            if (c.isSettingsRow !== true)
                continue;
            if (first)
                return c === groupItem;
            seen = c;
        }
        return seen === groupItem;
    }

    width: parent?.width ?? 0
    height: implicitHeight
    implicitHeight: paddingV * 2 + headerLine.height + (hasBody ? bodySlot.height + (headerLine.height > 0 ? bodyGap : 0) : 0)

    SettingsSearchRegistration {
        target: root
        settingKey: root.settingKey
    }

    Rectangle {
        anchors.fill: parent
        visible: root.paintBackground || root.active || root.highlighted
        color: {
            if (root.active)
                return root.selectedRowColor;
            if (!root.paintBackground)
                return SettingsMetrics.rowHighlightColor;
            return root.highlighted ? Theme.blend(root.rowColor, Theme.primary, SettingsMetrics.highlightBlend) : root.rowColor;
        }
        border.width: {
            if (!root.paintBackground)
                return 0;
            return root.inGroup ? SettingsMetrics.groupEdgeWidth : Theme.layerOutlineWidth;
        }
        border.color: Theme.outlineMedium
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius

        Loader {
            x: root.paddingH
            width: parent.width - root.paddingH * 2
            active: root.paintBackground && SettingsMetrics.continuousGroups && root.dividerBefore
            sourceComponent: DDivider {
                color: SettingsMetrics.groupDividerColor
            }
        }
    }

    // Most rows are never pressed or focused, so the state layer, ripple, click target and focus ring wait for one that is
    Loader {
        anchors.fill: parent
        active: root.clickable || root.focusWithin

        sourceComponent: Item {
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: root.hasBody && !root.focusWithin ? root.headerBand : root.height
                color: root.contentColor
                opacity: {
                    if (!root.enabled)
                        return 0;
                    if (clickControl.down)
                        return Theme.stateLayerPressed;
                    if (root.focusWithin)
                        return Theme.stateLayerFocus;
                    return root.headerHovered && !root.resetChipHovered ? Theme.stateLayerHover : 0;
                }
                topLeftRadius: root.topLeftRadius
                topRightRadius: root.topRightRadius
                bottomLeftRadius: height < root.height ? 0 : root.bottomLeftRadius
                bottomRightRadius: height < root.height ? 0 : root.bottomRightRadius

                Behavior on opacity {
                    NumberAnimation {
                        duration: SettingsMetrics.fadeDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }
            }

            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: root.hasBody ? root.headerBand : root.height

                DRipple {
                    id: ripple
                    visible: root.clickable
                    rippleColor: root.contentColor
                    topLeftRadius: root.topLeftRadius
                    topRightRadius: root.topRightRadius
                    bottomLeftRadius: root.hasBody ? 0 : root.bottomLeftRadius
                    bottomRightRadius: root.hasBody ? 0 : root.bottomRightRadius
                }

                StyledButton {
                    id: clickControl
                    anchors.fill: parent
                    enabled: root.clickable && root.enabled
                    hoverEnabled: false
                    focusPolicy: Qt.NoFocus
                    background: null
                    Accessible.ignored: true
                    onPressedChanged: {
                        if (pressed) {
                            root.forceActiveFocus(Qt.MouseFocusReason);
                            ripple.trigger(pressX, pressY);
                        }
                    }
                    onClicked: root.clicked(false)
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.focusRingWidth / 2
                topLeftRadius: Math.max(0, root.topLeftRadius - Theme.focusRingWidth / 2)
                topRightRadius: Math.max(0, root.topRightRadius - Theme.focusRingWidth / 2)
                bottomLeftRadius: Math.max(0, root.bottomLeftRadius - Theme.focusRingWidth / 2)
                bottomRightRadius: Math.max(0, root.bottomRightRadius - Theme.focusRingWidth / 2)
                color: "transparent"
                border.width: Theme.focusRingWidth
                border.color: Theme.focusRingColor
                visible: root.visualFocus && root.clickable
            }
        }
    }

    // Hover must live on the row itself: Qt skips siblings once a hover-enabled child is hovered
    HoverHandler {
        id: rowHover
        enabled: root.clickable
        cursorShape: root.headerHovered ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    Column {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.paddingH
        anchors.rightMargin: root.paddingH
        spacing: root.bodyGap

        Item {
            id: headerLine
            visible: height > 0
            width: parent.width
            implicitHeight: Math.max(textColumn.implicitHeight, trailingArea.implicitHeight, leadingArea.visible ? leadingArea.implicitHeight : 0)
            height: Math.max(implicitHeight, (root.hasText || trailingSlot.children.length > 0 ? root.minHeight : 0) - root.paddingV * 2)

            Row {
                id: leadingArea
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingL
                visible: leadingSlot.children.length > 0 || root.iconName !== ""
                opacity: root.enabled ? 1 : SettingsMetrics.disabledOpacity

                Row {
                    id: leadingSlot
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS
                    visible: children.length > 0
                }

                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    active: root.iconName !== ""

                    sourceComponent: Rectangle {
                        width: root.iconBox ? SettingsMetrics.heroLeadingSize : Theme.iconSize
                        height: width
                        radius: Theme.fullRadius(width, height)
                        color: root.iconBox ? Theme.withAlpha(root.iconColor, Theme.tonalTintAlpha) : "transparent"

                        DIcon {
                            anchors.centerIn: parent
                            name: root.iconName
                            size: root.iconBox ? Theme.iconSizeMedium : Theme.iconSize
                            color: root.iconColor
                        }
                    }
                }
            }

            Column {
                id: textColumn
                anchors.left: leadingArea.visible ? leadingArea.right : parent.left
                anchors.leftMargin: leadingArea.visible ? Theme.spacingL : 0
                anchors.right: trailingArea.visible ? trailingArea.left : parent.right
                anchors.rightMargin: trailingArea.visible ? SettingsMetrics.rowContentSpacing : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS
                opacity: root.enabled ? 1 : SettingsMetrics.disabledOpacity
                visible: root.hasText

                StyledText {
                    id: titleText

                    readonly property bool resettable: root.resetInHeader && (root.modified || root.resetKeys.length > 0)
                    readonly property real chipTrailing: Theme.spacingXS + Theme.iconSizeSmall + SettingsMetrics.resetChipPaddingH
                    readonly property real firstLineHeight: lineCount > 0 ? contentHeight / lineCount : height

                    width: parent.width - (resettable ? chipTrailing : 0)
                    text: root.title
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: root.titleColor
                    wrapMode: root.singleLineTitle ? Text.NoWrap : Text.WordWrap
                    elide: root.singleLineTitle ? Text.ElideRight : Text.ElideNone
                    visible: root.title !== ""
                    horizontalAlignment: Text.AlignLeft

                    // The chip bleeds past the title box on every side, so the title never moves when a row turns modified
                    Loader {
                        id: resetChipLoader
                        anchors.left: parent.left
                        anchors.leftMargin: -SettingsMetrics.resetChipPaddingH
                        y: -SettingsMetrics.resetChipPaddingV
                        z: -1
                        width: SettingsMetrics.resetChipPaddingH + titleText.contentWidth + titleText.chipTrailing
                        height: titleText.height + SettingsMetrics.resetChipPaddingV * 2
                        active: root.modified && root.resetInHeader && root.title !== ""

                        sourceComponent: StyledButton {
                            id: chip
                            radius: Theme.fullRadius(width, height)
                            color: hovered || visualFocus || down ? SettingsMetrics.controlColor : Theme.withAlpha(SettingsMetrics.controlColor, 0)
                            enabled: root.enabled

                            Behavior on color {
                                ColorAnimation {
                                    duration: SettingsMetrics.fadeDuration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                                }
                            }
                            Accessible.name: I18n.tr("Reset to default")
                            Accessible.description: root.title
                            onClicked: root.resetRequested()

                            FocusRing {
                                visible: chip.visualFocus
                            }

                            DIcon {
                                anchors.right: parent.right
                                anchors.rightMargin: SettingsMetrics.resetChipPaddingH - Theme.spacingXXS
                                anchors.verticalCenter: parent.verticalCenter
                                name: "restart_alt"
                                size: Theme.iconSizeSmall
                                color: root.supportingContentColor
                            }

                            StateLayer {
                                control: chip
                                stateColor: root.contentColor
                                tooltipText: I18n.tr("Reset to default")
                            }
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    text: root.subtitle
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.subtitleColor
                    wrapMode: Text.WordWrap
                    visible: root.subtitle !== ""
                    horizontalAlignment: Text.AlignLeft
                }

                Row {
                    id: supportingSlot
                    topPadding: Theme.spacingXS
                    spacing: Theme.spacingXS
                    visible: children.length > 0
                }
            }

            Row {
                id: trailingArea
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: root.trailingOnTitleLine && titleText.visible ? textColumn.y + titleText.firstLineHeight / 2 - parent.height / 2 : 0
                spacing: Theme.spacingS
                visible: trailingSlot.children.length > 0 || root.showChevron || root.trailingBadge !== ""

                Row {
                    id: trailingSlot
                    spacing: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                }

                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    active: root.trailingBadge !== ""
                    sourceComponent: StyledText {
                        text: root.trailingBadge
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.trailingBadgeColor
                    }
                }

                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    active: root.showChevron
                    sourceComponent: DIcon {
                        name: "chevron_right"
                        size: Theme.iconSize
                        color: root.supportingContentColor
                        rotation: I18n.isRtl ? 180 : 0
                    }
                }
            }
        }

        Column {
            id: bodySlot
            width: parent.width
            spacing: Theme.spacingM
        }
    }
}
