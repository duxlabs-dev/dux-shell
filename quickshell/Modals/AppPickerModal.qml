import QtQuick
import Quickshell
import qs.Common
import qs.Modals.Common
import qs.Modals.DLauncherV2.Components
import qs.DCommon.Widgets
import qs.Services

DModal {
    id: root
    readonly property var log: Log.scoped("AppPickerModal")

    property string title: I18n.tr("Select Application")
    property string targetData: ""
    property string editableTargetData: ""
    property string targetDataLabel: ""
    property string searchQuery: ""
    property int selectedIndex: 0
    property int gridColumns: SettingsData.appLauncherGridColumns
    property bool keyboardNavigationActive: false
    property string viewMode: "grid"
    property var categoryFilter: []
    property var usageHistoryKey: ""
    property bool showTargetData: true
    property string mimeType: ""
    property var rememberMimeTypes: []
    property bool rememberChoice: false
    property bool targetCopied: false
    property var mimeMatchedAppIds: []
    property var mimeMatchedRawIds: []

    signal applicationSelected(var app, string targetData)

    function _normAppId(id) {
        if (!id)
            return "";
        return id.replace(/\.desktop$/, "").toLowerCase();
    }

    shouldBeVisible: false
    allowStacking: true
    modalWidth: 520
    modalHeight: 500

    onBackgroundClicked: close()

    onDialogClosed: {
        searchQuery = "";
        selectedIndex = 0;
        keyboardNavigationActive = false;
    }

    onOpened: {
        searchQuery = "";
        editableTargetData = targetData;
        targetCopied = false;
        rememberChoice = false;
        fetchMimeMatches();
        updateApplicationList();
        selectedIndex = 0;
        Qt.callLater(() => {
            if (contentLoader.item && contentLoader.item.searchField) {
                contentLoader.item.searchField.text = "";
                contentLoader.item.searchField.forceActiveFocus();
            }
        });
    }

    function fetchMimeMatches() {
        mimeMatchedAppIds = [];
        mimeMatchedRawIds = [];
        const queriedMime = mimeType;
        if (queriedMime.length === 0)
            return;
        DMSService.sendRequest("mime.appsForMime", {
            "mimeType": queriedMime
        }, response => {
            if (queriedMime !== root.mimeType)
                return;
            if (response.error) {
                log.warn("mime.appsForMime failed:", response.error);
                return;
            }
            const ids = (response.result && response.result.desktopIds) || [];
            mimeMatchedRawIds = ids;
            mimeMatchedAppIds = ids.map(_normAppId);
            updateApplicationList();
        });
    }

    function _appMatchesMime(app, mime) {
        const list = app && (app.mimeTypes || app.mimeType);
        return !!list && !!list.includes && list.includes(mime);
    }

    function updateApplicationList() {
        applicationsModel.clear();
        const apps = AppSearchService.applications;
        const usageHistory = usageHistoryKey && CacheData[usageHistoryKey] ? CacheData[usageHistoryKey] : {};
        const hasCategoryFilter = categoryFilter.length > 0;
        const hasMime = mimeType.length > 0;
        const hasMimeMatches = mimeMatchedAppIds.length > 0;
        const lowerQuery = searchQuery.toLowerCase();
        let filteredApps = [];
        const listedIds = new Set();

        for (const app of apps) {
            if (!app)
                continue;
            const appId = _normAppId(app.id || app.execString || app.exec || "");
            listedIds.add(appId);
            const mimeIdMatch = hasMimeMatches && mimeMatchedAppIds.includes(appId);
            const mimeFieldMatch = hasMime && _appMatchesMime(app, mimeType);
            const mimeMatch = mimeIdMatch || mimeFieldMatch;

            let categoryMatch = false;
            if (hasCategoryFilter && app.categories) {
                try {
                    for (const cat of app.categories) {
                        if (categoryFilter.includes(cat)) {
                            categoryMatch = true;
                            break;
                        }
                    }
                } catch (e) {
                    log.warn("AppPicker: Error iterating categories for", app.name, ":", e);
                    continue;
                }
            }

            const include = (!hasCategoryFilter && !hasMime) || mimeMatch || categoryMatch;
            if (!include)
                continue;

            const name = app.name || "";
            if (searchQuery !== "" && !name.toLowerCase().includes(lowerQuery))
                continue;

            filteredApps.push({
                name: name,
                icon: app.icon || "application-x-executable",
                exec: app.exec || app.execString || "",
                startupClass: app.startupWMClass || "",
                appData: app,
                mimeMatch: mimeMatch
            });
        }

        // NoDisplay handlers stay hidden like in the launcher, except the shell's own (notepad)
        for (const rawId of mimeMatchedRawIds) {
            const normId = _normAppId(rawId);
            if (!normId.startsWith("dev.duxlabs.shell.") || listedIds.has(normId))
                continue;
            const desktopId = rawId.replace(/\.desktop$/, "");
            const entry = DesktopEntries.byId(desktopId) || DesktopEntries.heuristicLookup(desktopId);
            if (!entry)
                continue;
            const name = entry.name || "";
            if (searchQuery !== "" && !name.toLowerCase().includes(lowerQuery))
                continue;
            filteredApps.push({
                name: name,
                icon: entry.icon || "application-x-executable",
                exec: entry.execString || "",
                startupClass: entry.startupClass || "",
                appData: entry,
                mimeMatch: true
            });
        }

        filteredApps.sort((a, b) => {
            if (a.mimeMatch !== b.mimeMatch) {
                return a.mimeMatch ? -1 : 1;
            }
            const aId = a.appData.id || a.appData.execString || a.appData.exec || "";
            const bId = b.appData.id || b.appData.execString || b.appData.exec || "";
            const aUsage = usageHistory[aId] ? usageHistory[aId].count : 0;
            const bUsage = usageHistory[bId] ? usageHistory[bId].count : 0;
            if (aUsage !== bUsage) {
                return bUsage - aUsage;
            }
            return (a.name || "").localeCompare(b.name || "");
        });

        filteredApps.forEach(app => {
            applicationsModel.append({
                name: app.name,
                icon: app.icon,
                exec: app.exec,
                startupClass: app.startupClass,
                appId: app.appData.id || app.appData.execString || app.appData.exec || ""
            });
        });

        log.debug("AppPicker: Found " + filteredApps.length + " applications");
    }

    onSearchQueryChanged: updateApplicationList()

    function copyEditableTarget() {
        Quickshell.execDetached(["dms", "cl", "copy", editableTargetData]);
        ToastService.showInfo(I18n.tr("Copied to clipboard"));
        targetCopied = true;
        targetCopyConfirmationTimer.restart();
    }

    Timer {
        id: targetCopyConfirmationTimer
        interval: 1200
        repeat: false
        onTriggered: root.targetCopied = false
    }

    ListModel {
        id: applicationsModel
    }

    content: Component {
        FocusScope {
            id: appContent

            property alias searchField: searchField

            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: event => {
                root.close();
                event.accepted = true;
            }

            Keys.onPressed: event => {
                const hasCtrl = (event.modifiers & Qt.ControlModifier) !== 0;
                const hasShift = (event.modifiers & Qt.ShiftModifier) !== 0;
                const hasOtherModifier = (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) !== 0;
                if (hasCtrl && hasShift && !hasOtherModifier && event.key === Qt.Key_C) {
                    root.copyEditableTarget();
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Tab && root.mimeType.length > 0) {
                    root.rememberChoice = !root.rememberChoice;
                    event.accepted = true;
                    return;
                }

                if (applicationsModel.count === 0)
                    return;

                if (root.viewMode === "grid") {
                    if (event.key === Qt.Key_Left) {
                        root.keyboardNavigationActive = true;
                        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right) {
                        root.keyboardNavigationActive = true;
                        root.selectedIndex = Math.min(applicationsModel.count - 1, root.selectedIndex + 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.keyboardNavigationActive = true;
                        root.selectedIndex = Math.max(0, root.selectedIndex - root.gridColumns);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.keyboardNavigationActive = true;
                        root.selectedIndex = Math.min(applicationsModel.count - 1, root.selectedIndex + root.gridColumns);
                        event.accepted = true;
                    }
                } else {
                    if (event.key === Qt.Key_Up) {
                        root.keyboardNavigationActive = true;
                        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.keyboardNavigationActive = true;
                        root.selectedIndex = Math.min(applicationsModel.count - 1, root.selectedIndex + 1);
                        event.accepted = true;
                    }
                }

                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.selectedIndex >= 0 && root.selectedIndex < applicationsModel.count) {
                        const app = applicationsModel.get(root.selectedIndex);
                        launchApplication(app);
                    }
                    event.accepted = true;
                }
            }

            Column {
                width: parent.width - Theme.spacingS * 2
                height: parent.height - Theme.spacingS * 2
                x: Theme.spacingS
                y: Theme.spacingS
                spacing: Theme.spacingS

                Item {
                    width: parent.width
                    height: 40

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.title
                        font.pixelSize: Theme.fontSizeLarge + 4
                        color: Theme.surfaceText
                    }

                    Row {
                        spacing: Theme.spacingXS
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter

                        DActionButton {
                            buttonSize: 36
                            circular: false
                            iconName: "view_list"
                            Accessible.name: I18n.tr("List")
                            iconSize: 20
                            iconColor: root.viewMode === "list" ? Theme.primary : Theme.surfaceText
                            backgroundColor: root.viewMode === "list" ? Theme.primaryHover : Theme.withAlpha(Theme.primaryHover, 0)
                            onClicked: {
                                root.viewMode = "list";
                            }
                        }

                        DActionButton {
                            buttonSize: 36
                            circular: false
                            iconName: "grid_view"
                            Accessible.name: I18n.tr("Grid")
                            iconSize: 20
                            iconColor: root.viewMode === "grid" ? Theme.primary : Theme.surfaceText
                            backgroundColor: root.viewMode === "grid" ? Theme.primaryHover : Theme.withAlpha(Theme.primaryHover, 0)
                            onClicked: {
                                root.viewMode = "grid";
                            }
                        }
                    }
                }

                DSearchField {
                    id: searchField

                    width: parent.width - Theme.spacingS * 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: Theme.fontSizeLarge
                    enabled: root.shouldBeVisible
                    ignoreLeftRightKeys: root.viewMode !== "list"
                    ignoreTabKeys: true
                    keyForwardTargets: [appContent]

                    onTextEdited: {
                        root.searchQuery = text;
                    }

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                            return;
                        }

                        const isEnterKey = [Qt.Key_Return, Qt.Key_Enter].includes(event.key);
                        const hasText = text.length > 0;

                        if (isEnterKey && hasText) {
                            if (root.keyboardNavigationActive && applicationsModel.count > 0) {
                                const app = applicationsModel.get(root.selectedIndex);
                                launchApplication(app);
                            } else if (applicationsModel.count > 0) {
                                const app = applicationsModel.get(0);
                                launchApplication(app);
                            }
                            event.accepted = true;
                            return;
                        }

                        const navigationKeys = [Qt.Key_Down, Qt.Key_Up, Qt.Key_Left, Qt.Key_Right, Qt.Key_Tab, Qt.Key_Backtab];
                        const isNavigationKey = navigationKeys.includes(event.key);
                        const isEmptyEnter = isEnterKey && !hasText;

                        event.accepted = !(isNavigationKey || isEmptyEnter);
                    }

                    Connections {
                        function onShouldBeVisibleChanged() {
                            if (!root.shouldBeVisible) {
                                searchField.focus = false;
                            }
                        }

                        target: root
                    }
                }

                Rectangle {
                    width: parent.width
                    height: {
                        let usedHeight = 40 + Theme.spacingS;
                        usedHeight += 52 + Theme.spacingS;
                        if (root.showTargetData) {
                            usedHeight += 52 + Theme.spacingS;
                        }
                        if (root.mimeType && root.mimeType.length > 0) {
                            usedHeight += 36 + Theme.spacingS;
                        }
                        return parent.height - usedHeight;
                    }
                    radius: Theme.cornerRadius
                    color: "transparent"

                    DListView {
                        id: appList

                        property int itemHeight: 60
                        property int itemSpacing: Theme.spacingS

                        function ensureVisible(index) {
                            if (index < 0 || index >= count)
                                return;
                            const itemY = index * (itemHeight + itemSpacing);
                            const itemBottom = itemY + itemHeight;
                            if (itemY < contentY) {
                                contentY = itemY;
                            } else if (itemBottom > contentY + height) {
                                contentY = itemBottom - height;
                            }
                        }

                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        anchors.bottomMargin: Theme.spacingS

                        visible: root.viewMode === "list"
                        model: applicationsModel
                        currentIndex: root.selectedIndex
                        clip: true
                        spacing: itemSpacing

                        onCurrentIndexChanged: {
                            root.selectedIndex = currentIndex;
                            if (root.keyboardNavigationActive) {
                                ensureVisible(currentIndex);
                            }
                        }

                        delegate: LauncherRow {
                            required property var model
                            required property int index

                            width: appList.width
                            height: 60
                            iconSize: 40
                            showDescription: false
                            item: ({
                                    name: model.name,
                                    icon: model.icon,
                                    type: "app"
                                })
                            isSelected: index === root.selectedIndex
                            onClicked: launchApplication(model)
                            onPointerMoved: {
                                root.keyboardNavigationActive = false;
                                appList.currentIndex = index;
                            }
                        }
                    }

                    DGridView {
                        id: appGrid

                        function ensureVisible(index) {
                            if (index < 0 || index >= count)
                                return;
                            const itemY = Math.floor(index / root.gridColumns) * cellHeight;
                            const itemBottom = itemY + cellHeight;
                            if (itemY < contentY) {
                                contentY = itemY;
                            } else if (itemBottom > contentY + height) {
                                contentY = itemBottom - height;
                            }
                        }

                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        anchors.bottomMargin: Theme.spacingS

                        visible: root.viewMode === "grid"
                        model: applicationsModel
                        cellWidth: width / root.gridColumns
                        cellHeight: 120
                        clip: true
                        currentIndex: root.selectedIndex

                        onCurrentIndexChanged: {
                            root.selectedIndex = currentIndex;
                            if (root.keyboardNavigationActive) {
                                ensureVisible(currentIndex);
                            }
                        }

                        delegate: LauncherTile {
                            required property var model
                            required property int index

                            width: appGrid.cellWidth - LauncherMetrics.tileGap
                            height: appGrid.cellHeight - LauncherMetrics.tileGap
                            item: ({
                                    name: model.name,
                                    icon: model.icon,
                                    type: "app"
                                })
                            isSelected: index === root.selectedIndex
                            onClicked: launchApplication(model)
                            onPointerMoved: {
                                root.keyboardNavigationActive = false;
                                appGrid.currentIndex = index;
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 52
                    radius: Theme.cornerRadius
                    color: Theme.floatingWindowNestedSurface
                    border.color: Theme.outlineMedium
                    border.width: Theme.layerOutlineWidth
                    visible: root.showTargetData && root.targetData.length > 0

                    StyledText {
                        id: targetDataLabelText
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.targetDataLabel.length > 0 ? root.targetDataLabel + ":" : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                        visible: text.length > 0
                    }

                    DTextField {
                        id: targetDataField
                        anchors.left: targetDataLabelText.visible ? targetDataLabelText.right : parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.right: copyTargetButton.left
                        anchors.rightMargin: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                        height: 44
                        text: root.editableTargetData
                        keyForwardTargets: [appContent]
                        backgroundColor: Theme.floatingWindowFieldColor
                        onTextEdited: root.editableTargetData = text
                        Keys.onLeftPressed: event => {
                            if (cursorPosition === 0)
                                event.accepted = true;
                        }
                        Keys.onRightPressed: event => {
                            if (cursorPosition === text.length)
                                event.accepted = true;
                        }
                    }

                    DActionButton {
                        id: copyTargetButton
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: 36
                        iconName: root.targetCopied ? "check" : "content_copy"
                        iconSize: Theme.iconSize - 6
                        iconColor: root.targetCopied ? Theme.primary : Theme.surfaceText
                        tooltipText: I18n.tr("Copy target (%1)", "app picker copy target button tooltip").arg("Ctrl+Shift+C")
                        onClicked: root.copyEditableTarget()
                    }
                }

                Item {
                    width: parent.width
                    height: 36
                    visible: root.mimeType.length > 0

                    DToggle {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        checked: root.rememberChoice
                        text: I18n.tr("Always use this app for %1", "app picker checkbox, %1 is a mime type").arg(root.mimeType)
                        onToggled: checked => {
                            root.rememberChoice = checked;
                        }
                    }
                }
            }

            function launchApplication(app) {
                if (!app)
                    return;

                if (root.rememberChoice && app.appId) {
                    const targets = (root.rememberMimeTypes && root.rememberMimeTypes.length > 0) ? root.rememberMimeTypes : (root.mimeType ? [root.mimeType] : []);
                    if (targets.length > 0) {
                        DesktopService.setDefaultAppForMimes(targets, app.appId);
                    }
                }

                root.applicationSelected(app, root.editableTargetData);

                if (usageHistoryKey && app.appId) {
                    const usageHistory = CacheData[usageHistoryKey] || {};
                    const currentCount = usageHistory[app.appId] ? usageHistory[app.appId].count : 0;
                    usageHistory[app.appId] = {
                        count: currentCount + 1,
                        lastUsed: Date.now(),
                        name: app.name
                    };
                    CacheData.set(usageHistoryKey, usageHistory);
                }

                root.close();
            }
        }
    }
}
