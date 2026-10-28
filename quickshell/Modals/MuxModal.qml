pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DModal {
    id: muxModal

    layerNamespace: "dms:mux"

    property int selectedIndex: -1
    property string searchText: ""
    property var filteredSessions: []

    function updateFilteredSessions() {
        var filtered = [];
        var lowerSearch = searchText.trim().toLowerCase();
        for (var i = 0; i < MuxService.sessions.length; i++) {
            var session = MuxService.sessions[i];
            if (lowerSearch.length > 0 && !session.name.toLowerCase().includes(lowerSearch))
                continue;
            filtered.push(session);
        }
        filteredSessions = filtered;

        if (selectedIndex >= filteredSessions.length) {
            selectedIndex = Math.max(0, filteredSessions.length - 1);
        }
    }

    onSearchTextChanged: updateFilteredSessions()

    Connections {
        target: MuxService
        function onSessionsChanged() {
            updateFilteredSessions();
        }
    }

    function toggle() {
        if (shouldBeVisible) {
            hide();
        } else {
            show();
        }
    }

    function show() {
        open();
        selectedIndex = -1;
        searchText = "";
        MuxService.refreshSessions();
        shouldHaveFocus = true;

        Qt.callLater(() => {
            if (muxPanel && muxPanel.searchField) {
                muxPanel.searchField.forceActiveFocus();
            }
        });
    }

    function hide() {
        close();
        selectedIndex = -1;
        searchText = "";
    }

    function attachToSession(name) {
        MuxService.attachToSession(name);
        hide();
    }

    function renameSession(name) {
        inputModal.showWithOptions({
            title: I18n.tr("Rename Session"),
            message: I18n.tr("Enter a new name for session \"%1\"", "rename session dialog, %1 is the current session name").arg(name),
            initialText: name,
            onConfirm: function (newName) {
                MuxService.renameSession(name, newName);
            }
        });
    }

    function killSession(name) {
        confirmModal.showWithOptions({
            title: I18n.tr("Kill Session"),
            message: I18n.tr("Are you sure you want to kill session \"%1\"?", "kill session confirmation, %1 is the session name").arg(name),
            confirmText: I18n.tr("Kill", "verb, terminate a multiplexer session"),
            confirmColor: Theme.primary,
            onConfirm: function () {
                MuxService.killSession(name);
            }
        });
    }

    function createNewSession() {
        inputModal.showWithOptions({
            title: I18n.tr("New Session"),
            message: I18n.tr("Please write a name for your new %1 session", "new session dialog, %1 is the terminal multiplexer name").arg(MuxService.displayName),
            onConfirm: function (name) {
                MuxService.createSession(name);
                hide();
            }
        });
    }

    function selectNext() {
        selectedIndex = Math.min(selectedIndex + 1, filteredSessions.length - 1);
    }

    function selectPrevious() {
        selectedIndex = Math.max(selectedIndex - 1, -1);
    }

    function activateSelected() {
        if (selectedIndex === -1) {
            createNewSession();
        } else if (selectedIndex >= 0 && selectedIndex < filteredSessions.length) {
            attachToSession(filteredSessions[selectedIndex].name);
        }
    }

    visible: false
    modalWidth: 600
    modalHeight: 600
    backgroundColor: Theme.floatingWindowSurface
    enableShadow: true
    keepContentLoaded: true

    onBackgroundClicked: hide()

    Timer {
        interval: 3000
        running: muxModal.shouldBeVisible
        repeat: true
        onTriggered: MuxService.refreshSessions()
    }

    IpcHandler {
        function open(): string {
            muxModal.show();
            return "MUX_OPEN_SUCCESS";
        }

        function close(): string {
            muxModal.hide();
            return "MUX_CLOSE_SUCCESS";
        }

        function toggle(): string {
            muxModal.toggle();
            return "MUX_TOGGLE_SUCCESS";
        }

        target: "mux"
    }

    // Backwards compatibility
    IpcHandler {
        function open(): string {
            muxModal.show();
            return "TMUX_OPEN_SUCCESS";
        }

        function close(): string {
            muxModal.hide();
            return "TMUX_CLOSE_SUCCESS";
        }

        function toggle(): string {
            muxModal.toggle();
            return "TMUX_TOGGLE_SUCCESS";
        }

        target: "tmux"
    }

    InputModal {
        id: inputModal
        onShouldBeVisibleChanged: {
            if (shouldBeVisible) {
                muxModal.shouldHaveFocus = false;
                muxModal.contentWindow.visible = false;
                return;
            }
            if (muxModal.shouldBeVisible) {
                muxModal.contentWindow.visible = true;
            }
            Qt.callLater(function () {
                if (!muxModal.shouldBeVisible) {
                    return;
                }
                muxModal.shouldHaveFocus = true;
                muxModal.modalFocusScope.forceActiveFocus();
                if (muxPanel.searchField) {
                    muxPanel.searchField.forceActiveFocus();
                }
            });
        }
    }

    ConfirmModal {
        id: confirmModal
        onShouldBeVisibleChanged: {
            if (shouldBeVisible) {
                muxModal.shouldHaveFocus = false;
                muxModal.contentWindow.visible = false;
                return;
            }
            if (muxModal.shouldBeVisible) {
                muxModal.contentWindow.visible = true;
            }
            Qt.callLater(function () {
                if (!muxModal.shouldBeVisible) {
                    return;
                }
                muxModal.shouldHaveFocus = true;
                muxModal.modalFocusScope.forceActiveFocus();
                if (muxPanel.searchField) {
                    muxPanel.searchField.forceActiveFocus();
                }
            });
        }
    }

    directContent: Item {
        id: muxPanel

        clip: false

        property alias searchField: searchField

        Keys.onPressed: event => {
            if ((event.key === Qt.Key_J && (event.modifiers & Qt.ControlModifier)) || (event.key === Qt.Key_Down)) {
                selectNext();
                event.accepted = true;
            } else if ((event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) || (event.key === Qt.Key_Up)) {
                selectPrevious();
                event.accepted = true;
            } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
                createNewSession();
                event.accepted = true;
            } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
                if (MuxService.supportsRename && selectedIndex >= 0 && selectedIndex < filteredSessions.length) {
                    renameSession(filteredSessions[selectedIndex].name);
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                if (selectedIndex >= 0 && selectedIndex < filteredSessions.length) {
                    killSession(filteredSessions[selectedIndex].name);
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                hide();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                activateSelected();
                event.accepted = true;
            }
        }

        Column {
            width: parent.width - Theme.spacingM * 2
            height: parent.height - Theme.spacingM * 2
            x: Theme.spacingM
            y: Theme.spacingM
            spacing: Theme.spacingS

            // Header
            Item {
                width: parent.width
                height: 40

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("%1 Sessions", "session manager title, %1 is the terminal multiplexer name").arg(MuxService.displayName)
                    font.pixelSize: Theme.fontSizeLarge + 4
                    color: Theme.surfaceText
                }

                StyledText {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const total = MuxService.sessions.length;
                        const filtered = muxModal.filteredSessions.length;
                        const activePart = total === 1 ? I18n.tr("%1 active session", "singular, %1 is 1, multiplexer session count").arg(total) : I18n.tr("%1 active sessions", "plural, %1 is a count of multiplexer sessions").arg(total);
                        const filteredPart = filtered === 1 ? I18n.tr("%1 filtered", "%1 is a count of sessions matching the search").arg(filtered) : I18n.tr("%1 filtered").arg(filtered);
                        return activePart + ", " + filteredPart;
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                }
            }

            // Search field
            DSearchField {
                id: searchField

                width: parent.width
                font.pixelSize: Theme.fontSizeMedium
                placeholderText: I18n.tr("Search sessions...")
                keyForwardTargets: [muxPanel]

                onTextEdited: {
                    muxModal.searchText = text;
                    muxModal.selectedIndex = 0;
                }
            }

            // New Session Button
            Rectangle {
                width: parent.width
                height: 56
                radius: Theme.cornerRadius
                color: muxModal.selectedIndex === -1 ? Theme.selectedContainer : (newMouse.containsMouse ? Theme.foregroundColor(Theme.chipSurface, true) : Theme.floatingWindowNestedSurface)
                border.width: Theme.layerOutlineWidth
                border.color: Theme.outlineMedium

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingM

                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: Theme.fullRadius(width, height)
                        color: Theme.primaryContainer

                        DIcon {
                            anchors.centerIn: parent
                            name: "add"
                            size: Theme.iconSize
                            color: Theme.accentOnPrimaryContainer
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXXS

                        StyledText {
                            text: I18n.tr("New Session")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: I18n.tr("Create a new %1 session (^N)", "button label, %1 is the terminal multiplexer name").arg(MuxService.displayName)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                MouseArea {
                    id: newMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: muxModal.createNewSession()
                }
            }

            // Sessions List
            Rectangle {
                width: parent.width
                height: parent.height - 88 - 48 - shortcutsBar.height - Theme.spacingS * 3
                radius: Theme.cornerRadius
                color: "transparent"

                DFlickable {
                    anchors.fill: parent
                    clip: true
                    contentHeight: sessionsColumn.height

                    Column {
                        id: sessionsColumn
                        width: parent.width
                        spacing: Theme.spacingXS

                        Repeater {
                            model: ScriptModel {
                                values: muxModal.filteredSessions
                            }

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                width: parent.width
                                height: 64
                                radius: Theme.cornerRadius
                                color: muxModal.selectedIndex === index ? Theme.selectedContainer : (sessionMouse.containsMouse ? Theme.cardSurface : Theme.withAlpha(Theme.cardSurface, 0))
                                border.width: muxModal.selectedIndex === index || sessionMouse.containsMouse ? Theme.layerOutlineWidth : 0
                                border.color: Theme.outlineMedium

                                MouseArea {
                                    id: sessionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: muxModal.attachToSession(modelData.name)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    spacing: Theme.spacingM

                                    // Avatar
                                    Rectangle {
                                        Layout.preferredWidth: 40
                                        Layout.preferredHeight: 40
                                        radius: Theme.fullRadius(width, height)
                                        color: modelData.attached ? Theme.primaryContainer : Theme.chipSurface

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: modelData.name.charAt(0).toUpperCase()
                                            font.pixelSize: Theme.fontSizeLarge
                                            font.weight: Theme.fontWeightMedium
                                            color: modelData.attached ? Theme.accentOnPrimaryContainer : Theme.surfaceText
                                        }
                                    }

                                    // Info
                                    Column {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingXXS

                                        StyledText {
                                            text: modelData.name
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Theme.fontWeightMedium
                                            color: Theme.surfaceText
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            text: {
                                                var parts = [];
                                                if (modelData.windows !== "N/A")
                                                    parts.push(modelData.windows === 1 ? I18n.tr("%1 window", "singular, %1 is 1, windows in a multiplexer session").arg(modelData.windows) : I18n.tr("%1 windows", "plural, %1 is a count of windows in a multiplexer session").arg(modelData.windows));
                                                parts.push(modelData.attached ? I18n.tr("attached", "multiplexer session state, a client is attached") : I18n.tr("detached", "multiplexer session state, no client attached"));
                                                return parts.join(" \u2022 ");
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                    }

                                    // Rename button (tmux only)
                                    Rectangle {
                                        Accessible.role: Accessible.Button
                                        Accessible.name: I18n.tr("Rename")
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36
                                        radius: Theme.fullRadius(width, height)
                                        visible: MuxService.supportsRename
                                        color: renameMouse.containsMouse ? Theme.chipSurface : Theme.withAlpha(Theme.chipSurface, 0)

                                        DIcon {
                                            anchors.centerIn: parent
                                            name: "edit"
                                            size: Theme.iconSizeSmall
                                            color: renameMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                        }

                                        MouseArea {
                                            id: renameMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: muxModal.renameSession(modelData.name)
                                        }
                                    }

                                    // Delete button
                                    Rectangle {
                                        Accessible.role: Accessible.Button
                                        Accessible.name: I18n.tr("Delete")
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36
                                        radius: Theme.fullRadius(width, height)
                                        color: deleteMouse.containsMouse ? Theme.errorContainer : Theme.withAlpha(Theme.errorContainer, 0)

                                        DIcon {
                                            anchors.centerIn: parent
                                            name: "delete"
                                            size: Theme.iconSizeSmall
                                            color: deleteMouse.containsMouse ? Theme.error : Theme.surfaceVariantText
                                        }

                                        MouseArea {
                                            id: deleteMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                muxModal.killSession(modelData.name);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Empty state
                        Item {
                            width: parent.width
                            height: muxModal.filteredSessions.length === 0 ? 200 : 0
                            visible: muxModal.filteredSessions.length === 0

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.spacingM

                                DIcon {
                                    name: muxModal.searchText.length > 0 ? "search_off" : "terminal"
                                    size: 48
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: muxModal.searchText.length > 0 ? I18n.tr("No sessions found") : I18n.tr("No active %1 sessions", "empty state, %1 is the terminal multiplexer name").arg(MuxService.displayName)
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: muxModal.searchText.length > 0 ? I18n.tr("Try a different search") : I18n.tr("Press Ctrl+N or click 'New Session' to create one")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }
                }
            }

            DKeyHints {
                id: shortcutsBar

                width: parent.width
                height: implicitHeight + Theme.spacingS
                hints: {
                    const shortcuts = [
                        {
                            keys: ["Up", "Down"],
                            label: I18n.tr("Navigate", "verb, keyboard shortcut hint for arrow keys")
                        },
                        {
                            keys: ["Return"],
                            label: I18n.tr("Attach", "verb, shortcut hint, attach to the selected multiplexer session")
                        },
                        {
                            keys: ["Ctrl+N"],
                            label: I18n.tr("New", "adjective, shortcut or button that creates a new session or note")
                        },
                        {
                            keys: ["Ctrl+D"],
                            label: I18n.tr("Kill")
                        },
                        {
                            keys: ["Escape"],
                            label: I18n.tr("Close")
                        }
                    ];
                    if (MuxService.supportsRename)
                        shortcuts.splice(3, 0, {
                            keys: ["Ctrl+R"],
                            label: I18n.tr("Rename")
                        });
                    return shortcuts;
                }
            }
        }
    }
}
