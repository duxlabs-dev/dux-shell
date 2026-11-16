import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modals.Common

DContextMenu {
    id: processContextMenu

    property var processData: null
    property var parentFocusItem: null
    property string submenu: ""

    readonly property bool menuOpen: renderActive
    readonly property bool confirmationOpen: confirmation.opened
    readonly property string endTitle: ProcessActions.restartKind(processData) === "reload" ? I18n.tr("Quit or reload", "process menu: opens the quit, force quit, end tree and reload actions") : I18n.tr("Quit or restart", "process menu: opens the quit, force quit, end tree and restart actions")

    signal menuClosed
    signal processKilled

    minMenuWidth: ProcessListMetrics.menuWidth
    keyboardNavigable: true

    onRenderActiveChanged: {
        transientSurfaceTracker?.setActive(processContextMenu, renderActive || confirmationOpen, contextWindow);
        if (!renderActive) {
            submenu = "";
            menuClosed();
            focusRestore.restart();
        }
    }
    onConfirmationOpenChanged: transientSurfaceTracker?.setActive(processContextMenu, renderActive || confirmationOpen, contextWindow)

    readonly property var mainItems: [
        {
            type: "item",
            text: I18n.tr("Copy PID"),
            icon: "tag",
            action: copyPid,
            enabled: true
        },
        {
            type: "item",
            text: I18n.tr("Copy Name"),
            icon: "content_copy",
            action: copyName,
            enabled: true
        },
        {
            type: "item",
            text: I18n.tr("Copy Full Command"),
            icon: "code",
            action: copyFullCommand,
            enabled: true
        },
        {
            type: "separator"
        }
    ].concat(ProcessActions.canPause(processData) ? [
            {
                type: "item",
                text: ProcessActions.isPaused(processData) ? I18n.tr("Resume", "process action: continue a paused process (SIGCONT)") : I18n.tr("Pause", "process action: freeze the process and everything it started (SIGSTOP)"),
                icon: ProcessActions.isPaused(processData) ? "play_arrow" : "pause",
                action: () => closeAndRun(process => ProcessActions.setPaused(process, !ProcessActions.isPaused(process))),
                enabled: true
            }
        ] : []).concat(ProcessActions.canSetPriority(processData) ? [
            {
                type: "item",
                text: I18n.tr("Priority", "process action: opens the priority presets"),
                icon: "speed",
                trailingIcon: "chevron_right",
                keepOpen: true,
                action: () => Qt.callLater(setSubmenu, "priority"),
                enabled: true,
                submenu: "priority"
            }
        ] : []).concat([
        {
            type: "item",
            text: endTitle,
            icon: "power_settings_new",
            trailingIcon: "chevron_right",
            keepOpen: true,
            action: () => Qt.callLater(setSubmenu, "end"),
            enabled: ProcessActions.canEnd(processData) || ProcessActions.canRestart(processData),
            submenu: "end"
        }
    ])

    readonly property var backItems: [
        {
            type: "item",
            text: I18n.tr("Back"),
            icon: "arrow_back",
            keepOpen: true,
            action: () => Qt.callLater(setSubmenu, ""),
            enabled: true
        },
        {
            type: "separator"
        }
    ]

    readonly property var endItems: backItems.concat([
        {
            type: "item",
            text: I18n.tr("Quit", "process action: ask the process to exit (SIGTERM)"),
            icon: "close",
            action: () => requestAction("quit"),
            enabled: ProcessActions.canEnd(processData),
            isDestructive: true
        },
        {
            type: "item",
            text: I18n.tr("Force quit", "process action: kill the process immediately (SIGKILL)"),
            icon: "dangerous",
            action: () => requestAction("force"),
            enabled: ProcessActions.canEnd(processData),
            isDestructive: true
        },
        {
            type: "item",
            text: I18n.tr("End process tree", "process action: quit the process and every process it started"),
            icon: "account_tree",
            action: () => requestAction("tree"),
            enabled: ProcessActions.canEnd(processData),
            isDestructive: true
        },
        {
            type: "item",
            text: ProcessActions.title("restart", processData),
            icon: "restart_alt",
            action: () => requestAction("restart"),
            enabled: ProcessActions.canRestart(processData)
        }
    ])

    readonly property var priorityItems: backItems.concat(ProcessActions.priorities.map(preset => ({
                type: "item",
                text: preset.label,
                icon: preset === ProcessActions.priorityPreset(processData?.nice) ? "check" : "",
                action: () => closeAndRun(process => ProcessActions.setPriority(process, preset.nice)),
                enabled: true
            })))

    menuItems: submenu === "end" ? endItems : submenu === "priority" ? priorityItems : mainItems

    function setSubmenu(name) {
        const from = submenu;
        submenu = name;
        if (!keyboardNavigation) {
            selectedMenuIndex = -1;
            return;
        }
        if (name) {
            selectedMenuIndex = 1;
            return;
        }
        const selectableMain = mainItems.filter(item => item.type === "item");
        selectedMenuIndex = Math.max(0, selectableMain.findIndex(item => item.submenu === from));
    }

    function show(x, y, fromKeyboard) {
        submenu = "";
        openAtItem(parent, x, y, fromKeyboard);
    }

    function copyPid() {
        if (processData)
            Quickshell.execDetached(["dms", "cl", "copy", "--", processData.pid.toString()]);
    }

    function copyName() {
        if (processData) {
            const name = processData.command || "";
            Quickshell.execDetached(["dms", "cl", "copy", "--", name]);
        }
    }

    function copyFullCommand() {
        if (processData) {
            const fullCmd = processData.fullCommand || processData.command || "";
            Quickshell.execDetached(["dms", "cl", "copy", "--", fullCmd]);
        }
    }

    function requestAction(action) {
        if (!processData || !(action === "restart" ? ProcessActions.canRestart(processData) : ProcessActions.canEnd(processData)))
            return;
        const process = Object.assign({}, processData);
        hide();
        confirmation.open(process, action, action !== "restart" && ProcessActions.isCritical(process));
    }

    function closeAndRun(action) {
        if (!processData)
            return;
        const process = Object.assign({}, processData);
        hide();
        action(process);
    }

    function dismiss() {
        hide();
        confirmation.close();
    }

    ProcessActionDialog {
        id: confirmation
        parent: processContextMenu.parent
        onChosen: (action, process) => {
            if ((process?.pid ?? 0) <= 0)
                return;
            ProcessActions.run(action, process);
            processContextMenu.processKilled();
        }
        onOpenedChanged: {
            if (!opened)
                focusRestore.restart();
        }
    }

    DeferredAction {
        id: focusRestore
        onTriggered: {
            if (!processContextMenu.confirmationOpen && processContextMenu.parentFocusItem?.visible)
                processContextMenu.parentFocusItem.forceActiveFocus();
        }
    }
}
