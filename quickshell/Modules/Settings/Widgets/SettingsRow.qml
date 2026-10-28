pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import qs.Common
import qs.Services
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
    property color trailingBadgeColor: supportingContentColor
    property bool paintBackground: !(parent?.isSettingsGroupHost ?? false)
    property real paddingH: SettingsMetrics.rowPaddingH
    property real paddingV: SettingsMetrics.rowPaddingV
    property color rowColor: SettingsMetrics.rowColor
    property bool active: false
    readonly property color contentColor: active ? Theme.onSelectedContainer : Theme.surfaceText
    readonly property color supportingContentColor: active ? Theme.onSelectedContainer : Theme.surfaceVariantText
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

    readonly property bool hasBody: bodySlot.height > 0
    readonly property bool hasText: title !== "" || subtitle !== ""
    readonly property bool isHighlighted: settingKey !== "" && SettingsSearchService.highlightSection === settingKey
    property bool highlighted: isHighlighted
    property bool inGroup: (groupItem.parent?.isSettingsGroupHost ?? false) || (groupItem.parent?.parent?.isSettingsGroupHost ?? false)
    readonly property bool isFirstInGroup: _edge(true)
    readonly property bool isLastInGroup: _edge(false)
    property bool dividerBefore: inGroup && !isFirstInGroup
    property real topRadius: isFirstInGroup ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
    property real bottomRadius: isLastInGroup ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
    property real minHeight: subtitle !== "" ? SettingsMetrics.rowMinHeightTwoLine : SettingsMetrics.rowMinHeight
    // Keyboard focus on the row or any control inside it tints the row, so navigation reads without a focus ring
    readonly property Item activeItem: Window.activeFocusItem
    readonly property bool focusWithin: (activeItem?.visualFocus ?? false) && _contains(activeItem)
    readonly property real headerBand: paddingV * 2 + headerLine.height
    readonly property bool headerHovered: rowHover.hovered && (!hasBody || rowHover.point.position.y < headerBand)

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
        const container = groupItem.parent;
        if (container?.isSettingsGroupHost)
            return container.isEdge(groupItem, first);
        const host = container?.parent;
        if (!host?.isSettingsGroupHost)
            return true;
        return host.isEdge(container, first) && _edgeInContainer(first);
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
    implicitHeight: paddingV * 2 + headerLine.height + (hasBody ? bodySlot.height + (headerLine.height > 0 ? Theme.spacingM : 0) : 0)

    SettingsSearchRegistration {
        target: root
        settingKey: root.settingKey
    }

    Rectangle {
        anchors.fill: parent
        visible: root.paintBackground
        color: root.active ? Theme.selectedContainer : root.highlighted ? Theme.blend(root.rowColor, Theme.primary, SettingsMetrics.highlightBlend) : root.rowColor
        border.width: root.inGroup ? SettingsMetrics.groupEdgeWidth : Theme.layerOutlineWidth
        border.color: Theme.outlineMedium

        Rectangle {
            x: root.paddingH
            width: parent.width - root.paddingH * 2
            height: Theme.dividerWidth
            visible: SettingsMetrics.continuousGroups && root.dividerBefore
            color: SettingsMetrics.groupDividerColor
        }
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.paintBackground && (root.active || root.highlighted)
        color: root.active ? Theme.selectedContainer : SettingsMetrics.rowHighlightColor
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
    }

    Rectangle {
        id: stateLayer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.hasBody && !root.focusWithin ? root.headerBand : root.height
        visible: root.clickable || root.focusWithin
        color: root.contentColor
        opacity: !root.enabled ? 0 : (clickControl.down ? Theme.stateLayerPressed : root.focusWithin ? Theme.stateLayerFocus : (root.headerHovered ? Theme.stateLayerHover : 0))
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: height < root.height ? 0 : root.bottomRadius
        bottomRightRadius: bottomLeftRadius

        Behavior on opacity {
            enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
            NumberAnimation {
                duration: SettingsMetrics.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }

    Item {
        id: pressSurface
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.hasBody ? root.headerBand : root.height

        DRipple {
            id: ripple
            visible: root.clickable
            rippleColor: root.contentColor
            topLeftRadius: root.topRadius
            topRightRadius: root.topRadius
            bottomLeftRadius: root.hasBody ? 0 : root.bottomRadius
            bottomRightRadius: bottomLeftRadius
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
        topLeftRadius: Math.max(0, root.topRadius - Theme.focusRingWidth / 2)
        topRightRadius: topLeftRadius
        bottomLeftRadius: Math.max(0, root.bottomRadius - Theme.focusRingWidth / 2)
        bottomRightRadius: bottomLeftRadius
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRingColor
        visible: root.visualFocus && root.clickable
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
        spacing: Theme.spacingM

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

                Rectangle {
                    id: leadingIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.iconBox ? SettingsMetrics.heroLeadingSize : Theme.iconSize
                    height: width
                    radius: Theme.fullRadius(width, height)
                    color: root.iconBox ? Theme.withAlpha(root.iconColor, Theme.tonalTintAlpha) : "transparent"
                    visible: root.iconName !== ""

                    DIcon {
                        anchors.centerIn: parent
                        name: root.iconName
                        size: root.iconBox ? Theme.iconSizeMedium : Theme.iconSize
                        color: root.iconColor
                    }
                }
            }

            Column {
                id: textColumn
                anchors.left: leadingArea.visible ? leadingArea.right : parent.left
                anchors.leftMargin: leadingArea.visible ? Theme.spacingL : 0
                anchors.right: resetButton.active ? resetButton.left : (trailingArea.visible ? trailingArea.left : parent.right)
                anchors.rightMargin: resetButton.active || trailingArea.visible ? SettingsMetrics.rowContentSpacing : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS
                opacity: root.enabled ? 1 : SettingsMetrics.disabledOpacity
                visible: root.hasText

                StyledText {
                    width: parent.width
                    text: root.title
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: root.titleColor
                    wrapMode: root.singleLineTitle ? Text.NoWrap : Text.WordWrap
                    elide: root.singleLineTitle ? Text.ElideRight : Text.ElideNone
                    visible: root.title !== ""
                    horizontalAlignment: Text.AlignLeft
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
            }

            Loader {
                id: resetButton
                anchors.right: trailingArea.visible ? trailingArea.left : parent.right
                anchors.rightMargin: trailingArea.visible ? Theme.spacingS : 0
                anchors.verticalCenter: parent.verticalCenter
                active: root.modified && root.resetInHeader
                visible: active

                sourceComponent: DActionButton {
                    buttonSize: Theme.iconButtonSize
                    iconName: "restart_alt"
                    iconSize: Theme.iconSizeMedium
                    iconColor: Theme.surfaceVariantText
                    tooltipText: I18n.tr("Reset to default")
                    Accessible.name: I18n.tr("Reset to default")
                    enabled: root.enabled
                    onClicked: root.resetRequested()
                }
            }

            Row {
                id: trailingArea
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS
                visible: trailingSlot.children.length > 0 || root.showChevron || root.trailingBadge !== ""

                Row {
                    id: trailingSlot
                    spacing: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.trailingBadge
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.trailingBadgeColor
                    visible: root.trailingBadge !== ""
                    anchors.verticalCenter: parent.verticalCenter
                }

                DIcon {
                    name: "chevron_right"
                    size: Theme.iconSize
                    color: root.supportingContentColor
                    rotation: I18n.isRtl ? 180 : 0
                    visible: root.showChevron
                    anchors.verticalCenter: parent.verticalCenter
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
