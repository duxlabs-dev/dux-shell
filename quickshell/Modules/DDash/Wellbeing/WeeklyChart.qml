pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.DDash
import "Wellbeing.js" as Wellbeing
import "../../../DCommon/Common/WheelInput.js" as WheelInput

DCard {
    id: root

    property var days: []
    property date today: new Date()
    property real limitSeconds: 0
    property string selectedDate: Wellbeing.dateKey(today)
    property color controlColor: chipColor
    property real wheelDistance: 0
    property real dragStartX: 0

    readonly property var weeks: Wellbeing.weeksBack(days, today)
    readonly property int pageCount: weeks.length
    property int page: pageCount - 1
    readonly property int currentPage: pager.width > 0 ? Math.max(0, Math.min(pageCount - 1, Math.round(pager.contentX / pager.width))) : page
    readonly property int weekOffset: page - (pageCount - 1)
    readonly property var week: weeks[page] ?? []
    readonly property var selectedDay: week.find(day => day.date === selectedDate) ?? null
    readonly property bool showingToday: weekOffset === 0 && (selectedDay?.today ?? false)
    readonly property real peak: Math.max(limitSeconds, ...week.map(day => day.active))
    readonly property var axis: Wellbeing.axis(peak)
    readonly property real columnWidth: pager.width / Wellbeing.weekLength
    readonly property real barWidth: columnWidth * WellbeingMetrics.barWidthRatio
    readonly property real dayLabelHeight: Theme.fontSizeLarge + Theme.spacingS
    readonly property color barColor: Theme.primaryContainer
    readonly property color selectedColor: Theme.primary
    readonly property string weekTitle: {
        switch (weekOffset) {
        case 0:
            return I18n.tr("This week", "screen time chart title, the seven days ending today");
        case -1:
            return I18n.tr("Last week", "screen time chart title, the seven days before this week");
        default:
            return I18n.tr("%1 weeks ago", "screen time chart title, %1 is a number of weeks, 2 or more").arg(-weekOffset);
        }
    }
    readonly property string dayTitle: {
        if (!selectedDay)
            return "";
        switch (Wellbeing.daysAgo(selectedDay.date, today)) {
        case 0:
            return I18n.tr("Today");
        case 1:
            return I18n.tr("Yesterday");
        default:
            return Wellbeing.parseKey(selectedDay.date).toLocaleDateString(I18n.locale(), "ddd, d MMM");
        }
    }

    function yFor(seconds) {
        return plot.height * (1 - Math.min(1, seconds / axis.top));
    }

    function barHeight(seconds) {
        if (seconds <= 0)
            return 0;
        return Math.max(WellbeingMetrics.minBarHeight, plot.height - yFor(seconds));
    }

    function dayLabel(day) {
        return I18n.locale().dayName(day.weekday === 0 ? Wellbeing.weekLength : day.weekday, Locale.NarrowFormat);
    }

    function selectColumn(index) {
        const day = week[Math.max(0, Math.min(Wellbeing.weekLength - 1, index))];
        if (day)
            selectedDate = day.date;
    }

    function snapTo(index, animate) {
        snapAnim.stop();
        page = Math.max(0, Math.min(pageCount - 1, index));
        const target = page * pager.width;
        if (!animate || !DashMetrics.animationsEnabled) {
            pager.contentX = target;
            return;
        }
        snapAnim.to = target;
        snapAnim.start();
    }

    function showToday() {
        snapTo(pageCount - 1, weekOffset !== 0);
        selectedDate = Wellbeing.dateKey(today);
    }

    onPageCountChanged: snapTo(pageCount - 1, false)
    onPageChanged: {
        const weekday = Wellbeing.parseKey(selectedDate).getDay();
        const day = (weeks[page] ?? []).find(entry => entry.weekday === weekday);
        if (day)
            selectedDate = day.date;
    }

    restRadius: DashMetrics.cardRadius
    pad: Theme.spacingL
    Accessible.role: Accessible.Chart
    Accessible.name: I18n.tr("Weekly screen time", "chart title, screen time per day over the week")

    NumberAnimation {
        id: snapAnim

        readonly property bool atEdge: root.page === 0 || root.page === root.pageCount - 1

        target: pager
        property: "contentX"
        duration: atEdge ? Theme.expressiveDurations.expressiveEffects : Theme.expressiveDurations.expressiveDefaultSpatial
        easing.type: Easing.BezierSpline
        easing.bezierCurve: atEdge ? Theme.expressiveCurves.expressiveEffects : Theme.expressiveCurves.expressiveDefaultSpatial
    }

    Timer {
        id: settleTimer
        interval: WellbeingMetrics.settleDelay
        onTriggered: root.snapTo(root.currentPage, true)
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingM

        Item {
            width: parent.width
            height: Math.max(titles.height, navigation.height)

            Column {
                id: titles
                anchors.left: parent.left
                anchors.right: navigation.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                StyledText {
                    width: parent.width
                    text: root.weekTitle
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                    color: root.contentColor
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: root.selectedDay ? root.dayTitle + " · " + WellbeingService.formatDuration(root.selectedDay.active) : ""
                    font.pixelSize: Theme.fontSizeMedium
                    color: root.mutedColor
                    elide: Text.ElideRight
                }
            }

            Row {
                id: navigation
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DActionButton {
                    buttonSize: Theme.iconButtonSize
                    iconName: "chevron_left"
                    iconColor: root.contentColor
                    backgroundColor: root.controlColor
                    enabled: root.page > 0
                    Accessible.name: I18n.tr("Previous")
                    onClicked: root.snapTo(root.page - 1, true)
                }

                DActionButton {
                    buttonSize: Theme.iconButtonSize
                    iconName: "chevron_right"
                    iconColor: root.contentColor
                    backgroundColor: root.controlColor
                    enabled: root.weekOffset < 0
                    Accessible.name: I18n.tr("Next")
                    onClicked: root.snapTo(root.page + 1, true)
                }

                DActionButton {
                    buttonSize: Theme.iconButtonSize
                    iconName: "calendar_today"
                    iconColor: root.contentColor
                    backgroundColor: root.controlColor
                    enabled: !root.showingToday
                    Accessible.name: I18n.tr("Today")
                    onClicked: root.showToday()
                }
            }
        }

        Item {
            width: parent.width
            height: parent.height - y
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            Item {
                id: axisLabels
                anchors.left: parent.left
                anchors.top: plot.top
                anchors.bottom: plot.bottom
                width: WellbeingMetrics.axisLabelWidth

                Repeater {
                    model: root.axis.ticks

                    StyledText {
                        required property int modelData
                        anchors.right: axisLabels.right
                        y: root.yFor(modelData * Wellbeing.secondsPerHour) - height / 2
                        text: I18n.tr("%1h", "hours abbreviation, %1 is a number").arg(modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.mutedColor
                    }
                }
            }

            Item {
                id: plot
                anchors.left: axisLabels.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Theme.spacingS
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.dayLabelHeight + Theme.spacingS

                Repeater {
                    model: root.axis.ticks

                    DDivider {
                        required property int modelData
                        y: root.yFor(modelData * Wellbeing.secondsPerHour) - height / 2
                    }
                }
            }

            Shape {
                anchors.fill: plot
                visible: root.limitSeconds > 0
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: Theme.error
                    strokeWidth: Theme.outlineWidthFocused
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [3, 3]
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    startX: 0
                    startY: root.yFor(root.limitSeconds)

                    PathLine {
                        x: plot.width
                        y: root.yFor(root.limitSeconds)
                    }
                }
            }

            DFlickable {
                id: pager
                anchors.left: plot.left
                anchors.right: plot.right
                anchors.top: plot.top
                anchors.bottom: parent.bottom
                contentWidth: width * root.pageCount
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                wheelEnabled: false
                showScrollBar: false
                clip: true

                onWidthChanged: {
                    snapAnim.stop();
                    contentX = root.page * width;
                }
                onDragStarted: {
                    snapAnim.stop();
                    settleTimer.stop();
                    root.dragStartX = contentX;
                }
                onFlickStarted: {
                    const forward = contentX > root.dragStartX;
                    cancelFlick();
                    root.snapTo(forward ? Math.ceil(contentX / width) : Math.floor(contentX / width), true);
                }
                onMovementEnded: {
                    if (!snapAnim.running)
                        root.snapTo(root.currentPage, true);
                }

                Repeater {
                    model: root.weeks

                    Item {
                        id: weekPage

                        required property var modelData
                        required property int index

                        x: index * pager.width
                        width: pager.width
                        height: pager.height

                        Repeater {
                            model: weekPage.modelData

                            Item {
                                id: column

                                required property var modelData
                                required property int index
                                readonly property bool selected: modelData.date === root.selectedDate

                                x: index * root.columnWidth
                                width: root.columnWidth
                                height: weekPage.height

                                StyledRect {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: plot.height - height
                                    width: root.barWidth
                                    height: root.barHeight(column.modelData.active)
                                    radius: 0
                                    topLeftRadius: Theme.cornerRadiusS
                                    topRightRadius: Theme.cornerRadiusS
                                    color: column.selected ? root.selectedColor : root.barColor
                                }

                                StyledText {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: root.dayLabelHeight
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: root.dayLabel(column.modelData)
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: column.selected ? Theme.fontWeightBold : Theme.fontWeightMedium
                                    color: column.selected ? root.selectedColor : root.contentColor
                                }
                            }
                        }

                        HoverHandler {
                            enabled: weekPage.index === root.page
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            enabled: weekPage.index === root.page && root.columnWidth > 0
                            onTapped: eventPoint => root.selectColumn(Math.floor(eventPoint.position.x / root.columnWidth))
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: pager
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    if (wheel.angleDelta.x === 0 && wheel.pixelDelta.x === 0) {
                        wheel.accepted = false;
                        return;
                    }
                    snapAnim.stop();
                    if (WheelInput.isTouchpad(wheel)) {
                        pager.contentX = Math.max(0, Math.min(pager.contentWidth - pager.width, pager.contentX - wheel.pixelDelta.x));
                        settleTimer.restart();
                        return;
                    }
                    root.wheelDistance += wheel.angleDelta.x;
                    if (Math.abs(root.wheelDistance) < WellbeingMetrics.wheelNotch)
                        return;
                    const step = root.wheelDistance > 0 ? -1 : 1;
                    root.wheelDistance = 0;
                    root.snapTo(root.page + step, true);
                }
            }
        }
    }
}
