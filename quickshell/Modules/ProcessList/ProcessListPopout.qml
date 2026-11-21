import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import qs.Common
import qs.Modules.ProcessList
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "ProcessColumns.js" as ProcessColumns

DPopout {
    id: processListPopout

    layerNamespace: "dms:process-list-popout"

    property var parentWidget: null
    property var triggerScreen: null
    property string style: "processes"
    property string deviceKey: ""
    property string entryType: ""
    // Until the close animation ends, so the contents keep their size and data while the popout shrinks away.
    property bool shown: false

    readonly property real compactWidth: Math.round(Theme.fontSizeMedium * 30)
    readonly property real wideWidth: Math.round(Theme.fontSizeMedium * 46)

    signal configured
    signal presenting

    function hide() {
        close();
        processContextMenu.dismiss();
    }

    function show() {
        open();
    }

    function configure(spec) {
        style = spec.style;
        deviceKey = spec.device ?? "";
        entryType = spec.entryType ?? "";
        processContextMenu.dismiss();
        configured();
    }

    popupWidth: Math.min(style === "compact" ? compactWidth : wideWidth, (screen?.width ?? Screen.width) - Theme.spacingL * 2)
    popupHeight: Math.min(contentLoader.item?.implicitHeight ?? 0, Math.max(0, (screen?.height ?? Screen.height) - Theme.barHeight - Theme.spacingXL * 2))
    triggerWidth: 55
    positioning: ""
    screen: triggerScreen
    shouldBeVisible: false

    onBackgroundClicked: {
        processContextMenu.dismiss();
        close();
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            presenting();
            shown = true;
        } else {
            processContextMenu.dismiss();
        }
    }
    onPopoutClosed: shown = false

    ProcessContextMenu {
        id: processContextMenu
        transientSurfaceTracker: processListPopout.transientSurfaceTracker
    }

    content: Component {
        Rectangle {
            id: processListContent

            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            implicitHeight: styleLoader.implicitHeight + PopoutMetrics.contentGap + monitorButton.implicitHeight + PopoutMetrics.contentPadding * 2
            radius: Theme.cornerRadius
            color: "transparent"
            clip: true
            focus: true

            property Item seenItem: null

            function focusOverview() {
                const overview = styleLoader.item as SysmonOverviewContent;
                if (overview && processListPopout.shouldBeVisible)
                    overview.focusExpanded();
            }

            // An item that has been on screen is replaced, so every open and retarget starts with fresh state.
            function renewIfSeen() {
                if (styleLoader.item !== seenItem)
                    return;
                styleLoader.active = false;
                styleLoader.active = true;
            }

            function markSeen() {
                if (processListPopout.shouldBeVisible)
                    seenItem = styleLoader.item;
            }

            function retarget() {
                if (!processListPopout.shouldBeVisible)
                    return;
                renewIfSeen();
                markSeen();
            }

            Component.onCompleted: {
                processContextMenu.parent = processListContent;
                processContextMenu.parentFocusItem = processListContent;
            }

            Connections {
                target: processListPopout
                function onOpened() {
                    Qt.callLater(processListContent.markSeen);
                    Qt.callLater(processListContent.focusOverview);
                }
                // Deferred: a click on the open row configures first and only then closes.
                function onConfigured() {
                    Qt.callLater(processListContent.retarget);
                }
                // Before the contents turn active, so a reused item never requests data.
                function onPresenting() {
                    processListContent.renewIfSeen();
                }
            }

            Keys.onPressed: event => {
                if (processContextMenu.menuOpen || processContextMenu.confirmationOpen)
                    return;
                if (event.key === Qt.Key_Escape) {
                    processListPopout.close();
                    event.accepted = true;
                }
            }

            Loader {
                id: styleLoader
                anchors.fill: parent
                anchors.margins: PopoutMetrics.contentPadding
                anchors.bottomMargin: PopoutMetrics.contentPadding + PopoutMetrics.contentGap + monitorButton.implicitHeight
                sourceComponent: {
                    switch (processListPopout.style) {
                    case "compact":
                        return compactComponent;
                    case "device":
                        return deviceComponent;
                    case "overview":
                        return overviewComponent;
                    }
                    return processesComponent;
                }
                onLoaded: Qt.callLater(processListContent.focusOverview)
            }

            SysmonMonitorButton {
                id: monitorButton
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: PopoutMetrics.contentPadding
                target: {
                    const item = styleLoader.item;
                    return (item as SysmonCompactContent)?.monitorTarget ?? (item as SysmonDeviceContent)?.monitorTarget ?? (item as SysmonOverviewContent)?.monitorTarget ?? "processes";
                }
            }

            Component {
                id: compactComponent

                SysmonCompactContent {
                    deviceKey: processListPopout.deviceKey
                    entryType: processListPopout.entryType
                    active: processListPopout.shown
                }
            }

            Component {
                id: deviceComponent

                SysmonDeviceContent {
                    deviceKey: processListPopout.deviceKey
                    entryType: processListPopout.entryType
                    active: processListPopout.shown
                }
            }

            Component {
                id: overviewComponent

                SysmonOverviewContent {
                    deviceKey: processListPopout.deviceKey
                    entryType: processListPopout.entryType
                    active: processListPopout.shown
                }
            }

            Component {
                id: processesComponent

                ColumnLayout {
                    id: processesContent

                    readonly property int reservedRows: 8
                    // Resource columns carry their own process data, which only flows while the column is shown.
                    readonly property var columns: {
                        const sort = DgopService.currentSort;
                        const cols = ProcessColumns.POPOUT_COLUMNS.slice();
                        if (ProcessColumns.modulesFor([sort]).length > 0)
                            cols[cols.length - 1] = sort;
                        return cols;
                    }

                    Keys.onPressed: event => {
                        if (processContextMenu.menuOpen || processContextMenu.confirmationOpen || event.key === Qt.Key_Escape)
                            return;
                        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                            searchField.forceActiveFocus();
                            event.accepted = true;
                            return;
                        }
                        processesView.handleKey(event);
                    }

                    function focusSearch() {
                        if (processListPopout.shouldBeVisible)
                            searchField.forceActiveFocus();
                    }

                    spacing: PopoutMetrics.contentGap

                    Component.onCompleted: Qt.callLater(focusSearch)

                    Connections {
                        target: processListPopout
                        function onOpened() {
                            Qt.callLater(processesContent.focusSearch);
                        }
                    }

                    DeviceSummaryTiles {
                        Layout.fillWidth: true
                        active: processListPopout.shown
                        deviceKey: processListPopout.deviceKey
                        entryType: processListPopout.entryType
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        // The chips wrap into a column until the row has its width.
                        Layout.preferredHeight: searchField.implicitHeight
                        spacing: Theme.spacingM

                        DSearchField {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.minimumWidth: Theme.fontSizeMedium * 8
                            placeholderText: I18n.tr("Search", "search field placeholder") + "…"
                            ignoreUpDownKeys: true
                            keyForwardTargets: [processesContent]
                            onInputFocusedChanged: {
                                if (inputFocused)
                                    processesView.clearSelection();
                            }
                        }

                        ProcessFilterChips {
                            Layout.preferredWidth: singleRowWidth
                        }
                    }

                    ProcessesView {
                        id: processesView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: ProcessListMetrics.headerHeight + Theme.spacingM + processesContent.reservedRows * rowHeight + (processesContent.reservedRows - 1) * Theme.groupedListGap
                        active: processListPopout.shown
                        searchText: searchField.text
                        contextMenu: processContextMenu
                        columns: processesContent.columns
                    }
                }
            }
        }
    }
}
