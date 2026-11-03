pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "BatteryHistory.js" as History
import "../../../DCommon/Common/WheelInput.js" as WheelInput

DCard {
    id: root

    property var samples: []
    property real rangeStart: 0
    property real rangeEnd: 1
    property string deviceName: ""
    readonly property real visibleDuration: 14400
    readonly property real rangeSpan: Math.max(1, rangeEnd - rangeStart)
    readonly property var segments: History.segments(samples, SettingsData.batteryLowThreshold)
    readonly property var gaps: History.gaps(samples)
    readonly property var hoverPoint: hoverArea.containsMouse ? History.pointAt(samples, rangeStart + (timeline.contentX + hoverArea.mouseX) / timeline.contentWidth * rangeSpan, Theme.iconButtonSize / 2 / timeline.contentWidth * rangeSpan) : null
    readonly property string timeFormat: SettingsData.use24HourClock ? "HH:mm" : "h:mm ap"
    readonly property int tickHours: [1, 2, 3, 4, 6, 12].find(hours => hours * 3600 / visibleDuration * timeline.width >= tickMetrics.implicitWidth + Theme.spacingL) ?? 24
    readonly property real tickPage: Math.floor(viewStart / visibleDuration) * visibleDuration
    readonly property var ticks: History.ticks(Math.max(rangeStart, tickPage - visibleDuration), Math.min(rangeEnd, tickPage + visibleDuration * 2), tickHours)
    readonly property bool scrollable: timeline.contentWidth > timeline.width + Theme.spacingXS
    readonly property real viewStart: rangeStart + timeline.contentX / Math.max(1, timeline.width) * visibleDuration
    readonly property real viewEnd: Math.min(rangeEnd, viewStart + visibleDuration)
    property bool followLatest: true

    implicitHeight: Theme.iconButtonSize * 4 + pad * 2 + navigation.height + Theme.spacingS + (deviceName ? deviceLabel.implicitHeight + Theme.spacingS : 0)
    restRadius: Theme.cornerRadiusL
    pad: Theme.spacingM
    Accessible.name: I18n.tr("History")

    onRangeEndChanged: {
        if (followLatest)
            latestTimer.restart();
    }

    function pointX(time) {
        return (time - rangeStart) / rangeSpan * timeline.contentWidth;
    }

    function pointY(value) {
        return Theme.spacingXS + (1 - value / 100) * (timeline.height - Theme.spacingXS * 2);
    }

    function gapPath(kind) {
        return gaps.filter(gap => History.kind(gap[0], SettingsData.batteryLowThreshold) === kind).map(gap => `M ${pointX(gap[0][0])} ${pointY(gap[0][1])} L ${pointX(gap[1][0])} ${pointY(gap[1][1])}`).join(" ");
    }

    function kindColor(kind) {
        switch (kind) {
        case "plugged":
            return Theme.primary;
        case "low":
            return Theme.error;
        default:
            return Theme.success;
        }
    }

    function scrollTo(offset) {
        timeline.cancelFlick();
        const next = Math.max(0, Math.min(timeline.contentWidth - timeline.width, offset));
        if (next === timeline.contentX)
            return false;
        timeline.contentX = next;
        followLatest = timeline.atXEnd;
        return true;
    }

    function showLatest() {
        scrollTo(timeline.contentWidth - timeline.width);
        followLatest = true;
    }

    Timer {
        id: latestTimer
        interval: 0
        onTriggered: root.showLatest()
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingS

        StyledText {
            id: deviceLabel
            width: parent.width
            text: root.deviceName
            visible: text !== ""
            color: Theme.onSurfaceVariant
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideMiddle
        }

        Item {
            id: navigation
            width: parent.width
            height: Theme.buttonHeightXS
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            StyledText {
                anchors.left: parent.left
                anchors.right: actions.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const point = root.hoverPoint;
                    if (point) {
                        const date = new Date(point[0] * 1000);
                        const time = `${date.toLocaleDateString(I18n.locale(), "MMM d")} ${date.toLocaleTimeString(I18n.locale(), root.timeFormat)}`;
                        const state = BatteryService.translateBatteryState(point[2]);
                        return point[2] === 0 ? `${time} · ${state}` : `${time} · ${Math.round(point[1])}% · ${state}`;
                    }
                    const start = new Date(root.viewStart * 1000).toLocaleDateString(I18n.locale(), "MMM d");
                    const end = new Date(root.viewEnd * 1000).toLocaleDateString(I18n.locale(), "MMM d");
                    return start === end ? start : `${start} - ${end}`;
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
            }

            Row {
                id: actions
                anchors.right: parent.right
                spacing: Theme.spacingXXS
                LayoutMirroring.enabled: false
                LayoutMirroring.childrenInherit: true

                DActionButton {
                    buttonSize: Theme.buttonHeightXS
                    iconName: "chevron_left"
                    Accessible.name: I18n.tr("Previous")
                    enabled: !timeline.atXBeginning
                    onClicked: root.scrollTo(timeline.contentX - timeline.width)
                }

                DActionButton {
                    buttonSize: Theme.buttonHeightXS
                    iconName: "today"
                    Accessible.name: I18n.tr("Today")
                    enabled: !timeline.atXEnd
                    onClicked: root.showLatest()
                }

                DActionButton {
                    buttonSize: Theme.buttonHeightXS
                    iconName: "chevron_right"
                    Accessible.name: I18n.tr("Next")
                    enabled: !timeline.atXEnd
                    onClicked: root.scrollTo(timeline.contentX + timeline.width)
                }
            }
        }

        Item {
            id: chart
            width: parent.width
            height: parent.height - navigation.height - timeLabels.height - parent.spacing * 2 - (deviceLabel.visible ? deviceLabel.height + parent.spacing : 0)
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            Repeater {
                model: 3

                Rectangle {
                    required property int index
                    width: timeline.width
                    height: Theme.dividerWidth
                    y: Theme.spacingXS + index * (chart.height - Theme.spacingXS * 2) / 2
                    color: Theme.outlineVariant
                }
            }

            DFlickable {
                id: timeline
                width: parent.width - percentLabel.implicitWidth - Theme.spacingS
                height: parent.height
                contentWidth: width * Math.max(1, (root.rangeEnd - root.rangeStart) / root.visibleDuration)
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                wheelEnabled: false
                interactive: root.scrollable
                clip: true
                activeFocusOnTab: root.scrollable
                Accessible.role: Accessible.Chart
                Accessible.name: I18n.tr("History")

                onContentWidthChanged: {
                    if (root.followLatest)
                        latestTimer.restart();
                }
                onMovementStarted: root.followLatest = false
                onMovementEnded: root.followLatest = atXEnd

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Left:
                        root.scrollTo(contentX - width / 2);
                        break;
                    case Qt.Key_Right:
                        root.scrollTo(contentX + width / 2);
                        break;
                    case Qt.Key_Home:
                        root.scrollTo(0);
                        break;
                    case Qt.Key_End:
                        root.showLatest();
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                Item {
                    width: timeline.contentWidth
                    height: timeline.height

                    Repeater {
                        model: root.segments

                        DSparkline {
                            required property var modelData
                            anchors.fill: parent
                            values: modelData.samples.map(sample => sample[1])
                            xValues: modelData.samples.map(sample => sample[0])
                            minimumX: root.rangeStart
                            maximumX: root.rangeEnd
                            maximum: 100
                            curved: false
                            lineColor: root.kindColor(modelData.kind)
                            lineWidth: Theme.outlineWidthFocused
                            insetTop: Theme.spacingXS
                            insetBottom: Theme.spacingXS
                            showDots: values.length === 1
                            dotRadius: Theme.spacingXXS
                        }
                    }

                    Repeater {
                        model: ["plugged", "normal", "low"]

                        Shape {
                            id: gapShape
                            required property string modelData
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: root.kindColor(gapShape.modelData)
                                strokeWidth: Theme.outlineWidthFocused
                                strokeStyle: ShapePath.DashLine
                                dashPattern: [2, 2]
                                fillColor: "transparent"
                                capStyle: ShapePath.FlatCap

                                PathSvg {
                                    path: root.gapPath(gapShape.modelData)
                                }
                            }
                        }
                    }

                    StyledRect {
                        visible: root.hoverPoint !== null
                        x: root.pointX(root.hoverPoint?.[0] ?? 0) - width / 2
                        width: Theme.dividerWidth
                        height: parent.height
                        color: Theme.outline
                    }

                    StyledRect {
                        visible: root.hoverPoint !== null && root.hoverPoint[2] !== 0
                        x: root.pointX(root.hoverPoint?.[0] ?? 0) - width / 2
                        y: root.pointY(root.hoverPoint?.[1] ?? 0) - height / 2
                        width: Theme.spacingS
                        height: width
                        radius: width / 2
                        color: root.hoverPoint ? root.kindColor(History.kind(root.hoverPoint, SettingsData.batteryLowThreshold)) : "transparent"
                    }
                }
            }

            MouseArea {
                id: hoverArea
                anchors.fill: timeline
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
                onWheel: wheel => {
                    if (!WheelInput.isHorizontal(wheel) || !root.scrollable) {
                        wheel.accepted = false;
                        return;
                    }
                    const pixels = WheelInput.isTouchpad(wheel) ? WheelInput.dominantDelta(wheel.pixelDelta) : 0;
                    const steps = WheelInput.dominantDelta(wheel.angleDelta) / 120;
                    root.scrollTo(timeline.contentX - (pixels || steps * timeline.mouseWheelSpeed));
                    wheel.accepted = true;
                }
            }

            FocusRing {
                anchors.fill: timeline
                radius: Theme.cornerRadiusXS
                visible: timeline.activeFocus
            }

            StyledText {
                id: percentLabel
                anchors.right: parent.right
                y: Theme.spacingXS - height / 2
                text: "100%"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
            }

            Repeater {
                model: [50, 0]

                StyledText {
                    required property int modelData
                    anchors.right: parent.right
                    y: Theme.spacingXS + (1 - modelData / 100) * (chart.height - Theme.spacingXS * 2) - height / 2
                    text: modelData + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                }
            }
        }

        Item {
            id: timeLabels
            width: timeline.width
            height: tickMetrics.height
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            StyledText {
                id: tickMetrics
                text: new Date(2000, 0, 1, 12).toLocaleTimeString(I18n.locale(), root.timeFormat)
                font.pixelSize: Theme.fontSizeSmall
                visible: false
            }

            StyledText {
                id: nowLabel
                anchors.right: parent.right
                visible: timeline.atXEnd
                text: I18n.tr("now")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
            }

            Repeater {
                model: root.ticks

                StyledText {
                    required property real modelData
                    x: root.pointX(modelData) - timeline.contentX - width / 2
                    visible: x >= 0 && x + width <= (nowLabel.visible ? nowLabel.x - Theme.spacingS : timeLabels.width)
                    text: {
                        const time = new Date(modelData * 1000);
                        return time.getHours() === 0 ? time.toLocaleDateString(I18n.locale(), "MMM d") : time.toLocaleTimeString(I18n.locale(), root.timeFormat);
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                }
            }
        }
    }
}
