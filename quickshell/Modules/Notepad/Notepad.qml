pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import "../../Common/Format.js" as Format

Item {
    id: root

    property bool fileDialogOpen: false
    property string currentFileName: ""
    property url currentFileUrl
    property bool confirmationDialogOpen: false
    property string pendingAction: ""
    property url pendingFileUrl
    property string lastSavedFileContent: ""
    property var currentTab: NotepadStorageService.tabs.length > NotepadStorageService.currentTabIndex ? NotepadStorageService.tabs[NotepadStorageService.currentTabIndex] : null
    property bool showSettingsMenu: false
    property string pendingSaveContent: ""
    readonly property bool conflictBannerVisible: currentTab !== null && NotepadStorageService.conflictTabId === currentTab.id
    readonly property bool anyModalOpen: fileDialogOpen || confirmationDialogOpen
    property var slideout: null
    property bool inPopout: false
    property bool surfaceVisible: slideout ? slideout.isVisible : true

    signal hideRequested
    signal popoutRequested
    signal dockRequested
    signal previewRequested(string content)

    function externalSync() {
        textEditor.syncFromDisk();
    }

    function flushAutoSave() {
        textEditor.autoSaveToSession();
    }

    Ref {
        service: NotepadStorageService
    }

    // In connected frame mode the slideout sits on the Overlay layer
    onFileDialogOpenChanged: {
        if (slideout)
            slideout.suppressOverlayLayer = fileDialogOpen;
    }

    Binding {
        target: root.slideout
        property: "hoverDismissSuspended"
        value: root.anyModalOpen
        when: root.slideout !== null
        restoreMode: Binding.RestoreBindingOrValue
    }

    Connections {
        target: slideout
        enabled: slideout !== null
        function onAboutToHide() {
            textEditor.autoSaveToSession();
        }
        function onRevealed() {
            textEditor.syncFromDisk();
        }
    }

    function showConflictBanner(diskContent) {
        if (!currentTab)
            return;
        NotepadStorageService.flagConflict(currentTab.id, diskContent);
    }

    function resolveConflictKeepEdits() {
        if (!root.conflictBannerVisible)
            return;
        NotepadStorageService.clearConflict();
        if (currentTab && currentTab.filePath && !currentTab.isTemporary) {
            root.saveToFile("file://" + currentTab.filePath);
        }
    }

    function resolveConflictReload() {
        if (!root.conflictBannerVisible)
            return;
        const diskContent = NotepadStorageService.conflictDiskContent;
        NotepadStorageService.clearConflict();
        textEditor.reloadFromDisk(diskContent);
    }

    function dismissConflictBanner() {
        if (root.conflictBannerVisible)
            NotepadStorageService.clearConflict();
    }

    function hasUnsavedChanges() {
        return textEditor.hasUnsavedChanges();
    }

    function createNewTab() {
        textEditor.commitLiveBuffer();
        NotepadStorageService.createNewTab();
        textEditor.applyingShared = true;
        textEditor.text = "";
        textEditor.lastSavedContent = "";
        textEditor.loadedTabId = -1;
        textEditor.contentLoaded = true;
        textEditor.applyingShared = false;
        textEditor.textArea.forceActiveFocus();
    }

    function closeTab(tabIndex) {
        if (tabIndex === NotepadStorageService.currentTabIndex && hasUnsavedChanges()) {
            root.pendingAction = "close_tab_" + tabIndex;
            root.confirmationDialogOpen = true;
            confirmationDialogLoader.active = true;
            if (confirmationDialogLoader.item)
                confirmationDialogLoader.item.open();
        } else {
            performCloseTab(tabIndex);
        }
    }

    function performCloseTab(tabIndex) {
        NotepadStorageService.closeTab(tabIndex);
        Qt.callLater(() => {
            textEditor.loadCurrentTabContent();
        });
    }

    function switchToTab(tabIndex) {
        if (tabIndex < 0 || tabIndex >= NotepadStorageService.tabs.length)
            return;
        if (textEditor.contentLoaded) {
            textEditor.autoSaveToSession();
        }

        NotepadStorageService.switchToTab(tabIndex);
        Qt.callLater(() => {
            if (currentTab) {
                root.currentFileName = currentTab.fileName || "";
                root.currentFileUrl = currentTab.fileUrl || "";
            }
        });
    }

    function saveToFile(fileUrl) {
        if (!currentTab)
            return;
        var content = textEditor.text;
        var filePath = fileUrl.toString().replace(/^file:\/\//, '');

        textEditor.externalWatchPaused = true;
        saveFileView.path = "";
        pendingSaveContent = content;
        saveFileView.path = filePath;

        saveFileView.setText(content);
    }

    function saveExternalWithFreshnessCheck() {
        if (!currentTab || currentTab.isTemporary || !currentTab.filePath)
            return;
        const filePath = currentTab.filePath;
        loadFileView.path = "";
        loadFileView.path = filePath;

        if (!loadFileView.waitForJob()) {
            saveToFile("file://" + filePath);
            return;
        }
        Qt.callLater(() => {
            if (!currentTab || currentTab.isTemporary || currentTab.filePath !== filePath)
                return;
            const diskContent = loadFileView.text();
            if (diskContent !== undefined && diskContent !== null && diskContent !== textEditor.text && diskContent !== textEditor.lastSavedContent) {
                root.showConflictBanner(diskContent);
                return;
            }
            saveToFile("file://" + filePath);
        });
    }

    function autoSaveExternal() {
        if (!SettingsData.notepadAutoSave)
            return;
        if (!currentTab || currentTab.isTemporary || !currentTab.filePath)
            return;
        if (!textEditor.hasUnsavedChanges())
            return;
        const filePath = currentTab.filePath;
        loadFileView.path = "";
        loadFileView.path = filePath;
        if (!loadFileView.waitForJob())
            return;
        Qt.callLater(() => {
            if (!currentTab || currentTab.isTemporary || currentTab.filePath !== filePath)
                return;
            const diskContent = loadFileView.text();
            if (diskContent === undefined || diskContent === null)
                return;
            if (diskContent !== textEditor.lastSavedContent)
                return;
            saveToFile("file://" + filePath);
        });
    }

    function openExternalFile(path) {
        if (!path)
            return;

        for (var i = 0; i < NotepadStorageService.tabs.length; i++) {
            var tab = NotepadStorageService.tabs[i];
            if (tab && !tab.isTemporary && tab.filePath === path) {
                textEditor.autoSaveToSession();
                switchToTab(i);
                return;
            }
        }

        textEditor.autoSaveToSession();
        NotepadStorageService.createTabForFile(path);
        root.currentFileName = path.split('/').pop();
        root.currentFileUrl = "file://" + path;
    }

    function loadFromFile(fileUrl) {
        if (hasUnsavedChanges()) {
            root.pendingFileUrl = fileUrl;
            root.pendingAction = "load_file";
            root.confirmationDialogOpen = true;
            confirmationDialogLoader.active = true;
            if (confirmationDialogLoader.item)
                confirmationDialogLoader.item.open();
        } else {
            performLoadFromFile(fileUrl);
        }
    }

    function confirmLargeFile(path, size, onOpen, onCancel) {
        largeFileConfirmLoader.active = true;
        const confirm = largeFileConfirmLoader.item;
        if (!confirm)
            return;
        root.confirmationDialogOpen = true;
        confirm.showWithOptions({
            "title": I18n.tr("Open large file?", "notepad prompt before loading a file over the size limit"),
            "message": I18n.tr("%1 is %2 and may use a lot of memory.", "notepad large file prompt, file name then size").arg(path.split('/').pop()).arg(Format.formatBytes(size)),
            "confirmText": I18n.tr("Open"),
            "onConfirm": () => {
                root.confirmationDialogOpen = false;
                NotepadStorageService.approveLargeFile(path);
                onOpen();
            },
            "onCancel": () => {
                root.confirmationDialogOpen = false;
                onCancel();
            }
        });
    }

    function performLoadFromFile(fileUrl) {
        const filePath = fileUrl.toString().replace(/^file:\/\//, '');
        const fileName = filePath.split('/').pop();

        NotepadStorageService.readFileSize(filePath, size => {
            if (NotepadStorageService.needsLargeFileConfirm(filePath, size)) {
                root.confirmLargeFile(filePath, size, () => root.performLoadFromFile(fileUrl), () => {});
                return;
            }

            loadFileView.path = "";
            loadFileView.path = filePath;

            if (!loadFileView.waitForJob())
                return;
            Qt.callLater(() => {
                var content = loadFileView.text();
                if (currentTab && content !== undefined && content !== null) {
                    textEditor.text = content;
                    textEditor.lastSavedContent = content;
                    textEditor.contentLoaded = true;
                    root.lastSavedFileContent = content;

                    NotepadStorageService.updateTabMetadata(NotepadStorageService.currentTabIndex, {
                        title: fileName,
                        filePath: filePath,
                        isTemporary: false
                    });

                    root.currentFileName = fileName;
                    root.currentFileUrl = fileUrl;
                    textEditor.loadedTabId = currentTab.id;
                    NotepadStorageService.clearSessionBuffer(currentTab.id);
                    if (root.conflictBannerVisible)
                        NotepadStorageService.clearConflict();
                }
            });
        });
    }

    Item {
        id: conflictBanner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.conflictBannerVisible ? bannerRect.implicitHeight : 0
        visible: height > 0
        clip: true
        z: 5

        Behavior on height {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        StyledRect {
            id: bannerRect
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            implicitHeight: bannerLayout.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.warning, 0.12)
            border.color: Theme.withAlpha(Theme.warning, 0.5)
            border.width: 1

            ColumnLayout {
                id: bannerLayout
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM

                    DIcon {
                        Layout.alignment: Qt.AlignVCenter
                        name: "sync_problem"
                        size: Theme.iconSize - 2
                        color: Theme.warning
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: I18n.tr("File changed on disk")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    DActionButton {
                        Layout.alignment: Qt.AlignVCenter
                        iconName: "close"
                        Accessible.name: I18n.tr("Dismiss")
                        iconSize: Theme.iconSizeSmall
                        iconColor: Theme.surfaceText
                        buttonSize: 28
                        onClicked: root.dismissConflictBanner()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32

                    Row {
                        id: bannerActions
                        anchors.right: parent.right
                        spacing: Theme.spacingS

                        readonly property real available: parent.width

                        StyledRect {
                            width: Math.min(keepText.implicitWidth + Theme.spacingM * 2, Math.max(104, (bannerActions.available - bannerActions.spacing) / 2))
                            height: 32
                            radius: Theme.cornerRadius
                            color: "transparent"
                            border.color: Theme.outlineMedium
                            border.width: 1

                            StateLayer {
                                anchors.fill: parent
                                cornerRadius: parent.radius
                                stateColor: Theme.surfaceText
                                onClicked: root.resolveConflictKeepEdits()
                            }

                            StyledText {
                                id: keepText
                                anchors.centerIn: parent
                                width: parent.width - Theme.spacingM
                                text: I18n.tr("Keep My Edits")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }

                        StyledRect {
                            width: Math.min(reloadText.implicitWidth + Theme.spacingM * 2, Math.max(116, (bannerActions.available - bannerActions.spacing) / 2))
                            height: 32
                            radius: Theme.cornerRadius
                            color: Theme.primary

                            StateLayer {
                                anchors.fill: parent
                                cornerRadius: parent.radius
                                stateColor: Theme.background
                                onClicked: root.resolveConflictReload()
                            }

                            StyledText {
                                id: reloadText
                                anchors.centerIn: parent
                                width: parent.width - Theme.spacingM
                                text: I18n.tr("Reload From Disk")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.background
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    Column {
        anchors.top: conflictBanner.bottom
        anchors.topMargin: root.conflictBannerVisible ? Theme.spacingM : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Theme.spacingM

        NotepadTabs {
            id: tabBar
            width: parent.width
            contentLoaded: textEditor.contentLoaded

            onTabSwitched: tabIndex => {
                switchToTab(tabIndex);
            }

            onTabClosed: tabIndex => {
                closeTab(tabIndex);
            }

            onNewTabRequested: {
                createNewTab();
            }
        }

        NotepadTextEditor {
            id: textEditor
            width: parent.width
            height: parent.height - tabBar.height - Theme.spacingM * 2
            inPopout: root.inPopout
            surfaceVisible: root.surfaceVisible

            onSaveRequested: {
                if (currentTab && !currentTab.isTemporary && currentTab.filePath) {
                    root.saveExternalWithFreshnessCheck();
                } else {
                    root.fileDialogOpen = true;
                    saveBrowserLoader.active = true;
                    if (saveBrowserLoader.item)
                        saveBrowserLoader.item.open();
                }
            }

            onOpenRequested: {
                textEditor.autoSaveToSession();
                if (textEditor.text.length > 0) {
                    createNewTab();
                }

                root.fileDialogOpen = true;
                loadBrowserLoader.active = true;
                if (loadBrowserLoader.item)
                    loadBrowserLoader.item.open();
            }

            onNewRequested: {
                textEditor.autoSaveToSession();
                createNewTab();
            }

            onPreviewRequested: {
                textEditor.togglePreview();
            }

            onEscapePressed: {
                textEditor.autoSaveToSession();
                if (showSettingsMenu) {
                    showSettingsMenu = false;
                    return;
                }
                if (!root.inPopout) {
                    root.hideRequested();
                }
            }

            onSettingsRequested: {
                showSettingsMenu = !showSettingsMenu;
            }

            onPopoutRequested: root.popoutRequested()

            onDockRequested: root.dockRequested()

            onConflictDetected: diskContent => {
                root.showConflictBanner(diskContent);
            }

            onLargeFileConfirmRequested: (tab, size) => {
                if (!root.surfaceVisible)
                    return;
                root.confirmLargeFile(tab.filePath, size, () => textEditor.loadCurrentTabContent(), () => {
                    root.performCloseTab(NotepadStorageService.tabs.findIndex(t => t.id === tab.id));
                });
            }

            onAutoSaveRequested: root.autoSaveExternal()
        }
    }

    NotepadSettings {
        id: notepadSettings
        anchors.fill: parent
        isVisible: showSettingsMenu
        frameManagesGap: root.slideout?.frameOwnsConnectedChrome ?? false
        onSettingsRequested: showSettingsMenu = !showSettingsMenu
        onFindRequested: {
            showSettingsMenu = false;
            textEditor.showSearch();
        }
    }

    FileView {
        id: saveFileView
        blockWrites: true
        preload: false
        atomicWrites: true
        printErrors: true

        onSaved: {
            if (currentTab && saveFileView.path) {
                NotepadStorageService.updateTabMetadata(NotepadStorageService.currentTabIndex, {
                    hasUnsavedChanges: false,
                    lastSavedContent: pendingSaveContent
                });
                root.lastSavedFileContent = pendingSaveContent;
                textEditor.lastSavedContent = pendingSaveContent;
                textEditor.ignoreNextExternalChange = true;
                textEditor.commitLiveBuffer();
                if (root.conflictBannerVisible)
                    NotepadStorageService.clearConflict();
            }
            textEditor.externalWatchPaused = false;
            pendingSaveContent = "";
        }

        onSaveFailed: error => {
            textEditor.externalWatchPaused = false;
            pendingSaveContent = "";
        }
    }

    FileView {
        id: loadFileView
        blockLoading: true
        preload: true
        atomicWrites: true
        printErrors: true

        onLoadFailed: error => {}
    }

    LazyLoader {
        id: saveBrowserLoader
        active: false

        FileBrowserSurfaceModal {
            id: saveBrowser

            browserTitle: I18n.tr("Save Notepad File")
            bucket: "notepad_save"
            mode: "save"
            defaultName: {
                if (currentTab && currentTab.title && currentTab.title !== "Untitled") {
                    return currentTab.title;
                } else if (currentTab && !currentTab.isTemporary && currentTab.filePath) {
                    return currentTab.filePath.split('/').pop();
                } else {
                    return "note.txt";
                }
            }

            onAccepted: paths => {
                root.fileDialogOpen = false;
                const cleanPath = paths[0];
                const fileName = cleanPath.split('/').pop();
                const fileUrl = "file://" + cleanPath;

                root.currentFileName = fileName;
                root.currentFileUrl = fileUrl;
                textEditor.externalWatchPaused = true;

                if (currentTab) {
                    NotepadStorageService.saveTabAs(NotepadStorageService.currentTabIndex, cleanPath);
                }

                saveToFile(fileUrl);

                if (root.pendingAction === "new") {
                    Qt.callLater(() => {
                        createNewTab();
                    });
                } else if (root.pendingAction === "open") {
                    Qt.callLater(() => {
                        root.fileDialogOpen = true;
                        loadBrowserLoader.active = true;
                        if (loadBrowserLoader.item)
                            loadBrowserLoader.item.open();
                    });
                } else if (root.pendingAction.startsWith("close_tab_")) {
                    Qt.callLater(() => {
                        var tabIndex = parseInt(root.pendingAction.split("_")[2]);
                        performCloseTab(tabIndex);
                    });
                }
                root.pendingAction = "";
            }

            onDialogClosed: {
                root.fileDialogOpen = false;
            }
        }
    }

    LazyLoader {
        id: loadBrowserLoader
        active: false

        FileBrowserSurfaceModal {
            id: loadBrowser

            browserTitle: I18n.tr("Open Notepad File")
            bucket: "notepad_load"

            onAccepted: paths => {
                root.fileDialogOpen = false;
                const fileUrl = "file://" + paths[0];

                root.currentFileName = paths[0].split('/').pop();
                root.currentFileUrl = fileUrl;

                loadFromFile(fileUrl);
            }

            onDialogClosed: {
                root.fileDialogOpen = false;
            }
        }
    }

    LazyLoader {
        id: largeFileConfirmLoader
        active: false

        ConfirmModal {
            useOverlayLayer: true
        }
    }

    LazyLoader {
        id: confirmationDialogLoader
        active: false

        DModal {
            id: confirmationDialog

            modalWidth: 400
            modalHeight: contentLoader.item ? contentLoader.item.implicitHeight + Theme.spacingM * 2 : 180
            shouldBeVisible: false
            allowStacking: true
            useOverlayLayer: true

            onBackgroundClicked: {
                close();
                root.confirmationDialogOpen = false;
            }

            content: Component {
                FocusScope {
                    anchors.fill: parent
                    focus: true
                    implicitHeight: contentColumn.implicitHeight

                    Keys.onEscapePressed: event => {
                        confirmationDialog.close();
                        root.confirmationDialogOpen = false;
                        event.accepted = true;
                    }

                    Column {
                        id: contentColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        StyledText {
                            text: I18n.tr("Unsaved changes")
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                            font.weight: Theme.fontWeightMedium
                        }

                        StyledText {
                            text: I18n.tr("You have unsaved changes. Save before continuing?")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceTextMedium
                            width: parent.width
                            wrapMode: Text.Wrap
                        }

                        Item {
                            width: parent.width
                            height: 36

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingM

                                Rectangle {
                                    width: Math.max(80, discardText.contentWidth + Theme.spacingM * 2)
                                    height: 36
                                    radius: Theme.cornerRadius
                                    color: discardArea.containsMouse ? Theme.surfaceTextHover : Theme.withAlpha(Theme.surfaceTextHover, 0)
                                    border.color: Theme.surfaceVariantAlpha
                                    border.width: 1

                                    StyledText {
                                        id: discardText
                                        anchors.centerIn: parent
                                        text: I18n.tr("Don't Save")
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                        font.weight: Theme.fontWeightMedium
                                    }

                                    MouseArea {
                                        id: discardArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            confirmationDialog.close();
                                            root.confirmationDialogOpen = false;
                                            if (root.pendingAction === "new") {
                                                createNewTab();
                                            } else if (root.pendingAction === "open") {
                                                root.fileDialogOpen = true;
                                                loadBrowserLoader.active = true;
                                                if (loadBrowserLoader.item)
                                                    loadBrowserLoader.item.open();
                                            } else if (root.pendingAction === "load_file") {
                                                performLoadFromFile(root.pendingFileUrl);
                                            } else if (root.pendingAction.startsWith("close_tab_")) {
                                                var tabIndex = parseInt(root.pendingAction.split("_")[2]);
                                                performCloseTab(tabIndex);
                                            }
                                            root.pendingAction = "";
                                            root.pendingFileUrl = "";
                                        }
                                    }
                                }

                                Rectangle {
                                    width: Math.max(70, saveAsText.contentWidth + Theme.spacingM * 2)
                                    height: 36
                                    radius: Theme.cornerRadius
                                    color: saveAsArea.containsMouse ? Qt.darker(Theme.primary, 1.1) : Theme.primary

                                    StyledText {
                                        id: saveAsText
                                        anchors.centerIn: parent
                                        text: I18n.tr("Save")
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.background
                                        font.weight: Theme.fontWeightMedium
                                    }

                                    MouseArea {
                                        id: saveAsArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            confirmationDialog.close();
                                            root.confirmationDialogOpen = false;
                                            root.fileDialogOpen = true;
                                            saveBrowserLoader.active = true;
                                            if (saveBrowserLoader.item)
                                                saveBrowserLoader.item.open();
                                        }
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Theme.shortDuration
                                            easing.type: Theme.standardEasing
                                        }
                                    }
                                }
                            }
                        }
                    }

                    DActionButton {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        iconName: "close"
                        Accessible.name: I18n.tr("Close")
                        iconSize: Theme.iconSize - 4
                        iconColor: Theme.surfaceText
                        onClicked: {
                            confirmationDialog.close();
                            root.confirmationDialogOpen = false;
                        }
                    }
                }
            }
        }
    }
}
