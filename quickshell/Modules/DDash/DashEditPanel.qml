pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter.Components
import qs.Modules.DDash.Overview
import "utils/widgets.js" as WidgetUtils

CcDockedEditPanel {
    id: root

    required property DashEditSession session
    property var tabItem: null
    property string entryId: ""
    property DashPageActions pageActions: null

    readonly property var editGrid: tabItem?.editGrid ?? null
    readonly property var pageEntry: DashRegistry.entry(entryId)
    readonly property var pageTarget: ({
            "kind": "page",
            "entryId": entryId,
            "key": entryId,
            "instanceId": "",
            "icon": pageEntry?.icon ?? "tune",
            "text": pageEntry?.text ?? ""
        })
    readonly property var target: {
        const s = session.selection;
        if (s?.kind === "page" || (!s && !editGrid))
            return pageTarget;
        return s ? (editGrid?.optionsTarget(s.key, s.instanceId ?? "") ?? null) : null;
    }
    readonly property bool canGoBack: session.selection !== null
    readonly property bool selectionLost: {
        const s = session.selection;
        return !!s && s.kind !== "page" && !(editGrid?.hasItem(s.key, s.instanceId ?? "") ?? false);
    }

    signal discardRequested

    function back() {
        if (!canGoBack)
            return false;
        session.clearSelection();
        return true;
    }

    function dropLostSelection() {
        if (selectionLost)
            session.clearSelection();
    }

    widgets: editGrid?.catalog ?? []
    canAdd: id => editGrid?.canPlace(id) ?? false
    categories: editGrid?.categories ?? []
    grid: editGrid
    listShown: editGrid !== null
    canUndo: session.canUndo
    heightModes: false
    clearable: pageActions?.hasWidgets ?? false
    detail: target === null ? null : target.kind === "widget" ? widgetForm : registryForm
    detailIcon: target?.icon ?? ""
    detailTitle: target?.text ?? ""
    detailSubtitle: I18n.tr("Options")
    detailBack: canGoBack
    menuItems: {
        const items = (tabItem?.menuActions ?? []).slice();
        if (editGrid && DashRegistry.hasOptions(entryId, true))
            items.push({
                "iconName": "tune",
                "label": I18n.tr("Options"),
                "action": () => root.session.selectPage(root.entryId)
            });
        return items;
    }

    // Deferred: a write can remove the selected item while its own handlers still run.
    onSelectionLostChanged: {
        if (selectionLost)
            Qt.callLater(dropLostSelection);
    }
    // Deferred: adding a single-use card removes the clicked bubble from the list.
    onAddRequested: id => Qt.callLater(() => root.editGrid?.addEntry(id))
    onUndoRequested: session.undo()
    onResetRequested: pageActions?.reset()
    onClearRequested: pageActions?.clear()
    onCancelRequested: discardRequested()
    onBackRequested: back()
    onCloseRequested: session.clearSelection()

    Component {
        id: registryForm

        DashOptionsForm {
            entryId: root.target?.entryId ?? ""
            instanceId: root.target?.instanceId ?? ""
            tabScope: root.target?.kind === "page"
            settingsLink: root.target?.kind !== "page" || DashRegistry.hasOptions(root.entryId, true)
        }
    }

    Component {
        id: widgetForm

        DashOptionsForm {
            // target is rebuilt on every commit; reading specs from it would recreate every row.
            specs: WidgetUtils.optionSpecs(root.editGrid?.specFor(root.session.selection?.key))
            valueFor: root.target?.valueFor ?? (key => undefined)
            commit: root.target?.commit ?? ((key, value) => {})
            resettable: false
            settingsLink: false
        }
    }
}
