pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    required property var modal
    property var keyController: null

    property var entry: null
    property string editorText: ""
    property bool textLoaded: false
    property bool loadFailed: false

    Timer {
        id: loadTimeoutTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (!root.textLoaded) {
                root.loadFailed = true;
                ToastService.showError(I18n.tr("Failed to load clipboard entry", "clipboard editor: fetching the entry's full text failed"));
            }
        }
    }

    function releaseTextInputFocus() {
        if (editField) {
            editField.setFocus(false);
        }
    }

    function decodeEntryData(data) {
        if (!data) {
            return "";
        }
        if (typeof data !== "string") {
            return String(data);
        }

        const sanitized = data.replace(/\s+/g, "");
        if (sanitized.length === 0) {
            return "";
        }

        try {
            const decoded = Qt.atob(sanitized);
            if (!decoded) {
                return data;
            }

            let binary = "";
            if (typeof decoded === "string") {
                // Pre-6.11 Qt.atob returns a binary string directly
                binary = decoded;
            } else {
                // Qt 6.11+ Qt.atob returns an ArrayBuffer — convert to avoid O(n²) concat/stack limits
                const bytes = new Uint8Array(decoded);
                const chunkSize = 8192;
                const chunks = [];
                for (let i = 0; i < bytes.length; i += chunkSize) {
                    chunks.push(String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize)));
                }
                binary = chunks.join("");
            }

            if (!binary) {
                return data;
            }
            try {
                return decodeURIComponent(escape(binary));
            } catch (e) {
                return binary;
            }
        } catch (e) {
            return data;
        }
    }

    function fetchEntry(requestedId) {
        loadFailed = false;
        loadTimeoutTimer.restart();
        DMSService.sendRequest("clipboard.getEntry", {
            "id": requestedId
        }, function (response) {
            loadTimeoutTimer.stop();
            if (!root.entry || root.entry.id !== requestedId) {
                return;
            }
            if (response.error || !response.result) {
                root.loadFailed = true;
                ToastService.showError(I18n.tr("Failed to load clipboard entry", "clipboard editor: fetching the entry's full text failed"));
                if (!response.result) {
                    ClipboardService.refresh();
                }
                return;
            }
            const result = response.result;
            let fullText = "";
            if (result?.data) {
                fullText = root.decodeEntryData(result.data);
            } else {
                fullText = result?.preview ?? "";
            }

            if (!fullText || fullText.length === 0) {
                root.loadFailed = true;
                ToastService.showError(I18n.tr("Failed to load clipboard entry", "clipboard editor: fetching the entry's full text failed"));
                return;
            }
            root.loadFailed = false;
            root.textLoaded = true;
            root.editorText = fullText;
            if (editField) {
                if (fullText.length > 50000) {
                    Qt.callLater(function () {
                        if (editField) {
                            editField.text = fullText;
                            editField.cursorPosition = fullText.length;
                        }
                    });
                } else {
                    editField.text = fullText;
                    editField.cursorPosition = fullText.length;
                }
            }
        });
    }

    function setEntry(newEntry) {
        entry = newEntry;
        loadFailed = false;
        const hasFullText = typeof newEntry?.text === "string";
        textLoaded = !newEntry || !ClipboardService.canEditEntry(newEntry) || !(newEntry.id > 0) || hasFullText;
        editorText = newEntry?.text ?? newEntry?.preview ?? "";
        if (editField) {
            editField.text = editorText;
        }
        Qt.callLater(function () {
            if (editField) {
                editField.forceActiveFocus();
                editField.cursorPosition = editField.text.length;
            }
        });

        if (hasFullText || !newEntry || !ClipboardService.canEditEntry(newEntry) || !(newEntry.id > 0)) {
            loadTimeoutTimer.stop();
            return;
        }

        fetchEntry(newEntry.id);
    }

    function saveEntry(action) {
        const saveAction = action ?? "history";
        const entryId = root.entry?.id ?? 0;

        if (entryId > 0 && !root.textLoaded) {
            if (root.loadFailed) {
                ToastService.showError(I18n.tr("Failed to load clipboard entry", "clipboard editor: fetching the entry's full text failed"));
                root.fetchEntry(entryId);
            } else {
                ToastService.showWarning(I18n.tr("Loading full text, please wait...", "clipboard editor: save blocked while the entry's full text is still being fetched"));
            }
            return;
        }

        loadTimeoutTimer.stop();

        const onComplete = function () {
            if (saveAction === "history") {
                modal.mode = "history";
                Qt.callLater(function () {
                    ClipboardService.reset();
                    ClipboardService.refresh();
                    if (keyController) {
                        keyController.reset();
                    }
                });
                return;
            }
            if (saveAction === "close") {
                modal.hide();
                return;
            }
            if (saveAction === "paste") {
                ClipboardService.pasteClipboard(modal.hide);
            }
        };

        if (entryId > 0) {
            ClipboardService.editEntry(root.entry, root.editorText, function (response) {
                if (response.error) {
                    ToastService.showError(I18n.tr("Failed to update clipboard"));
                    return;
                }
                onComplete();
            });
            return;
        }

        DMSService.sendRequest("clipboard.copy", {
            "text": root.editorText
        }, function (response) {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to update clipboard"));
                return;
            }
            onComplete();
        });
    }

    function positionSaveMenu() {
        saveMenu.width = Math.max(saveMenuColumn.implicitWidth + saveMenu.padding * 2, saveButton.width);
        const pos = saveButton.mapToItem(Overlay.overlay, 0, 0);
        const popupW = saveMenu.width;
        const popupH = saveMenu.height;
        const overlayW = Overlay.overlay.width;
        const overlayH = Overlay.overlay.height;

        let x = pos.x + (saveButton.width - popupW) / 2;
        let y = pos.y + saveButton.height + 4;
        if (y + popupH > overlayH) {
            y = pos.y - popupH - 4;
        }

        x = Math.max(8, Math.min(x, overlayW - popupW - 8));
        y = Math.max(8, y);

        saveMenu.x = x;
        saveMenu.y = y;
    }

    function toggleSaveMenu() {
        if (saveMenu.visible) {
            saveMenu.close();
            return;
        }
        saveMenu.open();
        positionSaveMenu();
        Qt.callLater(positionSaveMenu);
    }

    Shortcut {
        sequences: ["Escape"]
        enabled: modal.mode === "editor"
        onActivated: modal.mode = "history"
    }

    Column {
        anchors.fill: parent
        anchors.margins: PopoutMetrics.contentPadding
        spacing: PopoutMetrics.contentGap

        Item {
            id: editorHeader
            width: parent.width
            height: ClipboardConstants.headerHeight

            DActionButton {
                iconName: "arrow_back"
                Accessible.name: I18n.tr("Back")
                iconSize: Theme.iconSize - 4
                iconColor: Theme.surfaceText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                onClicked: modal.mode = "history"
            }

            StyledText {
                text: I18n.tr("Edit Clipboard")
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.surfaceText
                font.weight: Theme.fontWeightMedium
                anchors.centerIn: parent
            }

            DActionButton {
                iconName: "close"
                Accessible.name: I18n.tr("Close")
                iconSize: Theme.iconSize - 4
                iconColor: Theme.surfaceText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onClicked: modal.mode = "history"
            }
        }

        DTextEdit {
            id: editField
            width: parent.width
            height: Math.max(Theme.fontSizeMedium * 8, parent.height - editorHeader.height - editorActions.height - PopoutMetrics.contentGap * 2)
            leftIconName: "edit"
            placeholderText: I18n.tr("Edit clipboard text")
            backgroundColor: Theme.floatingWindowFieldColor
            normalBorderColor: Theme.outlineMedium
            focusedBorderColor: Theme.primary
            keyForwardTargets: [editorKeyHandler]

            onTextEdited: root.editorText = text

            Item {
                id: editorKeyHandler

                Keys.onPressed: function (event) {
                    const hasCtrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    const hasShift = (event.modifiers & Qt.ShiftModifier) !== 0;

                    if (hasCtrl && event.key === Qt.Key_S) {
                        root.saveEntry(hasShift ? "close" : "history");
                        event.accepted = true;
                        return;
                    }
                    if (hasCtrl && hasShift && event.key === Qt.Key_V) {
                        root.saveEntry("paste");
                        event.accepted = true;
                        return;
                    }
                }
            }
        }

        RowLayout {
            id: editorActions
            width: parent.width
            spacing: Theme.spacingS

            Item {
                Layout.fillWidth: true
            }

            DButton {
                id: cancelButton
                text: I18n.tr("Cancel")
                backgroundColor: Theme.chipSurface
                textColor: Theme.surfaceText
                onClicked: modal.mode = "history"
            }

            RowLayout {
                id: saveButton
                spacing: Theme.spacingS
                opacity: root.textLoaded ? 1 : 0.6

                DButton {
                    text: I18n.tr("Save")
                    backgroundColor: Theme.primary
                    textColor: Theme.onPrimary
                    onClicked: root.saveEntry("history")
                }

                DIconButton {
                    variant: "filled"
                    iconName: saveMenu.visible ? "expand_less" : "expand_more"
                    tooltipText: I18n.tr("Save")
                    onClicked: root.toggleSaveMenu()
                }
            }
        }

        Popup {
            id: saveMenu
            parent: root.Overlay.overlay
            padding: Theme.spacingM
            modal: true
            dim: false
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

            background: StyledRect {
                radius: Theme.windowRadius
                color: Theme.floatingWindowNestedSurface
                border.color: Theme.outlineMedium
                border.width: Theme.layerOutlineWidth
            }

            contentItem: Column {
                id: saveMenuColumn
                spacing: Theme.spacingXS

                StyledRect {
                    implicitWidth: saveMenuRow.implicitWidth + Theme.spacingS * 2
                    implicitHeight: saveMenuRow.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: saveMenuSaveArea.containsMouse ? Theme.surfaceVariant : Theme.withAlpha(Theme.surfaceVariant, 0)

                    Row {
                        id: saveMenuRow
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        DIcon {
                            name: "save"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: I18n.tr("Save")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                        }
                    }

                    MouseArea {
                        id: saveMenuSaveArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            saveMenu.close();
                            root.saveEntry("history");
                        }
                    }
                }

                StyledRect {
                    implicitWidth: saveMenuCloseRow.implicitWidth + Theme.spacingS * 2
                    implicitHeight: saveMenuCloseRow.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: saveMenuCloseArea.containsMouse ? Theme.surfaceVariant : Theme.withAlpha(Theme.surfaceVariant, 0)

                    Row {
                        id: saveMenuCloseRow
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        DIcon {
                            name: "close"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: I18n.tr("Save and close")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                        }
                    }

                    MouseArea {
                        id: saveMenuCloseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            saveMenu.close();
                            root.saveEntry("close");
                        }
                    }
                }

                StyledRect {
                    implicitWidth: saveMenuPasteRow.implicitWidth + Theme.spacingS * 2
                    implicitHeight: saveMenuPasteRow.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: saveMenuPasteArea.containsMouse ? Theme.surfaceVariant : Theme.withAlpha(Theme.surfaceVariant, 0)
                    opacity: modal.pasteAvailable ? 1 : 0.5

                    Row {
                        id: saveMenuPasteRow
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        DIcon {
                            name: "content_paste"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: I18n.tr("Save and paste")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                        }
                    }

                    MouseArea {
                        id: saveMenuPasteArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: modal.pasteAvailable
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            saveMenu.close();
                            root.saveEntry("paste");
                        }
                    }
                }
            }
        }
    }
}
