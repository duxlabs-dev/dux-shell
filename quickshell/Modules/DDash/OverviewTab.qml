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
    readonly property bool blocksTabNavigation: grid.blocksTabNavigation || detailSheet.shown || editorSheet.shown || optionsSheet.shown || addMenu.open

    implicitWidth: DashMetrics.contentWidthFor(SettingsData.showWeekNumber)
    implicitHeight: grid.implicitHeight

    signal tabRequested(string id)
    signal navFocusRequested(bool backwards)

    onEditModeChanged: {
        if (!editMode) {
            optionsSheet.dismiss();
            addMenu.close();
        }
    }

    function handleKeyEvent(event) {
        if (detailSheet.shown || editorSheet.shown || optionsSheet.shown) {
            if (event.key !== Qt.Key_Escape)
                return false;
            detailSheet.dismiss();
            editorSheet.dismiss();
            optionsSheet.dismiss();
            return true;
        }
        if (addMenu.open) {
            if (event.key !== Qt.Key_Escape)
                return false;
            addMenu.close();
            return true;
        }
        return grid.handleKeyEvent(event);
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
        addMenu.openAt(anchor);
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
        onOptionsRequested: cardId => optionsSheet.presentFor(cardId)
        onDetailRequested: eventData => {
            detailSheet.eventData = eventData;
            detailSheet.present();
        }
        onEditorRequested: (eventData, initialDate) => {
            editorSheet.eventData = eventData;
            editorSheet.initialDate = initialDate;
            editorSheet.present();
        }
    }

    CcMenu {
        id: addMenu
        transientSurfaceTracker: root.transientSurfaceTracker

        items: root.addable.map(candidate => ({
                    "label": candidate.entry.card.text,
                    "iconName": candidate.entry.card.icon,
                    "action": () => CardUtils.addCard(candidate.entry.id, candidate.size.w, candidate.size.h)
                }))
    }

    DashOptionsSheet {
        id: optionsSheet
        backdrop: grid
        onDismissed: root.navFocusRequested(false)
    }

    CcSheetDialog {
        id: detailSheet
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
        }

        Loader {
            id: detailLoader

            width: parent.width
            active: detailSheet.visible

            sourceComponent: CalendarEventDetail {
                eventData: detailSheet.eventData
                canEdit: detailSheet.canEdit
                onCloseRequested: detailSheet.dismiss()
                onEditRequested: {
                    editorSheet.eventData = detailSheet.eventData;
                    editorSheet.initialDate = detailSheet.eventData?.start ?? new Date();
                    detailSheet.dismiss();
                    editorSheet.present();
                }
                onDeleteRequested: {
                    if (detailSheet.eventData?.id)
                        CalendarService.deleteEvent(detailSheet.eventData.id, null);
                    detailSheet.dismiss();
                }
            }
        }
    }

    CcSheetDialog {
        id: editorSheet
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
        }

        Loader {
            id: editorLoader

            width: parent.width
            active: editorSheet.visible

            sourceComponent: CalendarEventEditor {
                eventData: editorSheet.eventData
                initialDate: editorSheet.initialDate
                transientSurfaceTracker: root.transientSurfaceTracker
                onSaved: editorSheet.dismiss()
                onCloseRequested: editorSheet.dismiss()
            }
        }
    }
}
