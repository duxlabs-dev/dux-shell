import QtQuick
import QtQuick.Layouts
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
    property string searchText: ""
    property string expandedPid: ""

    function hide() {
        close();
        processContextMenu.dismiss();
    }

    function show() {
        open();
    }

    function prepareForTrigger(triggerSource) {
        switch (triggerSource) {
        case "memory":
            DgopService.setSortBy("memory");
            break;
        case "cpu":
        case "cpu_temp":
        case "gpu_temp":
            DgopService.setSortBy("cpu");
            break;
        }
    }

    popupWidth: Math.round(Theme.fontSizeMedium * 46)
    popupHeight: Math.round(Theme.fontSizeMedium * 43)
    triggerWidth: 55
    positioning: ""
    screen: triggerScreen
    shouldBeVisible: false

    onBackgroundClicked: {
        processContextMenu.dismiss();
        close();
    }

    onShouldBeVisibleChanged: {
        if (!shouldBeVisible) {
            processContextMenu.dismiss();
            searchText = "";
            expandedPid = "";
        }
    }

    ProcessContextMenu {
        id: processContextMenu
        transientSurfaceTracker: processListPopout.transientSurfaceTracker
    }

    content: Component {
        Rectangle {
            id: processListContent

            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            radius: Theme.cornerRadius
            color: "transparent"
            clip: true
            focus: true

            Component.onCompleted: {
                if (processListPopout.shouldBeVisible)
                    searchField.forceActiveFocus();
                processContextMenu.parent = processListContent;
                processContextMenu.parentFocusItem = processListContent;
            }

            Keys.onPressed: event => {
                if (processContextMenu.visible || processContextMenu.confirmationOpen)
                    return;

                switch (event.key) {
                case Qt.Key_Escape:
                    processListPopout.close();
                    event.accepted = true;
                    return;
                case Qt.Key_F:
                    if (event.modifiers & Qt.ControlModifier) {
                        searchField.forceActiveFocus();
                        event.accepted = true;
                        return;
                    }
                    break;
                }

                processesView.handleKey(event);
            }

            readonly property bool popoutShouldBeVisible: processListPopout.shouldBeVisible

            onPopoutShouldBeVisibleChanged: {
                if (popoutShouldBeVisible) {
                    Qt.callLater(() => searchField.forceActiveFocus());
                } else {
                    processesView.reset();
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: PopoutMetrics.contentPadding
                spacing: PopoutMetrics.contentGap

                ProcessSystemHeader {
                    Layout.fillWidth: true
                }

                ProcessSummary {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM

                    DSearchField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.minimumWidth: Theme.fontSizeMedium * 8
                        placeholderText: I18n.tr("Search", "search field placeholder") + "…"
                        text: processListPopout.searchText
                        onTextChanged: processListPopout.searchText = text
                        ignoreUpDownKeys: true
                        keyForwardTargets: [processListContent]
                    }

                    ProcessFilterChips {
                        id: processFilterGroup
                        Layout.preferredWidth: singleRowWidth
                    }
                }

                ProcessesView {
                    id: processesView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: processListPopout.shouldBeVisible
                    searchText: processListPopout.searchText
                    expandedPid: processListPopout.expandedPid
                    contextMenu: processContextMenu
                    columns: ProcessColumns.POPOUT_COLUMNS
                    onExpandedPidChanged: processListPopout.expandedPid = expandedPid
                }
            }
        }
    }
}
