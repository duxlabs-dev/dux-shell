import QtQuick
import qs.Common

FocusScope {
    id: root

    required property Item sidebar
    required property Item content
    required property var parentModal
    property string activePane: "sidebar"
    property Item sidebarFocus: null
    readonly property Item focusedItem: Window.activeFocusItem
    property int focusRevision: 0

    focus: true

    // Controls take focus on press with the mouse reason, so visualFocus tells how the activating control was reached
    function keyboardDriven() {
        return focusedItem?.visualFocus ?? false;
    }

    function contains(ancestor, item) {
        for (let p = item; p; p = p.parent) {
            if (p === ancestor)
                return true;
        }
        return false;
    }

    function transientOwnsFocus() {
        for (let p = focusedItem; p && p !== root; p = p.parent) {
            if (p.capturing === true || p.Accessible.role === Accessible.Dialog || p.Accessible.role === Accessible.PopupMenu)
                return true;
        }
        return false;
    }

    onFocusedItemChanged: {
        if (transientOwnsFocus())
            return;
        if (contains(sidebar, focusedItem)) {
            if (focusedItem !== sidebar)
                sidebarFocus = focusedItem;
            activePane = "sidebar";
        } else if (contains(content, focusedItem)) {
            activePane = "content";
            content.rememberFocus();
            // Focus that falls back to a container when its control is destroyed must not scroll the page
            if (keyboardDriven() || focusedItem.cursorPosition !== undefined)
                content._reveal(focusedItem);
        }
    }

    function focusSidebar() {
        focusRevision++;
        activePane = "sidebar";
        if (parentModal.isCompactMode)
            parentModal.menuVisible = true;
        if (sidebarFocus?.visible && sidebarFocus.enabled && contains(sidebar, sidebarFocus)) {
            sidebarFocus.forceActiveFocus(Qt.TabFocusReason);
            sidebar.ensureRowVisible(sidebarFocus);
        } else {
            sidebar.focusNavigation();
        }
    }

    function focusContent(keyboard = true) {
        focusRevision++;
        activePane = "content";
        if (parentModal.isCompactMode)
            parentModal.menuVisible = false;
        content.keyboardNavigation = keyboard;
        content._focusPage();
    }

    function focusSearch() {
        focusRevision++;
        activePane = "sidebar";
        if (parentModal.isCompactMode)
            parentModal.menuVisible = true;
        sidebar.focusSearch();
    }

    function pointerFocus(pane) {
        const revision = ++focusRevision;
        activePane = pane;
        // Child controls get the press first. A background click only moves the keyboard region, highlighting nothing.
        Qt.callLater(() => {
            if (revision !== focusRevision || transientOwnsFocus())
                return;
            const region = pane === "sidebar" ? sidebar : content;
            if (contains(region, focusedItem))
                return;
            if (pane === "sidebar")
                sidebar.forceActiveFocus(Qt.MouseFocusReason);
            else
                content.parkFocus();
        });
    }

    TapHandler {
        parent: root.sidebar
        onPressedChanged: {
            if (pressed)
                root.pointerFocus("sidebar");
        }
    }

    // Page scrollers accept presses before this handler sees them; SettingsContent gives each one its own
    TapHandler {
        parent: root.content
        onPressedChanged: {
            if (pressed)
                root.pointerFocus("content");
        }
    }

    TapHandler {
        acceptedButtons: Qt.BackButton
        onTapped: {
            if (!transientOwnsFocus())
                root.content.goBack(false);
        }
    }

    Keys.onPressed: event => {
        const mods = event.modifiers & ~Qt.KeypadModifier;
        if (transientOwnsFocus()) {
            if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab || event.key === Qt.Key_F) && (mods & Qt.ControlModifier))
                event.accepted = true;
            return;
        }
        if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (mods === Qt.ControlModifier || mods === (Qt.ControlModifier | Qt.ShiftModifier))) {
            if (activePane === "sidebar")
                focusContent();
            else
                focusSidebar();
            event.accepted = true;
        } else if (mods === Qt.AltModifier && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            const forward = (event.key === Qt.Key_Right) !== I18n.isRtl;
            if (forward !== (activePane === "sidebar"))
                return;
            if (forward)
                focusContent();
            else
                focusSidebar();
            event.accepted = true;
        } else if (event.key === Qt.Key_F && mods === Qt.ControlModifier) {
            focusSearch();
            event.accepted = true;
        }
    }
}
