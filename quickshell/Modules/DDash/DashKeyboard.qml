pragma ComponentBehavior: Bound

import QtQuick
import "../../DCommon/Common/FocusNavigation.js" as FocusNavigation

Item {
    id: root

    property bool active: false
    property bool editable: true
    property bool editMode: false
    property bool optionsShown: false
    property bool menuOpen: false
    property var tabItem: null
    property Item contentScope: null
    property Item contentTarget: null
    property var headerTargets: []
    property string headerEdge: "up"
    property bool tabsShown: true
    // Outside the content, Tab switches tabs and the tab keeps Space and the arrows.
    property bool steppedIn: false

    onActiveChanged: steppedIn = false
    onTabItemChanged: steppedIn = false
    onEditModeChanged: steppedIn = false

    readonly property bool idle: active && !optionsShown && !menuOpen
    readonly property bool contentFocused: contentScope?.activeFocus ?? false
    readonly property bool headerFocused: headerTargets.some(item => item?.activeFocus ?? false)
    readonly property bool browsing: idle && !editMode && !(tabItem?.blocksTabNavigation ?? false)

    signal tabCycleRequested(int direction)
    signal editModeRequested(bool on)
    signal optionsDismissRequested
    signal closeRequested
    signal leaveRequested

    function visibleHeaderTargets() {
        return headerTargets.filter(item => item && item.visible && item.enabled);
    }

    // Outside edit mode the header is not a keyboard stop; leaving the content goes back to the tabs.
    function focusHeader(backwards) {
        if (!editMode) {
            leaveContent();
            return;
        }
        const targets = visibleHeaderTargets();
        const target = backwards ? targets[targets.length - 1] : targets[0];
        target?.forceActiveFocus(backwards ? Qt.BacktabFocusReason : Qt.TabFocusReason);
    }

    function enterContent(backwards) {
        steppedIn = true;
        const target = backwards ? (tabItem?.previousFocusTarget ?? contentTarget) : contentTarget;
        FocusNavigation.focusItem(target, backwards);
    }

    function leaveContent() {
        steppedIn = false;
        leaveRequested();
    }

    function toggleContent(backwards) {
        if (steppedIn)
            leaveContent();
        else
            enterContent(backwards);
    }

    function inContent(item) {
        for (let p = item; p; p = p.parent) {
            if (p === contentScope)
                return true;
        }
        return false;
    }

    function tabKey(backwards) {
        if (tabsShown && !steppedIn)
            tabCycleRequested(backwards ? -1 : 1);
        else
            walkContent(backwards);
    }

    // Tab wraps inside the content, as in Settings.
    function walkContent(backwards) {
        if (!contentFocused) {
            enterContent(backwards);
            return;
        }
        let item = Window.activeFocusItem;
        for (let step = 0; item && step < 1000; step++) {
            item = item.nextItemInFocusChain(!backwards);
            if (inContent(item)) {
                item.forceActiveFocus(backwards ? Qt.BacktabFocusReason : Qt.TabFocusReason);
                return;
            }
        }
    }

    function moveCard(direction) {
        if (!contentFocused) {
            if (direction !== headerEdge)
                enterContent(false);
            return;
        }
        if (tabItem?.moveCardFocus?.(direction) !== true && direction === headerEdge)
            leaveContent();
    }

    function arrowDirection(event) {
        if ((event.modifiers & ~Qt.KeypadModifier) !== Qt.NoModifier)
            return "";
        switch (event.key) {
        case Qt.Key_Left:
            return "left";
        case Qt.Key_Right:
            return "right";
        case Qt.Key_Up:
            return "up";
        case Qt.Key_Down:
            return "down";
        }
        return "";
    }

    function contentEntryFor(key) {
        switch (key) {
        case Qt.Key_Down:
        case Qt.Key_Right:
            return "forwards";
        case Qt.Key_Up:
        case Qt.Key_Left:
            return "backwards";
        }
        return "";
    }

    function handleKeyEvent(event) {
        if (!active || menuOpen)
            return false;
        if (optionsShown) {
            if (event.key !== Qt.Key_Escape)
                return false;
            optionsDismissRequested();
            return true;
        }
        const forTab = !headerFocused || event.key === Qt.Key_Escape;
        if (forTab && typeof tabItem?.handleKeyEvent === "function" && tabItem.handleKeyEvent(event) === true)
            return true;
        const direction = arrowDirection(event);
        if (direction !== "" && contentFocused)
            return !tabItem?.blocksTabNavigation && tabItem?.moveCardFocus?.(direction) === true;
        const entry = contentEntryFor(event.key);
        if (entry !== "" && !contentFocused) {
            enterContent(entry === "backwards");
            return true;
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            if (!editMode)
                return false;
            focusHeader(event.key === Qt.Key_Backtab || !!(event.modifiers & Qt.ShiftModifier));
            return true;
        }
        if (event.key !== Qt.Key_Escape)
            return false;
        if (editMode)
            editModeRequested(false);
        else if (steppedIn && tabsShown)
            leaveContent();
        else
            closeRequested();
        return true;
    }

    Shortcut {
        sequence: "Tab"
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.tabKey(false)
    }

    Shortcut {
        sequence: "Shift+Tab"
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.tabKey(true)
    }

    Shortcut {
        sequences: ["Ctrl+Tab", "Ctrl+Shift+Tab"]
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.toggleContent(false)
    }

    Shortcut {
        sequence: "Ctrl+PgDown"
        enabled: root.idle
        context: Qt.WindowShortcut
        onActivated: root.tabCycleRequested(1)
    }

    Shortcut {
        sequence: "Ctrl+PgUp"
        enabled: root.idle
        context: Qt.WindowShortcut
        onActivated: root.tabCycleRequested(-1)
    }

    Shortcut {
        sequences: ["F2", "Ctrl+E"]
        enabled: root.browsing && root.editable
        context: Qt.WindowShortcut
        onActivated: root.editModeRequested(true)
    }

    Shortcut {
        sequence: "F6"
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.toggleContent(false)
    }

    Shortcut {
        sequence: "Shift+F6"
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.toggleContent(true)
    }

    Shortcut {
        sequence: "Alt+Tab"
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.tabItem?.cycleCardFocus?.(false)
    }

    Shortcut {
        sequence: "Alt+Shift+Tab"
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.tabItem?.cycleCardFocus?.(true)
    }

    Shortcut {
        sequences: ["Alt+Left", "Alt+H"]
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.moveCard("left")
    }

    Shortcut {
        sequences: ["Alt+Right", "Alt+L"]
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.moveCard("right")
    }

    Shortcut {
        sequences: ["Alt+Up", "Alt+K"]
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.moveCard("up")
    }

    Shortcut {
        sequences: ["Alt+Down", "Alt+J"]
        enabled: root.browsing
        context: Qt.WindowShortcut
        onActivated: root.moveCard("down")
    }
}
