pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.DDash.Overview
import qs.Modules.ControlCenter.Widgets
import "utils/cards.js" as CardUtils

FocusScope {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property bool live: Window.window?.visible ?? false
    property bool editMode: false
    property int rowBudget: DashMetrics.minimumTabRows
    property int columnCap: DashMetrics.maximumGridColumns
    property string preferredFocusId: "calendar"
    property var transientSurfaceTracker: null

    signal cardFocusChanged(string id)
    readonly property Item focusTarget: grid
    readonly property Item previousFocusTarget: grid.lastFocusTarget
    readonly property var addable: grid.addableEntries
    readonly property int usedColumns: grid.usedColumns
    readonly property bool cardResizing: grid.sizePreview !== null
    readonly property bool cardInteracting: grid.interacting
    readonly property bool sheetShown: (detailSheet.item?.shown ?? false) || (editorSheet.item?.shown ?? false) || (optionsSheet.item?.shown ?? false)
    readonly property bool addMenuOpen: addMenu.item?.open ?? false
    readonly property bool blocksTabNavigation: grid.blocksTabNavigation || sheetShown || addMenuOpen

    implicitWidth: DashMetrics.contentWidthFor(SettingsData.showWeekNumber)
    implicitHeight: grid.implicitHeight

    signal tabRequested(string id)
    signal navFocusRequested(bool backwards)

    onEditModeChanged: {
        if (!editMode)
            optionsSheet.item?.dismiss();
    }

    function handleKeyEvent(event) {
        if (sheetShown) {
            if (event.key !== Qt.Key_Escape)
                return false;
            dismissSheets();
            return true;
        }
        if (addMenuOpen) {
            if (event.key !== Qt.Key_Escape)
                return false;
            addMenu.item.close();
            return true;
        }
        return grid.handleKeyEvent(event);
    }

    function dismissSheets() {
        detailSheet.item?.dismiss();
        editorSheet.item?.dismiss();
        optionsSheet.item?.dismiss();
    }

    function releaseSheet(loader) {
        Qt.callLater(() => {
            if (loader.item && !loader.item.shown)
                loader.active = false;
        });
    }

    function presentOptions(cardId) {
        optionsSheet.active = true;
        optionsSheet.item.presentFor(cardId);
    }

    function presentDetail(eventData) {
        detailSheet.active = true;
        detailSheet.item.eventData = eventData;
        detailSheet.item.present();
    }

    function presentEditor(eventData, initialDate) {
        editorSheet.active = true;
        editorSheet.item.eventData = eventData;
        editorSheet.item.initialDate = initialDate;
        editorSheet.item.present();
    }

    function restoreFocus() {
        return grid.restoreFocus();
    }

    function cycleFocus(backwards) {
        return grid.cycleFocus(backwards);
    }

    function moveCardFocus(direction) {
        return grid.moveCardFocus(direction);
    }

    function cycleCardFocus(backwards) {
        return grid.cycleCardFocus(backwards);
    }

    function openAddMenu(anchor) {
        addMenu.item?.openAt(anchor);
    }

    DashCardGrid {
        id: grid

        width: parent.width
        editMode: root.editMode
        rowBudget: root.rowBudget
        columnCap: root.columnCap
        live: root.live
        preferredFocusId: root.preferredFocusId
        transientSurfaceTracker: root.transientSurfaceTracker
        onCardFocusChanged: id => root.cardFocusChanged(id)

        onCardClicked: cardId => {
            if (DashRegistry.hasTab(cardId))
                root.tabRequested(cardId);
        }
        onNavFocusRequested: backwards => root.navFocusRequested(backwards)
        onOptionsRequested: cardId => root.presentOptions(cardId)
        onDetailRequested: eventData => root.presentDetail(eventData)
        onEditorRequested: (eventData, initialDate) => root.presentEditor(eventData, initialDate)
    }

    Loader {
        id: addMenu
        active: root.editMode

        sourceComponent: CcMenu {
            transientSurfaceTracker: root.transientSurfaceTracker

            items: root.addable.map(candidate => ({
                        "label": candidate.entry.card.text,
                        "iconName": candidate.entry.card.icon,
                        "action": () => CardUtils.addCard(candidate.entry.id, candidate.size.w, candidate.size.h)
                    }))
        }
    }

    Loader {
        id: optionsSheet
        anchors.fill: parent
        z: DashMetrics.overlayZ
        active: false

        sourceComponent: DashOptionsSheet {
            backdrop: grid
            onDismissed: {
                root.navFocusRequested(false);
                root.releaseSheet(optionsSheet);
            }
        }
    }

    Loader {
        id: detailSheet
        anchors.fill: parent
        z: DashMetrics.overlayZ
        active: false

        sourceComponent: CcSheetDialog {
            id: detail
            backdrop: grid
            showScrollBar: false

            property var eventData: null

            readonly property bool canEdit: CalendarService.canCreateEvents && !!eventData && !eventData.readOnly && !(eventData.id && eventData.id.startsWith("task_"))

            panelWidth: DashMetrics.sheetWidth
            iconName: "event"
            title: eventData?.title ?? ""
            subtitle: detailLoader.item?.timeText ?? ""

            onDismissed: {
                eventData = null;
                root.navFocusRequested(false);
                root.releaseSheet(detailSheet);
            }

            Loader {
                id: detailLoader

                width: parent.width
                active: detail.visible

                sourceComponent: CalendarEventDetail {
                    eventData: detail.eventData
                    canEdit: detail.canEdit
                    onCloseRequested: detail.dismiss()
                    onEditRequested: {
                        const eventData = detail.eventData;
                        detail.dismiss();
                        root.presentEditor(eventData, eventData?.start ?? new Date());
                    }
                    onDeleteRequested: {
                        if (detail.eventData?.id)
                            CalendarService.deleteEvent(detail.eventData.id, null);
                        detail.dismiss();
                    }
                }
            }
        }
    }

    Loader {
        id: editorSheet
        anchors.fill: parent
        z: DashMetrics.overlayZ
        active: false

        sourceComponent: CcSheetDialog {
            id: editor
            backdrop: grid
            showScrollBar: false

            property var eventData: null
            property date initialDate: new Date()

            panelWidth: DashMetrics.sheetWidth
            iconName: "edit_calendar"
            title: eventData ? I18n.tr("Edit event") : I18n.tr("New event")
            statusText: editorLoader.item?.errorText ?? ""
            statusColor: Theme.error

            onDismissed: {
                eventData = null;
                root.navFocusRequested(false);
                root.releaseSheet(editorSheet);
            }

            Loader {
                id: editorLoader

                width: parent.width
                active: editor.visible

                sourceComponent: CalendarEventEditor {
                    eventData: editor.eventData
                    initialDate: editor.initialDate
                    transientSurfaceTracker: root.transientSurfaceTracker
                    onSaved: editor.dismiss()
                    onCloseRequested: editor.dismiss()
                }
            }
        }
    }
}
