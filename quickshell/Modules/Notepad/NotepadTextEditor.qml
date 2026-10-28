pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Column {
    id: root

    Component.onCompleted: {
        if (PluginService.isPluginLoaded("dankNotepadModule")) {
            pluginHighlightedHtml = SettingsData.getBuiltInPluginSetting("dankNotepadModule", "highlightedHtml", "");
        }
    }

    property alias text: textArea.text
    property alias textArea: textArea
    property bool contentLoaded: false
    property string lastSavedContent: ""
    property var currentTab: NotepadStorageService.tabs.length > NotepadStorageService.currentTabIndex ? NotepadStorageService.tabs[NotepadStorageService.currentTabIndex] : null
    property bool searchVisible: false
    property string searchQuery: ""
    property var searchMatches: []
    property int currentMatchIndex: -1
    property int matchCount: 0
    property bool inlinePreviewVisible: false
    property string previewMode: "split" // split | full
    property string pluginHighlightedHtml: ""
    property string lastPluginContent: ""
    property int loadRequestId: 0
    property bool ignoreNextExternalChange: false
    property bool watcherReloadPending: false
    property bool externalWatchPaused: false
    property bool inPopout: false
    property bool surfaceVisible: true
    // Tab ids are Date.now() timestamps (~1.78e12) which overflow a 32-bit `int`,
    // corrupting the value (e.g. -946062153) and breaking buffer keying. `var`
    // holds the full JS-safe integer.
    property var loadedTabId: -1
    property bool applyingShared: false
    property bool showPathInfo: false

    function currentFilePath() {
        if (!currentTab)
            return "";
        return currentTab.isTemporary ? (NotepadStorageService.baseDir + "/" + currentTab.filePath) : currentTab.filePath;
    }

    signal saveRequested
    signal openRequested
    signal newRequested
    signal previewRequested
    signal escapePressed
    signal contentChanged
    signal settingsRequested
    signal popoutRequested
    signal dockRequested
    signal conflictDetected(string diskContent)
    signal largeFileConfirmRequested(var tab, real size)
    signal autoSaveRequested

    function hasUnsavedChanges() {
        if (!currentTab || !contentLoaded) {
            return false;
        }

        if (currentTab.isTemporary) {
            return textArea.text.length > 0;
        }
        return textArea.text !== lastSavedContent;
    }

    function commitLiveBuffer() {
        if (loadedTabId < 0 || !contentLoaded)
            return;
        NotepadStorageService.setSessionBuffer(loadedTabId, textArea.text, lastSavedContent);
    }

    function loadCurrentTabContent() {
        if (!currentTab)
            return;
        const requestedTabId = currentTab.id;
        const requestId = ++loadRequestId;
        contentLoaded = false;
        NotepadStorageService.loadTabContent(NotepadStorageService.currentTabIndex, content => {
            const activeTab = NotepadStorageService.tabs.length > NotepadStorageService.currentTabIndex ? NotepadStorageService.tabs[NotepadStorageService.currentTabIndex] : null;
            if (requestId !== loadRequestId || !activeTab || activeTab.id !== requestedTabId)
                return;

            const buffer = NotepadStorageService.getSessionBuffer(requestedTabId);
            if (buffer !== undefined) {
                applyingShared = true;
                lastSavedContent = buffer.baseline;
                textArea.text = buffer.content;
                applyingShared = false;
                loadedTabId = requestedTabId;
                contentLoaded = true;
                syncContentToPlugin();
                applyDiskContent(content);
                return;
            }

            applyingShared = true;
            lastSavedContent = content;
            textArea.text = content;
            applyingShared = false;
            loadedTabId = requestedTabId;
            contentLoaded = true;
            syncContentToPlugin();
        }, size => {
            if (requestId !== loadRequestId || !currentTab || currentTab.id !== requestedTabId)
                return;
            applyingShared = true;
            lastSavedContent = "";
            textArea.text = "";
            applyingShared = false;
            root.largeFileConfirmRequested(currentTab, size);
        });
    }

    function saveCurrentTabContent() {
        if (!currentTab || !contentLoaded)
            return;
        if (!currentTab.isTemporary)
            return;
        NotepadStorageService.saveTabContent(NotepadStorageService.currentTabIndex, textArea.text);
        lastSavedContent = textArea.text;
        NotepadStorageService.clearSessionBuffer(loadedTabId);
    }

    function autoSaveToSession() {
        commitLiveBuffer();
        if (!currentTab || !contentLoaded)
            return;
        if (currentTab.isTemporary) {
            saveCurrentTabContent();
        } else if (SettingsData.notepadAutoSave) {
            root.autoSaveRequested();
        }
    }

    function syncFromDisk() {
        if (!currentTab)
            return;
        loadCurrentTabContent();
    }

    function applyDiskContent(diskContent) {
        if (diskContent === undefined || diskContent === null)
            return;
        if (diskContent === textArea.text) {
            lastSavedContent = diskContent;
            return;
        }
        if (diskContent === lastSavedContent) {
            return;
        }
        if (textArea.text === lastSavedContent) {
            reloadFromDisk(diskContent);
        } else if (surfaceVisible) {
            conflictDetected(diskContent);
        }
    }

    function reloadFromDisk(diskContent) {
        applyingShared = true;
        contentLoaded = false;
        textArea.text = diskContent;
        lastSavedContent = diskContent;
        contentLoaded = true;
        applyingShared = false;
        NotepadStorageService.clearSessionBuffer(loadedTabId);
        syncContentToPlugin();
    }

    function setTextDocumentLineHeight() {
        return;
    }

    property string lastTextForLineModel: ""
    property var lineModel: []

    function updateLineModel() {
        if (!SettingsData.notepadShowLineNumbers) {
            lineModel = [];
            lastTextForLineModel = "";
            return;
        }

        if (textArea.text !== lastTextForLineModel || lineModel.length === 0) {
            lastTextForLineModel = textArea.text;
            lineModel = textArea.text.split('\n');
        }
    }

    function performSearch() {
        let matches = [];
        currentMatchIndex = -1;

        if (!searchQuery || searchQuery.length === 0) {
            searchMatches = [];
            matchCount = 0;
            textArea.select(0, 0);
            return;
        }

        const text = textArea.text;
        const query = searchQuery.toLowerCase();
        let index = 0;

        while (index < text.length) {
            const foundIndex = text.toLowerCase().indexOf(query, index);
            if (foundIndex === -1)
                break;
            matches.push({
                start: foundIndex,
                end: foundIndex + searchQuery.length
            });
            index = foundIndex + 1;
        }

        searchMatches = matches;
        matchCount = matches.length;

        if (matchCount > 0) {
            currentMatchIndex = 0;
            highlightCurrentMatch();
        } else {
            textArea.select(0, 0);
        }
    }

    function highlightCurrentMatch() {
        if (currentMatchIndex >= 0 && currentMatchIndex < searchMatches.length) {
            const match = searchMatches[currentMatchIndex];

            textArea.cursorPosition = match.start;
            textArea.moveCursorSelection(match.end, TextEdit.SelectCharacters);

            const flickable = textArea.parent;
            if (flickable && flickable.contentY !== undefined) {
                const lineHeight = textArea.font.pixelSize * 1.5;
                const approxLine = textArea.text.substring(0, match.start).split('\n').length;
                const targetY = approxLine * lineHeight - flickable.height / 2;
                flickable.contentY = Math.max(0, Math.min(targetY, flickable.contentHeight - flickable.height));
            }
        }
    }

    function findNext() {
        if (matchCount === 0 || searchMatches.length === 0)
            return;
        currentMatchIndex = (currentMatchIndex + 1) % matchCount;
        highlightCurrentMatch();
    }

    function findPrevious() {
        if (matchCount === 0 || searchMatches.length === 0)
            return;
        currentMatchIndex = currentMatchIndex <= 0 ? matchCount - 1 : currentMatchIndex - 1;
        highlightCurrentMatch();
    }

    function showSearch() {
        searchVisible = true;
        Qt.callLater(() => {
            searchField.forceActiveFocus();
        });
    }

    function togglePreview() {
        if (!inlinePreviewVisible) {
            inlinePreviewVisible = true;
            previewMode = "split";
        } else if (previewMode === "split") {
            previewMode = "full";
        } else {
            inlinePreviewVisible = false;
            previewMode = "split";
        }
        syncContentToPlugin();
    }

    function renderPreviewHtml() {
        if (!inlinePreviewVisible)
            return "";
        return pluginHighlightedHtml.length > 0 ? pluginHighlightedHtml : "<p><i>Rendering preview…</i></p>";
    }

    function syncContentToPlugin() {
        if (!PluginService.isPluginLoaded("dankNotepadModule"))
            return;
        if (!currentTab)
            return;
        const filePath = currentTab?.filePath || "";
        const baseName = filePath.split('/').pop();
        const ext = baseName.includes('.') ? baseName.split('.').pop().toLowerCase() : "";
        const content = textArea.text;

        if (content === lastPluginContent && SettingsData.getBuiltInPluginSetting("dankNotepadModule", "previewActive", false) === inlinePreviewVisible) {
            return;
        }

        lastPluginContent = content;
        SettingsData.setBuiltInPluginSetting("dankNotepadModule", "previewActive", inlinePreviewVisible);
        SettingsData.setBuiltInPluginSetting("dankNotepadModule", "currentFilePath", filePath);
        SettingsData.setBuiltInPluginSetting("dankNotepadModule", "currentFileExtension", ext);
        SettingsData.setBuiltInPluginSetting("dankNotepadModule", "sourceContent", content);
        SettingsData.setBuiltInPluginSetting("dankNotepadModule", "updatedAt", Date.now());
    }

    function hideSearch() {
        searchVisible = false;
        searchQuery = "";
        searchMatches = [];
        matchCount = 0;
        currentMatchIndex = -1;
        textArea.select(0, 0);
        textArea.forceActiveFocus();
    }

    function copyPlainTextToClipboard() {
        if (!inlinePreviewVisible || !textArea.text)
            return;
        const content = textArea.text;
        if (content.length === 0)
            return;
        const proc = clipboardCopyProcComp.createObject(root, {
            content: content,
            running: true
        });
        proc.exited.connect(() => {
            ToastService.showInfo(I18n.tr("Copied to clipboard"));
            proc.destroy();
        });
    }

    function copyHtmlToClipboard() {
        if (!inlinePreviewVisible || !pluginHighlightedHtml)
            return;
        if (pluginHighlightedHtml.length === 0)
            return;
        const proc = clipboardCopyProcComp.createObject(root, {
            content: pluginHighlightedHtml,
            running: true
        });
        proc.exited.connect(() => {
            ToastService.showInfo(I18n.tr("HTML copied to clipboard"));
            proc.destroy();
        });
    }

    Component {
        id: clipboardCopyProcComp
        Process {
            property string content: ""
            command: ["sh", "-c", "printf '%s' \"$CONTENT\" | dms clipboard copy"]
            environment: ({
                    "CONTENT": content
                })
        }
    }

    spacing: Theme.spacingM

    StyledRect {
        id: searchBar
        width: parent.width
        height: 48
        visible: searchVisible
        opacity: searchVisible ? 1 : 0
        color: Theme.floatingWindowNestedSurface
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        radius: Theme.cornerRadius

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingS

            DSearchField {
                id: searchField
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                leftIconSize: Theme.iconSizeSmall
                font.pixelSize: Theme.fontSizeMedium
                placeholderText: I18n.tr("Find in note...")
                topPadding: 0
                bottomPadding: 0
                keyForwardTargets: [searchKeyHandler]

                Component.onCompleted: {
                    text = root.searchQuery;
                }

                onTextChanged: {
                    if (root.searchQuery !== text) {
                        root.searchQuery = text;
                        root.performSearch();
                    }
                }

                readonly property string rootSearchQuery: root.searchQuery

                onRootSearchQueryChanged: {
                    if (text !== rootSearchQuery) {
                        text = rootSearchQuery;
                    }
                }

                Item {
                    id: searchKeyHandler

                    Keys.onEscapePressed: event => {
                        root.hideSearch();
                        event.accepted = true;
                    }
                    Keys.onReturnPressed: event => {
                        if (event.modifiers & Qt.ShiftModifier) {
                            root.findPrevious();
                        } else {
                            root.findNext();
                        }
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: event => {
                        if (event.modifiers & Qt.ShiftModifier) {
                            root.findPrevious();
                        } else {
                            root.findNext();
                        }
                        event.accepted = true;
                    }
                }
            }

            // Match count display
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: matchCount > 0 ? "%1/%2".arg(currentMatchIndex + 1).arg(matchCount) : searchQuery.length > 0 ? I18n.tr("No matches") : ""
                font.pixelSize: Theme.fontSizeSmall
                color: matchCount > 0 ? Theme.primary : Theme.surfaceTextMedium
                visible: searchQuery.length > 0
                Layout.rightMargin: Theme.spacingS
            }

            // Navigation buttons
            DActionButton {
                id: prevButton
                Layout.alignment: Qt.AlignVCenter
                iconName: "keyboard_arrow_up"
                Accessible.name: I18n.tr("Previous")
                iconSize: Theme.iconSize
                iconColor: matchCount > 0 ? Theme.surfaceText : Theme.surfaceTextAlpha
                enabled: matchCount > 0
                onClicked: root.findPrevious()
            }

            DActionButton {
                id: nextButton
                Layout.alignment: Qt.AlignVCenter
                iconName: "keyboard_arrow_down"
                Accessible.name: I18n.tr("Next")
                iconSize: Theme.iconSize
                iconColor: matchCount > 0 ? Theme.surfaceText : Theme.surfaceTextAlpha
                enabled: matchCount > 0
                onClicked: root.findNext()
            }

            DActionButton {
                id: closeSearchButton
                Layout.alignment: Qt.AlignVCenter
                iconName: "close"
                Accessible.name: I18n.tr("Close")
                iconSize: Theme.iconSize - 2
                iconColor: Theme.surfaceText
                onClicked: root.hideSearch()
            }
        }
    }

    StyledRect {
        width: parent.width
        height: parent.height - bottomControls.height - Theme.spacingM - (searchVisible ? searchBar.height + Theme.spacingM : 0)
        color: Theme.withAlpha(Theme.cardSurface, Theme.notepadTransparency)
        border.color: Theme.outlineMedium
        border.width: Theme.layerOutlineWidth
        radius: Theme.cornerRadius

        RowLayout {
            id: editorPreviewRow
            anchors.fill: parent
            anchors.margins: 1
            spacing: Theme.spacingM

            Item {
                id: editorPane
                visible: !inlinePreviewVisible || previewMode === "split"
                Layout.fillHeight: true
                Layout.fillWidth: !inlinePreviewVisible || previewMode === "split"
                Layout.preferredWidth: inlinePreviewVisible ? parent.width * 0.55 : parent.width
                clip: true

                DFlickable {
                    id: flickable
                    anchors.fill: parent
                    clip: true
                    contentWidth: width - 11

                    Rectangle {
                        id: lineNumberArea
                        anchors.left: parent.left
                        anchors.top: parent.top
                        width: SettingsData.notepadShowLineNumbers ? Math.max(30, 32 + Theme.spacingXS) : 0
                        height: textArea.contentHeight + textArea.topPadding + textArea.bottomPadding
                        color: "transparent"
                        visible: SettingsData.notepadShowLineNumbers

                        ListView {
                            id: lineNumberList
                            anchors.top: parent.top
                            anchors.topMargin: textArea.topPadding
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            width: 32
                            height: textArea.contentHeight
                            model: SettingsData.notepadShowLineNumbers ? root.lineModel : []
                            interactive: false
                            spacing: 0

                            delegate: Item {
                                id: lineDelegate
                                required property int index
                                required property string modelData
                                width: 32
                                height: measuringText.contentHeight

                                StyledText {
                                    id: measuringText
                                    width: textArea.width - textArea.leftPadding - textArea.rightPadding
                                    text: modelData || " "
                                    font: textArea.font
                                    wrapMode: Text.Wrap
                                    visible: false
                                }

                                StyledText {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    anchors.top: parent.top
                                    text: index + 1
                                    font.family: textArea.font.family
                                    font.pixelSize: textArea.font.pixelSize
                                    color: Theme.surfaceVariantText
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }
                    }

                    TextArea.flickable: TextArea {
                        id: textArea
                        placeholderText: ""
                        placeholderTextColor: Theme.surfaceTextSecondary
                        font.family: SettingsData.notepadUseMonospace ? SettingsData.monoFontFamily : (SettingsData.notepadFontFamily || SettingsData.fontFamily)
                        font.pixelSize: SettingsData.notepadFontSize * SettingsData.fontScale
                        font.letterSpacing: 0
                        color: Theme.surfaceText
                        selectedTextColor: Theme.background
                        selectionColor: Theme.primary
                        selectByMouse: true
                        selectByKeyboard: true
                        wrapMode: TextArea.Wrap
                        focus: true
                        activeFocusOnTab: true
                        textFormat: TextEdit.PlainText
                        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        persistentSelection: true
                        tabStopDistance: 40
                        leftPadding: (SettingsData.notepadShowLineNumbers ? lineNumberArea.width + Theme.spacingXS : Theme.spacingM)
                        topPadding: Theme.spacingM
                        rightPadding: Theme.spacingM
                        bottomPadding: Theme.spacingM
                        cursorDelegate: DTextCursor {
                            id: notepadCursor
                            width: 1.5
                            color: Theme.surfaceText
                            x: textArea.cursorRectangle.x
                            y: textArea.cursorRectangle.y
                            height: textArea.cursorRectangle.height
                            shown: textArea.cursorVisible

                            readonly property int areaCursorPosition: textArea.cursorPosition

                            onAreaCursorPositionChanged: resetBlink()
                        }

                        Component.onCompleted: {
                            loadCurrentTabContent();
                            setTextDocumentLineHeight();
                            root.updateLineModel();
                            Qt.callLater(() => {
                                textArea.forceActiveFocus();
                            });
                        }

                        Connections {
                            target: NotepadStorageService
                            function onCurrentTabIndexChanged() {
                                root.commitLiveBuffer();
                                loadCurrentTabContent();
                                Qt.callLater(() => {
                                    textArea.forceActiveFocus();
                                });
                            }
                            function onTabsChanged() {
                                if (NotepadStorageService.tabs.length > 0 && !contentLoaded) {
                                    loadCurrentTabContent();
                                }
                            }
                        }

                        readonly property bool settingsShowLineNumbers: SettingsData.notepadShowLineNumbers

                        onSettingsShowLineNumbersChanged: root.updateLineModel()

                        onTextChanged: {
                            // Debounced flush to the shared buffer (+ optional disk
                            // autosave) for every loaded tab, not just scratch notes.
                            if (contentLoaded && !applyingShared) {
                                autoSaveTimer.restart();
                            }
                            root.contentChanged();
                            root.updateLineModel();
                            pluginSyncTimer.restart();
                        }

                        Keys.onEscapePressed: event => {
                            root.escapePressed();
                            event.accepted = true;
                        }

                        Keys.onPressed: event => {
                            if (event.modifiers & Qt.ControlModifier) {
                                switch (event.key) {
                                case Qt.Key_S:
                                    event.accepted = true;
                                    root.saveRequested();
                                    break;
                                case Qt.Key_O:
                                    event.accepted = true;
                                    root.openRequested();
                                    break;
                                case Qt.Key_N:
                                    event.accepted = true;
                                    root.newRequested();
                                    break;
                                case Qt.Key_A:
                                    event.accepted = true;
                                    textArea.selectAll();
                                    break;
                                case Qt.Key_F:
                                    event.accepted = true;
                                    root.showSearch();
                                    break;
                                case Qt.Key_P:
                                    if (PluginService.isPluginLoaded("dankNotepadModule")) {
                                        event.accepted = true;
                                        root.previewRequested();
                                    }
                                    break;
                                }
                            }
                        }

                        background: Rectangle {
                            color: "transparent"
                        }
                    }

                    StyledText {
                        id: placeholderOverlay
                        text: I18n.tr("Start typing your notes here...")
                        color: Theme.surfaceTextSecondary
                        font.family: textArea.font.family
                        font.pixelSize: textArea.font.pixelSize
                        visible: textArea.text.length === 0 && !textArea.inputMethodComposing
                        anchors.left: textArea.left
                        anchors.top: textArea.top
                        anchors.leftMargin: textArea.leftPadding
                        anchors.topMargin: textArea.topPadding
                        z: textArea.z + 1
                    }
                }
            }

            Rectangle {
                id: previewDivider
                visible: inlinePreviewVisible && previewMode === "split"
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: Theme.outlineMedium
            }

            Item {
                id: previewPane
                visible: inlinePreviewVisible
                Layout.fillHeight: true
                Layout.fillWidth: previewMode === "full"
                Layout.preferredWidth: previewMode === "full" ? parent.width : parent.width * 0.45
                clip: true

                // Preview header with copy buttons
                Rectangle {
                    id: previewHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 36
                    color: Theme.withAlpha(Theme.cardSurface, Theme.notepadTransparency)
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium
                    z: 2

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingS

                        // Copy plain text button
                        DActionButton {
                            iconName: "content_copy"
                            Accessible.name: I18n.tr("Copy Text")
                            iconSize: Theme.iconSize - 4
                            iconColor: Theme.surfaceTextMedium
                            onClicked: copyPlainTextToClipboard()
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Copy Text")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                        }

                        Rectangle {
                            width: 1
                            height: 20
                            color: Theme.outlineVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Copy HTML button
                        DActionButton {
                            iconName: "code"
                            Accessible.name: I18n.tr("Copy HTML")
                            iconSize: Theme.iconSize - 4
                            iconColor: Theme.surfaceTextMedium
                            onClicked: copyHtmlToClipboard()
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Copy HTML")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                        }
                    }
                }

                DFlickable {
                    id: previewFlickable
                    anchors.top: previewHeader.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.topMargin: Theme.spacingS
                    clip: true
                    contentWidth: width - 11
                    contentHeight: previewText.paintedHeight + Theme.spacingM * 2

                    StyledText {
                        id: previewText
                        width: parent.width - Theme.spacingM
                        padding: Theme.spacingM
                        wrapMode: Text.WordWrap
                        textFormat: Text.RichText
                        text: inlinePreviewVisible ? renderPreviewHtml() : ""
                        color: Theme.surfaceText
                        font.family: SettingsData.notepadFontFamily || SettingsData.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        linkColor: Theme.primary

                        onLinkActivated: url => Qt.openUrlExternally(url)
                    }
                }
            }
        }
    }

    Column {
        id: bottomControls
        width: parent.width
        spacing: Theme.spacingS

        Item {
            id: buttonBarItem
            width: parent.width
            height: 32

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingL

                Row {
                    spacing: Theme.spacingS
                    DActionButton {
                        iconName: "save"
                        Accessible.name: I18n.tr("Save")
                        iconSize: Theme.iconSize - 2
                        iconColor: Theme.primary
                        enabled: currentTab && (hasUnsavedChanges() || textArea.text.length > 0)
                        onClicked: root.saveRequested()
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Save")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                }

                Row {
                    spacing: Theme.spacingS
                    DActionButton {
                        iconName: "folder_open"
                        Accessible.name: I18n.tr("Open")
                        iconSize: Theme.iconSize - 2
                        iconColor: Theme.secondary
                        onClicked: root.openRequested()
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Open")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                }

                Row {
                    spacing: Theme.spacingS
                    DActionButton {
                        iconName: "note_add"
                        Accessible.name: I18n.tr("New")
                        iconSize: Theme.iconSize - 2
                        iconColor: Theme.surfaceText
                        onClicked: root.newRequested()
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("New")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                }

                Row {
                    spacing: Theme.spacingS
                    visible: PluginService.isPluginLoaded("dankNotepadModule")
                    DActionButton {
                        iconName: inlinePreviewVisible ? "visibility" : "visibility_off"
                        Accessible.name: I18n.tr("Preview")
                        iconSize: Theme.iconSize - 2
                        iconColor: Theme.surfaceText
                        enabled: textArea.text.length > 0
                        onClicked: root.previewRequested()
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Preview")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                }
            }

            Row {
                id: rightButtonRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DActionButton {
                    visible: !root.inPopout
                    iconName: "open_in_new"
                    tooltipText: I18n.tr("Open as window")
                    iconSize: Theme.iconSize - 2
                    iconColor: Theme.surfaceText
                    onClicked: root.popoutRequested()
                }

                DActionButton {
                    visible: root.inPopout
                    iconName: "dock_to_right"
                    tooltipText: I18n.tr("Dock")
                    iconSize: Theme.iconSize - 2
                    iconColor: Theme.surfaceText
                    onClicked: root.dockRequested()
                }

                DActionButton {
                    iconName: "more_horiz"
                    tooltipText: I18n.tr("Settings")
                    iconSize: Theme.iconSize - 2
                    iconColor: Theme.surfaceText
                    onClicked: root.settingsRequested()
                }
            }

            StyledRect {
                id: pathInfoPopup
                visible: root.showPathInfo
                anchors.right: parent.right
                anchors.bottom: parent.top
                anchors.bottomMargin: Theme.spacingS
                width: Math.min(root.width, 360)
                height: pathInfoRow.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Theme.floatingWindowNestedSurface
                border.color: Theme.outlineMedium
                border.width: Theme.layerOutlineWidth
                z: 10

                Row {
                    id: pathInfoRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingS

                    DIcon {
                        name: currentTab && currentTab.isTemporary ? "draft" : "description"
                        size: Theme.iconSize - 4
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        width: pathInfoRow.width - (Theme.iconSize - 4) - copyPathButton.width - Theme.spacingS * 2
                        text: root.currentFilePath()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        elide: Text.ElideMiddle
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DActionButton {
                        id: copyPathButton
                        iconName: "content_copy"
                        Accessible.name: I18n.tr("Copy path")
                        iconSize: Theme.iconSize - 6
                        iconColor: Theme.surfaceTextMedium
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            const proc = clipboardCopyProcComp.createObject(root, {
                                content: root.currentFilePath(),
                                running: true
                            });
                            proc.exited.connect(() => {
                                ToastService.showInfo(I18n.tr("Path copied to clipboard"));
                                proc.destroy();
                            });
                        }
                    }
                }
            }
        }

        Row {
            id: statusRow
            width: parent.width
            spacing: Theme.spacingL

            StyledText {
                text: {
                    const len = textArea.text.length;
                    if (len === 0)
                        return I18n.tr("Empty");
                    return len === 1 ? I18n.tr("%1 character", "singular, notepad status bar character count, %1 is 1").arg(len) : I18n.tr("%1 characters", "plural, notepad status bar character count, %1 is a count").arg(len);
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceTextMedium
            }

            StyledText {
                text: textArea.lineCount === 1 ? I18n.tr("Line: %1", "singular, notepad status bar line count, %1 is 1").arg(textArea.lineCount) : I18n.tr("Lines: %1", "plural, notepad status bar line count, %1 is a count").arg(textArea.lineCount)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceTextMedium
                visible: textArea.text.length > 0
                opacity: 1.0
            }

            Row {
                visible: textArea.text.length > 0
                spacing: Theme.spacingXS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool savingToDisk: autoSaveTimer.running && currentTab && (currentTab.isTemporary || SettingsData.notepadAutoSave)
                    text: {
                        if (savingToDisk) {
                            return I18n.tr("Saving...");
                        }

                        if (currentTab && currentTab.isTemporary) {
                            return I18n.tr("Auto saved");
                        }

                        return hasUnsavedChanges() ? I18n.tr("Unsaved changes") : I18n.tr("Saved", "notepad status, file has no unsaved changes", true);
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: {
                        if (savingToDisk) {
                            return Theme.primary;
                        }

                        if (currentTab && currentTab.isTemporary) {
                            return Theme.success;
                        }

                        return hasUnsavedChanges() ? Theme.warning : Theme.success;
                    }
                }

                DActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "info"
                    tooltipText: I18n.tr("File info")
                    iconSize: Theme.iconSizeSmall
                    iconColor: root.showPathInfo ? Theme.primary : Theme.surfaceTextMedium
                    buttonSize: 20
                    onClicked: root.showPathInfo = !root.showPathInfo
                }
            }
        }
    }

    Timer {
        id: autoSaveTimer
        interval: 2000
        repeat: false
        onTriggered: {
            autoSaveToSession();
        }
    }

    Timer {
        id: pluginSyncTimer
        interval: 350
        repeat: false
        onTriggered: syncContentToPlugin()
    }

    FileView {
        id: externalWatch
        path: (!root.externalWatchPaused && currentTab && !currentTab.isTemporary && currentTab.filePath && root.loadedTabId === currentTab.id) ? currentTab.filePath : ""
        blockLoading: true
        preload: true
        watchChanges: true

        onFileChanged: {
            root.watcherReloadPending = true;
            reload();
        }

        onLoaded: {
            if (root.ignoreNextExternalChange) {
                root.ignoreNextExternalChange = false;
                root.lastSavedContent = externalWatch.text();
                root.watcherReloadPending = false;
                return;
            }
            if (!root.watcherReloadPending)
                return;
            root.watcherReloadPending = false;
            if (!root.contentLoaded || !root.currentTab || root.currentTab.isTemporary)
                return;
            if (!root.surfaceVisible)
                return;
            root.applyDiskContent(externalWatch.text());
        }

        onLoadFailed: error => {}
    }

    readonly property var settingsBuiltInPluginSettings: SettingsData.builtInPluginSettings
    readonly property int storageSessionBufferRevision: NotepadStorageService.sessionBufferRevision

    onSettingsBuiltInPluginSettingsChanged: {
        if (PluginService.isPluginLoaded("dankNotepadModule")) {
            pluginHighlightedHtml = SettingsData.getBuiltInPluginSetting("dankNotepadModule", "highlightedHtml", "");
        }
    }

    onStorageSessionBufferRevisionChanged: {
        if (applyingShared || !contentLoaded || loadedTabId < 0)
            return;
        if (textArea.activeFocus)
            return;
        var buffer = NotepadStorageService.getSessionBuffer(loadedTabId);
        if (buffer === undefined || buffer.content === textArea.text)
            return;
        if (textArea.text === lastSavedContent) {
            applyingShared = true;
            lastSavedContent = buffer.baseline;
            textArea.text = buffer.content;
            applyingShared = false;
            syncContentToPlugin();
        }
    }
}
