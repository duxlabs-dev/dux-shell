import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var widgetData: ({})
    property var widgetDef: null
    property var host: null
    property bool live: true
    property string iconName: ""
    property string title: ""
    property string subtitle: ""
    // Dense pills drop the subtitle, so tiles whose title is a bare state name themselves here.
    property string denseTitle: ""
    property bool active: false
    property real columns: 4
    property real rows: 1
    property bool compact: columns <= 2 && rows === 1
    property bool small: false
    // Set by a background-less Quick tiles group.
    property bool bare: false
    property real quickContentWidth: 0
    readonly property real quickWidth: Math.max(bare ? CcMetrics.quickBareWidth : CcMetrics.iconBoxSize, quickContentWidth + (bare ? CcMetrics.quickBarePadding : Theme.spacingM * 2))
    property real bodyInset: small ? Math.max(0, (height - CcMetrics.iconBoxSize) / 2) : 0
    readonly property real bodyHeight: height - bodyInset * 2
    property bool toggle: !opensPage
    property Component expandedContent: null
    // Replaces the icon and labels inside the body; the chrome, focus and activation stay.
    property Component bodyContent: null
    property Component iconContent: null
    property real expandedMinimumHeight: CcMetrics.rowHeight
    readonly property Item expandedItem: expandedLoader.item
    readonly property bool expanded: expandedContent !== null && width >= CcMetrics.expandedTileMinWidth && height >= headerHeight + expandedMinimumHeight + tilePadding * 2 + Theme.spacingM
    readonly property real tilePadding: tall && !narrow ? CcMetrics.tallTilePadding : small ? CcMetrics.smallTilePadding : CcMetrics.tilePadding
    readonly property real baseIconExtent: Math.min(Math.max(CcMetrics.touchTarget, CcMetrics.iconBoxSize), bodyHeight - tilePadding * 2, width - tilePadding * 2)
    readonly property real iconExtent: stacked ? Math.max(0, Math.min(baseIconExtent, height - tilePadding * 2 - Theme.spacingS - titleLabel.implicitHeight)) : baseIconExtent
    readonly property real headerHeight: Math.max(baseIconExtent, (denseText ? Theme.fontSizeMedium + Theme.fontSizeSmall : Theme.fontSizeLarge + Theme.fontSizeMedium) + Theme.spacingS)
    readonly property bool stacked: tall && !expanded && width <= height
    readonly property bool narrow: width < CcMetrics.expandedTileMinWidth
    readonly property bool denseText: narrow || small || CcMetrics.denseTileText
    readonly property real labelHeight: titleLabel.implicitHeight + (showSubtitle ? Theme.spacingXXS + subtitleLabel.implicitHeight : 0)
    readonly property real textGap: CcMetrics.tileTextGap
    readonly property bool densePill: CcMetrics.dense && !tall && !expanded
    readonly property bool showSubtitle: {
        if (subtitle === "")
            return false;
        if (stacked)
            return height - tilePadding * 2 >= iconExtent + Theme.spacingS + titleLabel.implicitHeight + Theme.spacingXXS + subtitleLabel.implicitHeight;
        // Accessible.description still carries the hidden subtitle.
        if (densePill)
            return false;
        // Shrunk rows can overflow at larger font scales; small tiles keep their box.
        if (!CcMetrics.denseTileText || small)
            return true;
        return (expanded ? headerHeight : bodyHeight - tilePadding * 2) >= titleLabel.implicitHeight + Theme.spacingXXS + subtitleLabel.implicitHeight;
    }
    property bool showExpand: false
    property bool opensPage: false
    property color restIconColor: CcMetrics.tileInactiveIcon
    property Component tallContent: null
    // The tile's own state. The island disables a face while it fades in, and that must not restyle the tile.
    property bool available: true
    property bool interactive: true
    property bool iconBlinking: false
    property bool tooltips: true
    property real iconRotation: 0

    signal clicked
    signal expandClicked
    signal wheel(var wheelEvent)

    readonly property bool tall: height >= CcMetrics.gridRowUnit * 2
    readonly property bool hasIconBox: (showExpand || opensPage || expanded) && !compact
    readonly property bool showsActive: active && interactive
    readonly property real restRadius: {
        if (showsActive && Theme.shapeMorph)
            return Math.min(CcMetrics.tileActiveRadius, width / 2, bodyHeight / 2);
        return tall ? Math.min(CcMetrics.tallTileRadius, width / 2, height / 2) : CcMetrics.pillRadius(width, bodyHeight);
    }
    property bool acceptsInput: interactive && enabled
    readonly property bool bodyActive: showsActive && !hasIconBox && !bare
    readonly property color bodyColor: {
        if (bare)
            return "transparent";
        if (!available)
            return Theme.onSurface_12;
        return bodyActive ? CcMetrics.tileActiveColor : CcMetrics.tileInactiveColor;
    }
    readonly property color contentColor: {
        if (!available)
            return Theme.onSurface_38;
        return bodyActive ? CcMetrics.tileActiveContent : CcMetrics.tileInactiveContent;
    }
    readonly property color subtitleColor: {
        if (!available)
            return Theme.onSurface_38;
        return bodyActive ? CcMetrics.tileActiveContent : CcMetrics.tileInactiveSubtitle;
    }
    readonly property color iconColor: {
        if (!available)
            return Theme.onSurface_38;
        if (hasIconBox)
            return showsActive ? CcMetrics.tileActiveContent : CcMetrics.tileInactiveContent;
        // Without a body, toggles show their state in the icon tint alone.
        if (bare && showsActive)
            return CcMetrics.bareActiveIcon;
        if (bare && toggle)
            return CcMetrics.tileInactiveContent;
        return bodyActive ? CcMetrics.tileActiveContent : root.restIconColor;
    }
    readonly property color iconBoxColor: {
        if (!available)
            return Theme.onSurface_12;
        return showsActive ? CcMetrics.tileActiveColor : CcMetrics.iconBoxInactiveColor;
    }

    property real bodyRadius: bodyLayer.pressed && Theme.shapeMorph ? Math.min(Theme.cornerRadiusM, width / 2, bodyHeight / 2) : restRadius
    property real iconBoxRadius: {
        if (boxLayer.pressed && Theme.shapeMorph)
            return Math.min(Theme.cornerRadiusS, CcMetrics.iconBoxSize / 2);
        if (showsActive && Theme.shapeMorph)
            return Math.min(CcMetrics.iconBoxActiveRadius, CcMetrics.iconBoxSize / 2);
        return CcMetrics.pillRadius(CcMetrics.iconBoxSize, CcMetrics.iconBoxSize);
    }

    width: parent?.width ?? 0
    height: CcMetrics.tileHeight
    enabled: available
    activeFocusOnTab: acceptsInput
    Accessible.role: toggle && (!showExpand || compact) && !opensPage ? Accessible.CheckBox : Accessible.Button
    Accessible.checkable: toggle && (!showExpand || compact) && !opensPage
    Accessible.checked: active
    Accessible.name: title
    Accessible.description: subtitle
    Accessible.onPressAction: activate()
    Accessible.onToggleAction: {
        if (toggle && (!showExpand || compact) && !opensPage)
            activate();
    }

    function activate() {
        if (!acceptsInput)
            return;
        if (showExpand && !compact && !opensPage) {
            expandClicked();
            return;
        }
        clicked();
    }

    function expand() {
        if (!showExpand && !opensPage)
            return;
        expandClicked();
    }

    Keys.onPressed: event => {
        if (!acceptsInput)
            return;
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activate();
            event.accepted = true;
            break;
        }
    }

    // Animated so a half-row resize reads as the body shrinking.
    Behavior on bodyInset {
        enabled: CcMetrics.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    Behavior on bodyRadius {
        enabled: CcMetrics.animationsEnabled && !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    Behavior on iconBoxRadius {
        enabled: CcMetrics.animationsEnabled && !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    Rectangle {
        id: body

        anchors.fill: parent
        anchors.topMargin: root.bodyInset
        anchors.bottomMargin: root.bodyInset
        radius: root.bodyRadius
        color: root.bodyColor
        border.width: root.bare ? 0 : Theme.layerOutlineWidth
        border.color: Theme.outlineMedium

        Behavior on color {
            enabled: CcMetrics.animationsEnabled && !SettingsData.reduceMotion
            ColorAnimation {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        StateLayer {
            id: bodyLayer
            enabled: root.acceptsInput
            disabled: !root.acceptsInput
            anchors.bottomMargin: root.expanded ? root.height - root.headerHeight - root.tilePadding * 2 : 0
            stateColor: root.contentColor
            cornerRadius: root.bodyRadius
            tooltipText: root.tooltips && root.compact ? [root.title, root.subtitle].filter(text => text !== "").join(" · ") : ""
            onClicked: root.activate()
            onPressAndHold: root.expand()
            onWheel: wheelEvent => {
                wheelEvent.accepted = false;
                root.wheel(wheelEvent);
            }
        }

        FocusRing {
            radius: root.bodyRadius + Theme.focusRingOffset
            visible: root.activeFocus
        }

        DIcon {
            id: compactIcon
            anchors.centerIn: parent
            name: root.iconName
            size: root.small ? CcMetrics.iconBoxIconSize : CcMetrics.tileIconSize
            color: root.iconColor
            filled: root.showsActive
            rotation: root.iconRotation
            visible: root.compact && root.bodyContent === null && root.iconContent === null

            DBlink {
                target: compactIcon
                running: root.iconBlinking && root.compact && root.visible && root.live
            }
        }

        Loader {
            anchors.centerIn: parent
            active: root.compact && root.bodyContent === null && root.iconContent !== null
            sourceComponent: root.iconContent
        }

        Loader {
            id: bodyLoader
            anchors.fill: parent
            active: root.bodyContent !== null
            sourceComponent: root.bodyContent
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: root.tilePadding
            visible: !root.compact && root.bodyContent === null

            Rectangle {
                id: iconBox
                objectName: "tileIconBox"

                x: root.stacked && root.narrow ? (parent.width - width) / 2 : root.LayoutMirroring.enabled ? parent.width - width : 0
                y: root.stacked ? Math.max(0, (parent.height - height - Theme.spacingS - root.labelHeight) / 2) : root.expanded ? 0 : (parent.height - height) / 2
                width: root.iconExtent
                height: width
                radius: root.hasIconBox ? root.iconBoxRadius : 0
                color: root.hasIconBox ? root.iconBoxColor : "transparent"
                border.width: root.hasIconBox ? Theme.layerOutlineWidth : 0
                border.color: Theme.outlineMedium
                activeFocusOnTab: root.showExpand && root.toggle && root.acceptsInput
                Accessible.role: root.toggle ? Accessible.CheckBox : Accessible.Button
                Accessible.name: root.title
                Accessible.description: root.subtitle
                Accessible.checkable: root.toggle
                Accessible.checked: root.active
                Accessible.ignored: !root.showExpand || !root.toggle
                Accessible.onPressAction: activate()
                Accessible.onToggleAction: activate()

                function activate() {
                    if (root.acceptsInput && root.toggle)
                        root.clicked();
                }

                Keys.onPressed: event => {
                    if (!root.acceptsInput || !root.toggle)
                        return;
                    switch (event.key) {
                    case Qt.Key_Space:
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        activate();
                        event.accepted = true;
                        break;
                    }
                }

                DIcon {
                    id: tileIcon
                    anchors.centerIn: parent
                    name: root.iconName
                    size: root.hasIconBox ? CcMetrics.iconBoxIconSize : CcMetrics.tileIconSize
                    color: root.iconColor
                    filled: root.showsActive
                    rotation: root.iconRotation
                    visible: root.iconContent === null

                    DBlink {
                        target: tileIcon
                        running: root.iconBlinking && !root.compact && root.visible && root.live
                    }
                }

                Loader {
                    anchors.centerIn: parent
                    active: root.iconContent !== null && !root.compact
                    sourceComponent: root.iconContent
                }

                StateLayer {
                    id: boxLayer
                    visible: root.showExpand && root.toggle
                    enabled: visible && root.acceptsInput
                    disabled: !root.acceptsInput
                    stateColor: root.iconColor
                    cornerRadius: root.iconBoxRadius
                    onClicked: iconBox.activate()
                }

                FocusRing {
                    radius: root.iconBoxRadius + Theme.focusRingOffset
                    visible: iconBox.activeFocus
                }
            }

            Loader {
                id: meterLoader
                anchors.left: iconBox.right
                anchors.leftMargin: root.textGap
                anchors.right: parent.right
                y: iconBox.y
                height: iconBox.height
                active: root.stacked && !root.narrow && root.tallContent !== null
                sourceComponent: root.tallContent
            }

            Item {
                id: labels
                objectName: "tileLabels"
                x: root.stacked || root.LayoutMirroring.enabled ? 0 : root.baseIconExtent + root.textGap
                width: root.stacked ? parent.width : Math.max(0, parent.width - root.baseIconExtent - root.textGap)
                y: root.stacked ? iconBox.y + iconBox.height + Theme.spacingS : root.expanded ? (root.headerHeight - height) / 2 : (parent.height - height) / 2
                height: root.labelHeight

                StyledText {
                    id: titleLabel
                    objectName: "tileTitle"
                    width: parent.width
                    text: root.densePill && root.denseTitle !== "" ? root.denseTitle : root.title
                    color: root.contentColor
                    font.pixelSize: root.denseText ? Theme.fontSizeMedium : Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                    elide: Text.ElideRight
                    wrapMode: root.stacked ? Text.Wrap : Text.NoWrap
                    maximumLineCount: root.stacked ? 2 : 1
                    horizontalAlignment: root.stacked && root.narrow ? Text.AlignHCenter : Text.AlignLeft
                }

                StyledText {
                    id: subtitleLabel
                    objectName: "tileSubtitle"
                    y: titleLabel.implicitHeight + Theme.spacingXXS
                    width: parent.width
                    text: root.subtitle
                    color: root.subtitleColor
                    font.pixelSize: root.denseText ? Theme.fontSizeSmall : Theme.fontSizeMedium
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    horizontalAlignment: root.stacked && root.narrow ? Text.AlignHCenter : Text.AlignLeft
                    visible: root.showSubtitle
                }
            }

            Loader {
                id: expandedLoader
                objectName: "tileExpandedContent"
                anchors.left: parent.left
                anchors.right: parent.right
                y: root.headerHeight + Theme.spacingM
                height: Math.max(0, parent.height - y)
                active: root.expanded && root.live
                visible: root.expanded
                enabled: root.acceptsInput
                sourceComponent: root.expandedContent
            }
        }
    }
    Binding {
        target: expandedLoader.item
        property: "tile"
        value: root
        when: expandedLoader.item !== null && "tile" in expandedLoader.item
    }

    Binding {
        target: bodyLoader.item
        property: "tile"
        value: root
        when: bodyLoader.item !== null && "tile" in bodyLoader.item
    }
}
