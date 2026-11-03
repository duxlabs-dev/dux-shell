import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Session

FocusScope {
    id: root

    property int selectedIndex: 0
    onSelectedIndexChanged: {
        if (selectedIndex < visibleActions.length)
            return;
        selectedIndex = Math.max(0, visibleActions.length - 1);
        selectedRow = Math.floor(selectedIndex / gridColumns);
        selectedCol = selectedIndex % gridColumns;
    }
    property int selectedRow: 0
    property int selectedCol: 0
    property var visibleActions: []
    property int gridColumns: 3
    property int gridRows: 2
    readonly property int currentRowColumns: Math.max(1, Math.min(gridColumns, visibleActions.length - selectedRow * gridColumns))

    property string holdAction: ""
    property int holdActionIndex: -1
    property real holdProgress: 0
    property bool showHoldHint: false
    property bool holdFromKeyboard: false
    property string committedAction: ""

    readonly property bool needsConfirmation: SettingsData.powerActionConfirm
    readonly property int holdDurationMs: SettingsData.powerActionHoldDuration * 1000
    readonly property real desiredWidth: powerView.desiredWidth

    signal powerActionRequested(string action)
    signal lockRequested
    signal switchUserRequested
    signal closeRequested

    implicitHeight: powerView.implicitHeight

    function resetState() {
        holdAction = "";
        holdActionIndex = -1;
        holdProgress = 0;
        showHoldHint = false;
        holdFromKeyboard = false;
        committedAction = "";
        commitFallbackTimer.stop();
        updateVisibleActions();
        const defaultIndex = getDefaultActionIndex();
        selectedIndex = defaultIndex;
        if (SettingsData.powerMenuGridLayout) {
            selectedRow = Math.floor(defaultIndex / gridColumns);
            selectedCol = defaultIndex % gridColumns;
        }
    }

    function actionNeedsConfirm(action) {
        return action !== "lock" && action !== "restart";
    }

    function actionWakesOnKeyRelease(action) {
        return action === "suspend" || action === "hibernate";
    }

    function startHold(action, actionIndex) {
        if (committedAction !== "")
            return;
        if (!needsConfirmation || !actionNeedsConfirm(action)) {
            if (holdFromKeyboard && actionWakesOnKeyRelease(action)) {
                commitAction(action, actionIndex);
                return;
            }
            executeAction(action);
            return;
        }
        holdAction = action;
        holdActionIndex = actionIndex;
        holdProgress = 0;
        showHoldHint = false;
        holdTimer.start();
    }

    function cancelHold() {
        if (holdAction === "")
            return;
        const wasHolding = holdProgress > 0;
        holdTimer.stop();
        if (wasHolding && holdProgress < 1) {
            showHoldHint = true;
            hintTimer.restart();
        }
        holdAction = "";
        holdActionIndex = -1;
        holdProgress = 0;
    }

    function completeHold() {
        if (holdProgress < 1) {
            cancelHold();
            return;
        }
        holdTimer.stop();
        if (holdFromKeyboard && actionWakesOnKeyRelease(holdAction)) {
            commitAction(holdAction, holdActionIndex);
            return;
        }
        const action = holdAction;
        holdAction = "";
        holdActionIndex = -1;
        holdProgress = 0;
        executeAction(action);
    }

    function commitAction(action, actionIndex) {
        holdTimer.stop();
        holdAction = "";
        holdActionIndex = actionIndex;
        committedAction = action;
        commitFallbackTimer.restart();
    }

    function executeCommittedAction() {
        if (committedAction === "")
            return;
        commitFallbackTimer.stop();
        const action = committedAction;
        committedAction = "";
        holdActionIndex = -1;
        holdProgress = 0;
        executeAction(action);
    }

    function executeAction(action) {
        closeRequested();
        if (action === "lock") {
            lockRequested();
            return;
        }
        if (action === "switchuser") {
            switchUserRequested();
            return;
        }
        root.powerActionRequested(action);
    }

    Timer {
        id: holdTimer
        interval: 16
        repeat: true
        onTriggered: {
            root.holdProgress = Math.min(1, root.holdProgress + (interval / root.holdDurationMs));
            if (root.holdProgress >= 1) {
                stop();
                root.completeHold();
            }
        }
    }

    Timer {
        id: hintTimer
        interval: 2000
        onTriggered: root.showHoldHint = false
    }

    Timer {
        id: commitFallbackTimer
        interval: 5000
        onTriggered: root.executeCommittedAction()
    }

    function updateVisibleActions() {
        const allActions = SettingsData.powerMenuActions || ["reboot", "logout", "poweroff", "lock", "suspend", "restart"];
        visibleActions = allActions.filter(action => SessionService.isPowerActionSupported(action)).concat(SessionService.extraPowerActions);

        if (!SettingsData.powerMenuGridLayout)
            return;
        const count = visibleActions.length;
        if (count === 0) {
            gridColumns = 1;
            gridRows = 1;
            return;
        }

        if (count <= 3) {
            gridColumns = 1;
            gridRows = count;
            return;
        }

        if (count === 4) {
            gridColumns = 2;
            gridRows = 2;
            return;
        }

        gridColumns = 3;
        gridRows = Math.ceil(count / 3);
    }

    function getDefaultActionIndex() {
        const defaultAction = SettingsData.powerMenuDefaultAction || "logout";
        const index = visibleActions.indexOf(defaultAction);
        return index >= 0 ? index : 0;
    }

    function getActionAtIndex(index) {
        if (index < 0 || index >= visibleActions.length)
            return "";
        return visibleActions[index];
    }

    function getActionData(action) {
        return SessionService.getPowerActionData(action);
    }

    function selectOption(action, actionIndex) {
        startHold(action, actionIndex !== undefined ? actionIndex : -1);
    }

    Keys.onPressed: event => {
        if (event.isAutoRepeat) {
            event.accepted = true;
            return;
        }
        if (committedAction !== "") {
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Escape) {
            cancelHold();
            closeRequested();
            event.accepted = true;
            return;
        }
        holdFromKeyboard = true;
        if (SettingsData.powerMenuGridLayout) {
            handleGridNavigation(event);
        } else {
            handleListNavigation(event);
        }
    }

    Keys.onReleased: event => {
        if (event.isAutoRepeat) {
            event.accepted = true;
            return;
        }
        if (committedAction !== "") {
            event.accepted = true;
            executeCommittedAction();
            return;
        }
        if (event.key === Qt.Key_Escape) {
            event.accepted = true;
            return;
        }
        handleKeyRelease(event);
    }

    function isEnterKey(event) {
        return event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
    }

    // The shortcut of each visible action is the key its hint shows. Ctrl combinations navigate.
    // fromCharCode truncates to 16 bits, so special keys (0x01xxxxxx) must be rejected first.
    function actionForKey(event) {
        if (event.modifiers & Qt.ControlModifier || event.key > Qt.Key_Z)
            return "";
        const key = String.fromCharCode(event.key);
        if (!/^[A-Z0-9]$/.test(key))
            return "";
        return visibleActions.find(action => getActionData(action).key === key) ?? "";
    }

    function handleKeyRelease(event) {
        if (isEnterKey(event) || actionForKey(event) !== "") {
            cancelHold();
            event.accepted = true;
        }
    }

    function handleActionShortcut(event) {
        if (isEnterKey(event)) {
            startHold(getActionAtIndex(selectedIndex), selectedIndex);
            event.accepted = true;
            return true;
        }
        const action = actionForKey(event);
        if (action === "")
            return false;
        startHold(action, visibleActions.indexOf(action));
        event.accepted = true;
        return true;
    }

    function handleListNavigation(event) {
        if (handleActionShortcut(event))
            return;

        switch (event.key) {
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            selectedIndex = (selectedIndex - 1 + visibleActions.length) % visibleActions.length;
            event.accepted = true;
            break;
        case Qt.Key_Down:
        case Qt.Key_Tab:
            selectedIndex = (selectedIndex + 1) % visibleActions.length;
            event.accepted = true;
            break;
        case Qt.Key_N:
        case Qt.Key_J:
            if (event.modifiers & Qt.ControlModifier) {
                selectedIndex = (selectedIndex + 1) % visibleActions.length;
                event.accepted = true;
            }
            break;
        case Qt.Key_P:
        case Qt.Key_K:
            if (event.modifiers & Qt.ControlModifier) {
                selectedIndex = (selectedIndex - 1 + visibleActions.length) % visibleActions.length;
                event.accepted = true;
            }
            break;
        }
    }

    function handleGridNavigation(event) {
        if (handleActionShortcut(event))
            return;

        switch (event.key) {
        case Qt.Key_Left:
            selectedCol = (selectedCol + (I18n.isRtl ? 1 : -1) + currentRowColumns) % currentRowColumns;
            selectedIndex = selectedRow * gridColumns + selectedCol;
            event.accepted = true;
            break;
        case Qt.Key_Right:
            selectedCol = (selectedCol + (I18n.isRtl ? -1 : 1) + currentRowColumns) % currentRowColumns;
            selectedIndex = selectedRow * gridColumns + selectedCol;
            event.accepted = true;
            break;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            selectedRow = (selectedRow - 1 + gridRows) % gridRows;
            selectedIndex = selectedRow * gridColumns + selectedCol;
            event.accepted = true;
            break;
        case Qt.Key_Down:
        case Qt.Key_Tab:
            selectedRow = (selectedRow + 1) % gridRows;
            selectedIndex = selectedRow * gridColumns + selectedCol;
            event.accepted = true;
            break;
        case Qt.Key_N:
            if (event.modifiers & Qt.ControlModifier) {
                selectedCol = (selectedCol + 1) % currentRowColumns;
                selectedIndex = selectedRow * gridColumns + selectedCol;
                event.accepted = true;
            }
            break;
        case Qt.Key_P:
            if (event.modifiers & Qt.ControlModifier) {
                selectedCol = (selectedCol - 1 + currentRowColumns) % currentRowColumns;
                selectedIndex = selectedRow * gridColumns + selectedCol;
                event.accepted = true;
            }
            break;
        case Qt.Key_J:
            if (event.modifiers & Qt.ControlModifier) {
                selectedRow = (selectedRow + 1) % gridRows;
                selectedIndex = selectedRow * gridColumns + selectedCol;
                event.accepted = true;
            }
            break;
        case Qt.Key_K:
            if (event.modifiers & Qt.ControlModifier) {
                selectedRow = (selectedRow - 1 + gridRows) % gridRows;
                selectedIndex = selectedRow * gridColumns + selectedCol;
                event.accepted = true;
            }
            break;
        }
    }

    Component.onCompleted: resetState()

    PowerMenuView {
        id: powerView
        anchors.fill: parent
        color: "transparent"
        actions: root.visibleActions
        actionProvider: root.getActionData
        gridLayout: SettingsData.powerMenuGridLayout
        gridColumns: root.gridColumns
        selectedIndex: root.selectedIndex
        holdActionIndex: root.holdActionIndex
        holdProgress: root.holdProgress
        showHint: root.needsConfirmation
        hintWarning: root.showHoldHint
        hintIcon: root.showHoldHint ? "warning" : root.actionNeedsConfirm(root.getActionAtIndex(root.selectedIndex)) ? "touch_app" : "bolt"
        hintText: {
            if (root.committedAction !== "")
                return I18n.tr("Release to confirm");
            if (root.showHoldHint)
                return I18n.tr("Hold longer to confirm");
            if (!root.actionNeedsConfirm(root.getActionAtIndex(root.selectedIndex)))
                return I18n.tr("Activates immediately");
            const totalMs = root.holdDurationMs;
            const remainingMs = Math.ceil(totalMs * (1 - root.holdProgress));
            if (root.holdProgress > 0)
                return totalMs < 1000 ? I18n.tr("Hold to confirm (%1 ms)", "power menu hint, %1 is a number of milliseconds").arg(remainingMs) : I18n.tr("Hold to confirm (%1s)", "power menu hint, %1 is a number of seconds").arg(Math.ceil(remainingMs / 1000));
            return totalMs < 1000 ? I18n.tr("Hold to confirm (%1 ms)").arg(totalMs) : I18n.tr("Hold to confirm (%1s)").arg(totalMs / 1000);
        }
        onActionPressed: index => {
            root.holdFromKeyboard = false;
            root.selectedIndex = index;
            root.selectedRow = Math.floor(index / root.gridColumns);
            root.selectedCol = index % root.gridColumns;
            root.startHold(root.visibleActions[index], index);
        }
        onActionReleased: root.cancelHold()
        onActionCanceled: root.cancelHold()
    }
}
