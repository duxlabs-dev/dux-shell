pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Modules.DBar
import qs.Modules.SurfaceWidgets
import qs.DCommon.Widgets
import qs.Widgets

GridLayout {
    id: root

    property bool edgePlacement: false
    property bool widgetStyle: false
    property bool barLength: false
    property bool indicatorStyle: false
    property bool islandShape: false
    property bool statusStyle: false
    property real indicatorRoundness: -1
    property bool indicatorCompact: false
    property bool vertical: false
    property var choices: barModes
    property string selectedKey: activeBarMode
    signal selected(string key)
    onSelected: key => {
        if (!edgePlacement && !widgetStyle && !barLength && !indicatorStyle && !islandShape && !statusStyle)
            applyBarMode(key);
    }

    readonly property var barModes: [
        {
            "key": "standard",
            "label": I18n.tr("Standard")
        },
        {
            "key": "frame",
            "label": I18n.tr("Frame")
        },
        {
            "key": "island",
            "label": I18n.tr("Island")
        }
    ]
    readonly property real cardHeightRatio: 7.5
    readonly property real previewWidthRatio: 2.9
    readonly property real previewAspect: 0.62
    readonly property real previewStripRatio: 0.55
    readonly property real previewIslandRatio: 0.42
    readonly property var lengthPreviewRatios: ({
            "full": 1,
            "percent": 0.7,
            "fit": 0.45
        })
    readonly property real previewWidth: Math.round(Theme.iconSize * previewWidthRatio)
    readonly property real minimumCardWidth: previewWidth + Theme.spacingL * 2
    readonly property var targetConfig: {
        SettingsData.barConfigs;
        SettingsUiState.selectedBarId;
        const configs = (SettingsData.barConfigs || []).filter(cfg => !SettingsData.isDotBarConfig(cfg));
        const selected = SettingsData.getBarConfig(SettingsUiState.selectedBarId);
        return (selected && !SettingsData.isDotBarConfig(selected) ? selected : null) ?? configs.find(cfg => cfg.enabled) ?? configs[0] ?? null;
    }
    readonly property string activeBarMode: SettingsData.frameEnabled ? "frame" : (SettingsData.isIslandBarConfig(root.targetConfig) ? "island" : "standard")

    function applyBarMode(mode) {
        const target = root.targetConfig;
        switch (mode) {
        case "frame":
            if (SettingsData.frameEnabled)
                return;
            SettingsData.set("frameEnabled", true);
            return;
        case "island":
            if (!target)
                return;
            if (SettingsData.frameEnabled)
                SettingsData.set("frameEnabled", false);
            SettingsData.setBarIsland(target.id, true);
            return;
        default:
            if (SettingsData.frameEnabled)
                SettingsData.set("frameEnabled", false);
            if (target)
                SettingsData.setBarIsland(target.id, false);
            return;
        }
    }

    width: parent?.width ?? 0
    columns: {
        const count = Math.max(1, root.choices.length);
        const availableColumns = Math.max(1, Math.floor((width + columnSpacing) / (minimumCardWidth + columnSpacing)));
        return Math.ceil(count / Math.ceil(count / availableColumns));
    }
    columnSpacing: Theme.spacingS
    rowSpacing: Theme.spacingS

    Repeater {
        model: root.choices

        Rectangle {
            id: modeCard
            required property var modelData
            enabled: modelData.enabled ?? true
            opacity: enabled ? 1 : SettingsMetrics.disabledOpacity

            readonly property bool isActive: root.selectedKey === modelData.key

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            implicitWidth: root.minimumCardWidth
            implicitHeight: Math.max(Math.round(Theme.fontSizeMedium * root.cardHeightRatio), cardContent.implicitHeight + Theme.spacingM * 2)
            radius: Theme.cornerRadius
            color: SettingsMetrics.rowColor
            border.width: isActive ? Theme.outlineWidthFocused : Theme.layerOutlineWidth
            border.color: isActive ? Theme.primary : Theme.outlineMedium

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData.label
            Accessible.checkable: true
            Accessible.checked: isActive
            Accessible.onPressAction: root.selected(modelData.key)
            Keys.onSpacePressed: root.selected(modelData.key)
            Keys.onEnterPressed: root.selected(modelData.key)
            Keys.onReturnPressed: root.selected(modelData.key)

            FocusRing {
                id: cardRing
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Theme.primary
                opacity: cardRing.visible ? Theme.stateLayerFocus : modeMouse.containsMouse ? Theme.stateLayerHover : 0
            }

            Column {
                id: cardContent

                anchors.centerIn: parent
                width: Math.max(0, parent.width - Theme.spacingM * 2)
                spacing: Theme.spacingS

                Rectangle {
                    id: screenPreview
                    readonly property real edgePad: Math.max(2, Math.round(width * 0.045))
                    readonly property real stripSize: Math.round(width * 0.11)

                    width: Math.min(root.previewWidth, cardContent.width)
                    height: Math.round(width * root.previewAspect)
                    radius: Theme.spacingXS
                    color: SettingsMetrics.controlColor
                    border.width: Theme.outlineWidth
                    border.color: Theme.outline
                    anchors.horizontalCenter: parent.horizontalCenter

                    BarSegment {
                        visible: root.widgetStyle
                        anchors.centerIn: parent
                        scale: (screenPreview.width - screenPreview.edgePad * 2 - Theme.spacingS) / (Theme.iconSizeLarge * 3 + Theme.spacingXS * 2)
                        spacing: modeCard.modelData.key === "segments" ? BarMetrics.segmentGap : Theme.spacingXS

                        Repeater {
                            model: 3
                            BarPillSurface {
                                required property int index
                                width: Theme.iconSizeLarge
                                height: Theme.iconSizeLarge
                                thickness: Theme.iconSizeLarge
                                style: modeCard.modelData.key
                                joinedStart: style === "segments" && index > 0
                                joinedEnd: style === "segments" && index < 2
                                color: index === 1 ? Theme.primary : Theme.primaryContainer
                            }
                        }
                    }

                    Row {
                        id: indicatorPreview
                        readonly property real thickness: Theme.iconSizeLarge
                        readonly property string style: modeCard.modelData.key
                        visible: root.indicatorStyle
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS
                        scale: Math.min(1, (screenPreview.width - screenPreview.edgePad * 2 - Theme.spacingS) / Math.max(1, implicitWidth))

                        Repeater {
                            model: 3
                            BarPillSurface {
                                required property int index
                                readonly property bool active: index === 1
                                readonly property bool outlined: indicatorPreview.style === "cards" && !active
                                anchors.verticalCenter: parent.verticalCenter
                                width: indicatorPreview.thickness * BarMetrics.indicatorRatio(indicatorPreview.style, active ? "active" : "compact", root.indicatorCompact)
                                height: indicatorPreview.thickness * BarMetrics.indicatorRatio(indicatorPreview.style, active ? "activeSlim" : "slim", root.indicatorCompact)
                                thickness: Math.min(width, height)
                                radiusOverride: BarMetrics.indicatorRadius(indicatorPreview.style, thickness, root.indicatorRoundness)
                                color: outlined ? "transparent" : active ? Theme.primary : Theme.primaryContainer
                                border.width: outlined ? Theme.outlineWidth : 0
                                border.color: Theme.primaryContainer
                            }
                        }
                    }

                    Rectangle {
                        readonly property int edge: Number(modeCard.modelData.key)
                        readonly property bool vertical: edge === SettingsData.Position.Left || edge === SettingsData.Position.Right
                        visible: root.edgePlacement
                        x: edge === SettingsData.Position.Right ? parent.width - width - screenPreview.edgePad : screenPreview.edgePad
                        y: edge === SettingsData.Position.Bottom ? parent.height - height - screenPreview.edgePad : screenPreview.edgePad
                        width: vertical ? screenPreview.stripSize : parent.width - screenPreview.edgePad * 2
                        height: vertical ? parent.height - screenPreview.edgePad * 2 : screenPreview.stripSize
                        radius: Theme.fullRadius(width, height)
                        color: Theme.primary
                    }

                    Rectangle {
                        readonly property real span: root.lengthPreviewRatios[modeCard.modelData.key] ?? 1
                        readonly property real extent: (root.vertical ? parent.height : parent.width) - screenPreview.edgePad * 2
                        visible: root.barLength
                        x: root.vertical ? screenPreview.edgePad : Math.round((parent.width - width) / 2)
                        y: root.vertical ? Math.round((parent.height - height) / 2) : screenPreview.edgePad
                        width: root.vertical ? screenPreview.stripSize : Math.round(extent * span)
                        height: root.vertical ? Math.round(extent * span) : screenPreview.stripSize
                        radius: Theme.fullRadius(width, height)
                        color: Theme.primary
                    }

                    Rectangle {
                        visible: !root.widgetStyle && !root.edgePlacement && modeCard.modelData.key === "standard"
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: screenPreview.edgePad
                        height: screenPreview.stripSize
                        radius: Theme.fullRadius(width, height)
                        color: Theme.primary
                    }

                    Rectangle {
                        visible: !root.widgetStyle && modeCard.modelData.key === "frame"
                        anchors.fill: parent
                        anchors.margins: screenPreview.edgePad
                        radius: screenPreview.radius
                        color: "transparent"
                        border.width: Math.max(Theme.outlineWidthFocused, Math.round(screenPreview.stripSize * root.previewStripRatio))
                        border.color: Theme.primary
                    }

                    Rectangle {
                        visible: !root.widgetStyle && modeCard.modelData.key === "frame"
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: screenPreview.edgePad
                        height: screenPreview.stripSize
                        radius: screenPreview.radius
                        color: Theme.primary
                    }

                    BatteryMeter {
                        visible: root.statusStyle && modeCard.modelData.key !== "connectivity"
                        anchors.centerIn: parent
                        thickness: Theme.iconSizeLarge
                        meterStyle: modeCard.modelData.key
                    }

                    Row {
                        visible: root.statusStyle && modeCard.modelData.key === "connectivity"
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DIcon {
                            name: "wifi"
                            size: Theme.iconSize
                            color: Theme.primary
                        }

                        DIcon {
                            name: "bluetooth"
                            size: Theme.iconSize
                            color: Theme.primary
                        }
                    }

                    Item {
                        id: shapePreview
                        readonly property bool notch: modeCard.modelData.key === "notch"
                        readonly property real seamOverlap: 1
                        visible: root.islandShape
                        anchors.fill: parent

                        Rectangle {
                            id: shapeBody
                            x: Math.round((parent.width - width) / 2)
                            y: shapePreview.notch ? 0 : screenPreview.edgePad
                            width: Math.round(parent.width * root.previewIslandRatio)
                            height: Math.round(screenPreview.stripSize * 1.5)
                            radius: Theme.fullRadius(width, height)
                            topLeftRadius: shapePreview.notch ? 0 : radius
                            topRightRadius: shapePreview.notch ? 0 : radius
                            color: Theme.primary
                        }

                        GothCorner {
                            visible: shapePreview.notch
                            radius: screenPreview.stripSize
                            color: Theme.primary
                            corner: "bottomLeft"
                            x: shapeBody.x - radius + shapePreview.seamOverlap
                            y: 0
                        }

                        GothCorner {
                            visible: shapePreview.notch
                            radius: screenPreview.stripSize
                            color: Theme.primary
                            corner: "bottomRight"
                            x: shapeBody.x + shapeBody.width - shapePreview.seamOverlap
                            y: 0
                        }
                    }

                    Rectangle {
                        visible: !root.widgetStyle && modeCard.modelData.key === "island"
                        anchors.top: parent.top
                        anchors.topMargin: screenPreview.edgePad
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.round(parent.width * root.previewIslandRatio)
                        height: screenPreview.stripSize
                        radius: Theme.fullRadius(width, height)
                        color: Theme.primary
                    }
                }

                StyledText {
                    width: parent.width
                    text: modeCard.modelData.label
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: modeCard.isActive ? Theme.primary : Theme.surfaceText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }

            MouseArea {
                id: modeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    cardRing.pointerFocused = true;
                    modeCard.forceActiveFocus(Qt.MouseFocusReason);
                    root.selected(modeCard.modelData.key);
                }
            }
        }
    }
}
