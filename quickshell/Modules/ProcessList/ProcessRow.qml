import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import Quickshell.Widgets
import "ProcessColumns.js" as ProcessColumns
import "../../Services/ProcessSort.js" as ProcessSort

DListItem {
    id: root

    required property var process
    property real rowHeight: ProcessListMetrics.rowHeight
    property bool isExpanded: false
    readonly property string command: process?.command ?? ""
    readonly property string fullCommand: process?.fullCommand ?? command

    property var columns: ProcessColumns.DEFAULT_COLUMNS
    readonly property int childCount: process?.childCount ?? 0
    readonly property var appEntry: ProcessListMetrics.appEntry(process)
    readonly property string displayName: appEntry?.name || command

    // The part of a sideways-scrolling table that is on screen; the details stay inside it.
    property real detailX: 0
    property real detailWidth: -1

    signal actionRequested(string action)

    readonly property real leadWidth: ProcessListMetrics.appIconSize + Theme.spacingS
    readonly property real cellsWidth: columns.reduce((sum, id) => sum + cellWidth(id) + Theme.spacingXS, 0)
    readonly property real nameWidth: Math.max(0, cells.width - leadWidth - Theme.spacingXS - cellsWidth)

    function cellWidth(id) {
        return Theme.fontSizeSmall * (ProcessColumns.COLUMNS.find(c => c.id === id)?.width ?? 6);
    }

    listView: null
    color: surfaceColor

    height: root.rowHeight + (isExpanded && details.item ? details.item.implicitHeight + Theme.spacingXS + Theme.spacingS : 0)
    // No clip: a clip rectangle that changes every frame makes the scene graph rebatch the whole strip each frame.
    // The open row draws over the rows sliding out from under its strip instead.
    z: height > rowHeight ? 1 : 0

    // Opening one strip closes another; animating both shows where the selection went.
    Behavior on height {
        enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
        NumberAnimation {
            id: heightSlide
            duration: Theme.expressiveDurations.expressiveDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            onRunningChanged: {
                if (!running)
                    Qt.callLater(details.release);
            }
        }
    }

    onIsExpandedChanged: {
        if (isExpanded)
            return;
        details.keepAlive = true;
        Qt.callLater(details.release);
    }
    Accessible.name: command
    Accessible.description: fullCommand

    Rectangle {
        width: parent.width
        height: root.rowHeight
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.height > root.rowHeight ? root.radius : root.bottomLeftRadius
        bottomRightRadius: bottomLeftRadius
        color: Theme.selectedContainer
        visible: root.isSelected || root.visualFocus
    }

    Row {
        id: cells
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.spacingL
        anchors.rightMargin: Theme.spacingL
        height: root.rowHeight
        spacing: Theme.spacingXS

        Item {
            width: root.leadWidth
            height: root.rowHeight

            IconImage {
                id: appIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: ProcessListMetrics.appIconSize
                height: width
                source: root.command ? Paths.getAppIcon(root.appEntry?.id ?? root.command, root.appEntry) : ""
                smooth: true
                asynchronous: true
                visible: status === Image.Ready
            }

            Rectangle {
                anchors.fill: appIcon
                visible: !appIcon.visible
                radius: Theme.cornerRadiusXS
                color: Theme.surfaceContainerHighest

                StyledText {
                    anchors.centerIn: parent
                    text: root.command.charAt(0).toUpperCase()
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceVariantText
                }
            }
        }

        StyledText {
            id: nameText
            width: root.nameWidth
            height: root.rowHeight
            verticalAlignment: Text.AlignVCenter
            text: root.childCount > 0 ? root.displayName + " (" + root.childCount + ")" : root.displayName
            font.pixelSize: Theme.fontSizeMedium
            color: root.contentColor
            textFormat: Text.PlainText
            maximumLineCount: 1
            elide: Text.ElideRight

            MouseArea {
                id: nameHover
                anchors.fill: parent
                enabled: root.childCount > 0 || root.displayName !== root.command
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: {
                    if (containsMouse) {
                        rowTip.text = (root.displayName !== root.command ? root.command : "");
                        rowTip.target = nameText;
                        rowTip.hoverArea = nameHover;
                    } else if (rowTip.hoverArea === nameHover) {
                        rowTip.hoverArea = null;
                    }
                }
            }
        }

        Repeater {
            model: root.columns

            StyledText {
                id: cell

                required property string modelData
                readonly property var col: ProcessColumns.COLUMNS.find(c => c.id === modelData) ?? ({})
                readonly property var raw: ProcessColumns.formatCell(modelData, root.process ?? ({}))
                readonly property bool absent: raw === null
                readonly property bool waiting: absent && DgopService.unlockLoading
                readonly property bool zero: !cell.absent && ProcessSort.rawValue(cell.modelData, root.process ?? ({})) === 0

                width: root.cellWidth(modelData)
                height: root.rowHeight
                rightPadding: Theme.spacingS
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                font.features: {
                    "tnum": 1
                }
                text: cell.waiting ? "" : cell.absent ? "—" : cell.modelData === "status" ? ProcessListMetrics.statusLabel(cell.raw) : cell.raw
                font.pixelSize: Theme.fontSizeSmall
                color: cell.absent || cell.zero ? Theme.surfaceVariantText : cell.col.meter ? root.contentColor : root.supportingContentColor

                Loader {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    active: cell.waiting
                    sourceComponent: DSpinner {
                        size: Theme.fontSizeSmall
                    }
                }

                MouseArea {
                    id: absentArea
                    anchors.fill: parent
                    enabled: cell.absent
                    hoverEnabled: enabled
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: {
                        if (containsMouse) {
                            const reason = ProcessColumns.absentReason(cell.modelData, root.process);
                            rowTip.text = reason === "unmonitored" ? I18n.tr("Monitoring off", "GPU monitoring is turned off in settings") : reason === "unknown" ? I18n.tr("Unknown", "process network rate that could not be measured") : I18n.tr("Not readable without privileges", "process value that needs root access to read");
                            rowTip.target = cell;
                            rowTip.hoverArea = absentArea;
                        } else if (rowTip.hoverArea === absentArea) {
                            rowTip.hoverArea = null;
                        }
                    }
                }
            }
        }
    }

    // One tooltip per row, created on first hover: building one up front for every row made sorting slow.
    DTooltipHost {
        id: rowTip
        multiline: true
    }

    Loader {
        id: details
        x: root.detailX + Theme.spacingL
        width: (root.detailWidth >= 0 ? root.detailWidth : root.width) - Theme.spacingL * 2
        anchors.top: parent.top
        anchors.topMargin: root.rowHeight + Theme.spacingXS
        // Kept while the row slides closed, released on a later event loop turn: releasing it changes root.height,
        // so a binding that read height or the slide state here looped.
        property bool keepAlive: false
        active: root.isExpanded || keepAlive
        asynchronous: true

        function release() {
            if (!heightSlide.running)
                keepAlive = false;
        }
        opacity: root.isExpanded ? 1 : 0

        Behavior on opacity {
            enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }

        sourceComponent: ProcessDetailStrip {
            process: root.process
            onActionRequested: action => root.actionRequested(action)
        }
    }
}
