import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import qs.Common
import qs.Modules.ProcessList
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../Modules/ProcessList/ProcessColumns.js" as ProcessColumns

DFloatingWindow {
    id: processListModal
    readonly property var log: Log.scoped("ProcessListModal")

    property int currentTab: 0
    property string searchText: ""
    property string expandedPid: ""
    property var processColumns: ProcessColumns.DEFAULT_COLUMNS
    property bool shouldHaveFocus: visible
    readonly property alias modalFocusScope: contentFocusScope
    property alias shouldBeVisible: processListModal.visible

    signal closingModal

    function show() {
        if (!DgopService.dgopAvailable) {
            log.warn("dgop is not available");
            return;
        }
        visible = true;
    }

    function hide() {
        visible = false;
        processContextMenu.dismiss();
    }

    function toggle() {
        if (!DgopService.dgopAvailable) {
            log.warn("dgop is not available");
            return;
        }
        visible = !visible;
    }

    function focusOrToggle() {
        if (!DgopService.dgopAvailable) {
            log.warn("dgop is not available");
            return;
        }
        if (!visible) {
            show();
            return;
        }
        const modalTitle = I18n.tr("System Monitor", "sysmon window title");
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (toplevel.title !== "System Monitor" && toplevel.title !== modalTitle)
                continue;
            if (toplevel.activated) {
                hide();
                return;
            }
            toplevel.activate();
            return;
        }
        hide();
        show();
    }

    function nextTab() {
        currentTab = (currentTab + 1) % 4;
    }

    function previousTab() {
        currentTab = (currentTab - 1 + 4) % 4;
    }

    objectName: "processListModal"
    title: I18n.tr("System Monitor", "sysmon window title")
    minimumSize: Qt.size(Math.min(Math.round(Theme.fontSizeMedium * 48), Screen.width), Math.min(Math.round(Theme.fontSizeMedium * 34), Screen.height))
    implicitWidth: Math.round(Theme.fontSizeMedium * 91)
    implicitHeight: ProcessListMetrics.windowHeight
    visible: false

    Ref {
        service: DgopService
        // Device histories keep filling while the window is open, whichever page is shown.
        modules: ["cpu", "memory", "network", "disk", "system", "gpu", "disk-rate", "net-rate"]
        active: processListModal.visible
    }

    // Held for the whole window, so drive cards survive tab switches and the SMART report is not read again.
    Ref {
        service: DriveService
        active: processListModal.visible
    }

    onClosed: hide()

    onCurrentTabChanged: {
        if (visible && currentTab === 0 && searchField.visible && !viewNavigation.activeFocus)
            searchField.forceActiveFocus();
    }

    onVisibleChanged: {
        if (!visible) {
            DgopService.lock();
            processContextMenu.dismiss();
            closingModal();
            searchText = "";
            expandedPid = "";
            if (processesTabLoader.item)
                processesTabLoader.item.reset();
        } else {
            Qt.callLater(() => {
                if (currentTab === 0 && searchField.visible)
                    searchField.forceActiveFocus();
                else if (contentFocusScope)
                    contentFocusScope.forceActiveFocus();
            });
        }
    }

    ProcessContextMenu {
        id: processContextMenu
        parentFocusItem: contentFocusScope
    }

    FocusScope {
        id: contentFocusScope

        LayoutMirroring.enabled: I18n.isRtl
        LayoutMirroring.childrenInherit: true

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (processContextMenu.visible || processContextMenu.confirmationOpen || columnPicker.shown)
                return;

            switch (event.key) {
            case Qt.Key_1:
            case Qt.Key_2:
            case Qt.Key_3:
            case Qt.Key_4:
                if (searchField.getActiveFocus())
                    return;
                currentTab = event.key - Qt.Key_1;
                event.accepted = true;
                return;
            case Qt.Key_Escape:
                hide();
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

            if (currentTab === 0 && processesTabLoader.item)
                processesTabLoader.item.handleKey(event);
        }

        Rectangle {
            anchors.centerIn: parent
            width: 400
            height: 200
            radius: Theme.cornerRadius
            color: Theme.errorHover
            border.color: Theme.error
            border.width: Theme.outlineWidthFocused
            visible: !DgopService.dgopAvailable

            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingL

                DIcon {
                    name: "error"
                    size: 48
                    color: Theme.error
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: I18n.tr("System Monitor Unavailable")
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                    color: Theme.error
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: I18n.tr("%1 not available", "%1 is a tool or environment variable name").arg("DMS_SOCKET")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            spacing: 0
            visible: DgopService.dgopAvailable

            DWindowHeader {
                Layout.fillWidth: true
                controls: windowControls
                title: I18n.tr("System Monitor")
                onCloseRequested: processListModal.hide()
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                DNavigationBar {
                    id: viewNavigation
                    Layout.preferredWidth: Theme.navigationRailWidth
                    Layout.preferredHeight: implicitHeight
                    Layout.alignment: Qt.AlignTop
                    orientation: Qt.Vertical
                    evenlySpaced: false
                    spacing: Theme.spacingM
                    nextFocusTarget: currentTab === 0 ? searchField : null
                    model: [
                        {
                            text: I18n.tr("Processes"),
                            icon: "list_alt"
                        },
                        {
                            text: I18n.tr("Performance"),
                            icon: "monitoring"
                        },
                        {
                            text: I18n.tr("Disks", "process list window tab name"),
                            icon: "storage"
                        },
                        {
                            text: I18n.tr("System", "noun, tab name, process filter and app category"),
                            icon: "computer"
                        }
                    ]
                    currentIndex: processListModal.currentTab
                    onActivated: index => processListModal.currentTab = index
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: Theme.spacingS
                    Layout.rightMargin: Theme.windowInset
                    Layout.bottomMargin: Theme.windowInset
                    spacing: Theme.spacingM

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingM
                        visible: currentTab === 0

                        DSearchField {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.maximumWidth: Theme.fontSizeMedium * 30
                            placeholderText: I18n.tr("Search processes...", "process search placeholder")
                            text: processListModal.searchText
                            onTextChanged: processListModal.searchText = text
                            ignoreUpDownKeys: true
                            keyForwardTargets: [contentFocusScope]
                            KeyNavigation.backtab: viewNavigation
                        }

                        ProcessFilterChips {
                            id: processFilterGroup
                            Layout.preferredWidth: singleRowWidth
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: processesTabLoader.item?.processCountText ?? ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        DIconButton {
                            id: lockButton
                            readonly property bool busy: DgopService.unlocking || DgopService.unlockLoading
                            iconName: busy ? "" : DgopService.unlocked ? "lock_open" : "lock"
                            variant: DgopService.unlocked ? "tonal" : "standard"
                            enabled: !DgopService.unlocking
                            tooltipText: DgopService.unlocked ? I18n.tr("Lock") : I18n.tr("Unlock")
                            onClicked: DgopService.unlocked ? DgopService.lock() : DgopService.unlock()

                            DSpinner {
                                anchors.centerIn: parent
                                size: Theme.iconSizeSmall
                                visible: lockButton.busy
                            }
                        }

                        DIconButton {
                            iconName: "view_column"
                            tooltipText: I18n.tr("Columns")
                            onClicked: columnPicker.present()
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        readonly property bool isFloatingWindowSurface: true

                        Loader {
                            id: processesTabLoader
                            anchors.fill: parent
                            active: processListModal.visible
                            visible: currentTab === 0
                            sourceComponent: ProcessesView {
                                fullList: true
                                searchText: processListModal.searchText
                                expandedPid: processListModal.expandedPid
                                contextMenu: processContextMenu
                                columns: processListModal.processColumns
                                onExpandedPidChanged: processListModal.expandedPid = expandedPid
                            }
                        }

                        Loader {
                            id: performanceTabLoader
                            anchors.fill: parent
                            active: processListModal.visible
                            visible: currentTab === 1
                            sourceComponent: PerformanceView {}
                        }

                        Loader {
                            id: disksTabLoader
                            anchors.fill: parent
                            active: processListModal.visible
                            visible: currentTab === 2
                            sourceComponent: DisksView {}
                        }

                        Loader {
                            id: systemTabLoader
                            anchors.fill: parent
                            active: processListModal.visible
                            visible: currentTab === 3
                            sourceComponent: SystemView {}
                        }
                    }
                }
            }
        }

        ColumnPickerSheet {
            id: columnPicker
            backdrop: mainColumn
            columns: processListModal.processColumns
            onColumnsEdited: cols => processListModal.processColumns = cols
            onDismissed: searchField.forceActiveFocus()
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: processListModal
    }
}
