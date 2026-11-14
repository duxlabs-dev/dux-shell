pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

PanelWindow {
    id: root

    required property Item anchorButton
    required property var surfaceContext
    required property var options

    signal dismissed

    readonly property bool containsMouse: cardHover.hovered
    readonly property bool isVertical: options.position === SettingsData.Position.Left || options.position === SettingsData.Position.Right
    readonly property real screenWidth: screen?.width ?? 0
    readonly property real screenHeight: screen?.height ?? 0
    readonly property real screenShape: screenHeight > 0 ? screenWidth / screenHeight : 1
    readonly property real narrowestShape: 3 / 4
    readonly property real widestShape: screenShape * 4 / 3
    readonly property real compactExtent: screenHeight / 8
    readonly property real largestExtent: screenHeight / 6
    readonly property real titleHeight: Theme.iconSizeSmall + Theme.spacingS
    readonly property real flowLength: (isVertical ? screenHeight : screenWidth) - Theme.spacingXL * 2
    readonly property real typicalStride: (isVertical ? titleHeight + Theme.spacingXS + compactExtent : compactExtent * screenShape) + Theme.spacingS
    readonly property int tileLimit: Math.max(1, Math.floor(flowLength / typicalStride))
    readonly property var toplevels: anchorButton?.previewToplevels ?? []
    readonly property int tileCount: Math.min(toplevels.length, tileLimit)
    readonly property real shapeSum: {
        let sum = 0;
        for (let i = 0; i < tiles.count; i++)
            sum += tiles.itemAt(i)?.shape ?? screenShape;
        return sum;
    }
    readonly property real tileSpace: flowLength - Theme.spacingS * (tileCount + 1)
    readonly property real fittedExtent: isVertical ? tileSpace / Math.max(1, tileCount) - titleHeight - Theme.spacingXS : tileSpace / Math.max(1, shapeSum)
    readonly property real extent: Math.round(Math.min(largestExtent, fittedExtent))
    readonly property real tileHeight: titleHeight + Theme.spacingXS + extent
    readonly property bool shaped: {
        for (let i = 0; i < tiles.count; i++) {
            if (!tiles.itemAt(i)?.shaped)
                return false;
        }
        return tiles.count > 0;
    }
    property bool revealed: false
    readonly property point anchorPoint: (anchorButton ? surfaceContext.screenPoint(anchorButton, anchorButton.width / 2, anchorButton.height / 2) : null) ?? Qt.point(0, 0)
    readonly property real magnificationScale: options.magnification ? Math.max(1.05, Math.min(2.0, (options.magnificationScale ?? 130) / 100)) : 1.0
    readonly property real edgeOffset: surfaceContext.thickness * magnificationScale / 2 + Math.abs(anchorButton?.hoverAnimOffset ?? 0) * (magnificationScale - 1.0) + Theme.spacingS
    readonly property real cardX: {
        switch (options.position) {
        case SettingsData.Position.Left:
            return anchorPoint.x + edgeOffset;
        case SettingsData.Position.Right:
            return anchorPoint.x - edgeOffset - card.width;
        default:
            return Math.max(Theme.spacingS, Math.min(screenWidth - card.width - Theme.spacingS, anchorPoint.x - card.width / 2));
        }
    }
    readonly property real cardY: {
        switch (options.position) {
        case SettingsData.Position.Top:
            return anchorPoint.y + edgeOffset;
        case SettingsData.Position.Bottom:
            return anchorPoint.y - edgeOffset - card.height;
        default:
            return Math.max(Theme.spacingS, Math.min(screenHeight - card.height - Theme.spacingS, anchorPoint.y - card.height / 2));
        }
    }

    WlrLayershell.namespace: "dms:dock-window-preview"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    visible: toplevels.length > 0
    onVisibleChanged: {
        if (!visible)
            revealed = false;
    }
    onShapedChanged: {
        if (shaped)
            revealed = true;
    }
    color: "transparent"
    anchors {
        top: true
        left: true
    }
    margins.left: Math.round(cardX)
    margins.top: Math.round(cardY)
    implicitWidth: card.width
    implicitHeight: card.height

    WindowBlur {
        targetWindow: root
        surfaceColor: card.color
        blurEnabled: root.revealed
        blurWidth: card.width
        blurHeight: card.height
        blurRadius: Theme.windowRadius
    }

    Timer {
        interval: Theme.tooltipDelay / 2
        running: root.visible && !root.revealed
        onTriggered: root.revealed = true
    }

    Rectangle {
        id: card

        opacity: root.revealed ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shorterDuration
            }
        }

        width: tileFlow.width + Theme.spacingS * 2
        height: tileFlow.height + Theme.spacingXS + Theme.spacingS
        color: Theme.floatingSurface
        radius: Theme.windowRadius
        border.color: BlurService.borderColor
        border.width: BlurService.borderWidth

        HoverHandler {
            id: cardHover
        }

        Flow {
            id: tileFlow

            x: Theme.spacingS
            y: Theme.spacingXS
            flow: root.isVertical ? Flow.TopToBottom : Flow.LeftToRight
            spacing: Theme.spacingS

            Repeater {
                id: tiles

                model: root.tileCount

                delegate: Item {
                    id: tile

                    required property int index
                    readonly property var toplevel: root.toplevels[index] ?? null
                    readonly property var placement: CompositorService.toplevelPlacement(toplevel)
                    readonly property string placementLabel: {
                        if (Quickshell.screens.length < 2)
                            return "";
                        const output = SettingsData.getScreenDisplayName(Quickshell.screens.find(screen => screen.name === placement.output)) || placement.output;
                        return [placement.workspace, output].filter(text => text !== "").join(" · ");
                    }

                    // Latched: a capture drops its content while it switches windows.
                    property real shape: root.screenShape
                    property bool shaped: false

                    width: Math.round(root.extent * (root.isVertical ? root.screenShape : shape))
                    height: root.tileHeight

                    MouseArea {
                        id: tileArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.MiddleButton) {
                                tile.toplevel?.close();
                                return;
                            }
                            root.anchorButton?.activateWindow(tile.toplevel);
                            root.dismissed();
                        }
                    }

                    Item {
                        id: titleRow

                        width: parent.width
                        height: root.titleHeight

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingXS + Theme.spacingXXS
                            anchors.right: closeButton.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: tile.toplevel?.title || (root.anchorButton?.tooltipText ?? "")
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        DActionButton {
                            id: closeButton

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: root.titleHeight
                            iconSize: Theme.iconSizeSmall
                            iconName: "close"
                            Accessible.name: I18n.tr("Close")
                            onClicked: tile.toplevel?.close()
                        }
                    }

                    ClippingRectangle {
                        id: thumbnail

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: (root.tileHeight - root.extent) / 2
                        width: capture.hasContent ? capture.width : parent.width
                        height: capture.hasContent ? capture.height : root.extent
                        radius: Theme.cornerRadiusS
                        color: "transparent"
                        border.color: Theme.outlineHeavy
                        border.width: Theme.outlineWidth
                        contentUnderBorder: true

                        Image {
                            id: placeholder

                            anchors.centerIn: parent
                            width: Theme.iconSizeLarge
                            height: Theme.iconSizeLarge
                            sourceSize: Qt.size(width, height)
                            source: root.anchorButton?.appData ? Paths.getAppIcon(root.anchorButton.appData.appId, root.anchorButton.cachedDesktopEntry) : ""
                            asynchronous: true
                            visible: !capture.hasContent
                            opacity: 0

                            // Restarts whenever the capture is lost, so a tile reused for another window never flashes the icon.
                            SequentialAnimation {
                                running: !capture.hasContent

                                PropertyAction {
                                    target: placeholder
                                    property: "opacity"
                                    value: 0
                                }
                                PauseAnimation {
                                    duration: Theme.tooltipDelay
                                }
                                NumberAnimation {
                                    target: placeholder
                                    property: "opacity"
                                    to: 1
                                    duration: Theme.shortDuration
                                }
                            }
                        }

                        ScreencopyView {
                            id: capture

                            // A stopped view only captures again once its source is reassigned.
                            property bool stream: true

                            function latchShape() {
                                if (!hasContent || sourceSize.height <= 0)
                                    return;
                                tile.shape = Math.max(root.narrowestShape, Math.min(root.widestShape, sourceSize.width / sourceSize.height));
                                tile.shaped = true;
                            }

                            anchors.centerIn: parent
                            constraintSize: Qt.size(tile.width, root.extent)
                            captureSource: stream ? WindowCaptureService.captureSource(tile.toplevel) : null
                            live: true
                            onHasContentChanged: latchShape()
                            onSourceSizeChanged: latchShape()
                            onStopped: {
                                stream = false;
                                streamRetry.restart();
                            }
                        }

                        Timer {
                            id: streamRetry
                            interval: Theme.tooltipDelay
                            onTriggered: capture.stream = true
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.withAlpha(Theme.onSurface, tileArea.containsMouse ? Theme.stateLayerHover : 0)
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingXS
                            width: placementText.width + Theme.spacingS * 2
                            height: placementText.height + Theme.spacingXS * 2
                            radius: Theme.cornerRadius
                            color: Theme.chipSurface
                            visible: tile.placementLabel !== ""

                            // An eliding Text reports its elided width as implicitWidth once the text changes, so it cannot size itself.
                            TextMetrics {
                                id: placementMetrics

                                font: placementText.font
                                text: tile.placementLabel
                                elide: Text.ElideRight
                                elideWidth: thumbnail.width - Theme.spacingXS * 2 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: placementText

                                anchors.centerIn: parent
                                text: placementMetrics.elidedText
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Theme.fontWeightMedium
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.toplevels.length > root.tileLimit
                width: root.isVertical ? Math.round(root.extent * root.screenShape) : implicitWidth
                height: root.isVertical ? implicitHeight : root.tileHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "+" + (root.toplevels.length - root.tileLimit)
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }
}
