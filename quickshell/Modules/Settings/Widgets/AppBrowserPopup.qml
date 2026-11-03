import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

DFloatingWindow {
    id: root

    property string searchQuery: ""
    property var filteredApps: []
    property int selectedIndex: -1
    property bool keyboardNavigationActive: false
    property var appsModel: []
    property var parentModal: null
    parentWindow: parentModal

    signal appSelected(string appId)

    objectName: "appBrowserPopup"
    title: I18n.tr("Select Application")
    minimumSize: Qt.size(400, 350)
    implicitWidth: SettingsMetrics.windowMinWidth
    implicitHeight: SettingsMetrics.windowMinWidth + Theme.spacingXL * 2
    visible: false

    onClosed: hide()

    FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                root.hide();
                event.accepted = true;
                return;
            case Qt.Key_Down:
                root.selectNext();
                event.accepted = true;
                return;
            case Qt.Key_Up:
                root.selectPrevious();
                event.accepted = true;
                return;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (root.keyboardNavigationActive) {
                    root.selectApp();
                } else if (root.filteredApps.length > 0) {
                    root.selectAppByIndex(0);
                }
                event.accepted = true;
                return;
            }
        }

        Column {
            anchors.fill: parent
            spacing: 0

            DWindowHeader {
                id: titleBar
                width: parent.width
                controls: windowControls
                title: I18n.tr("Select Application")
                onCloseRequested: root.hide()
            }

            Item {
                width: parent.width
                height: parent.height - titleBar.height

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.windowInset
                    anchors.topMargin: 0
                    spacing: Theme.spacingM

                    DSearchField {
                        id: searchField
                        width: parent.width
                        textColor: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        placeholderText: I18n.tr("Search applications...")
                        text: root.searchQuery
                        onTextEdited: {
                            root.searchQuery = text;
                            root.updateFilteredApps();
                        }
                    }

                    DListView {
                        id: appList
                        width: parent.width
                        height: parent.height - searchField.height - Theme.spacingM
                        spacing: Theme.spacingS
                        // Start with no model. It is (re)bound in show() so that each open
                        // gets a fresh QQmlDelegateModel, avoiding a crash where a stale
                        // incubation queue from a previous open races with a background
                        // refreshApplications() replacing the underlying DesktopEntries
                        // QObjectModel (SIGSEGV in QQmlIncubatorPrivate::incubate via
                        // libQt6QmlModels). See hide()/onVisibleChanged() for the teardown.
                        model: null
                        clip: true

                        delegate: Rectangle {
                            width: appList.width
                            height: SettingsMetrics.rowMinHeight + Theme.spacingXS
                            radius: Theme.cornerRadius
                            required property int index
                            required property var modelData

                            readonly property bool isSelected: root.keyboardNavigationActive && index === root.selectedIndex

                            color: isSelected ? Theme.selectedContainer : appArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.08) : Theme.floatingWindowNestedSurface
                            border.color: isSelected ? Theme.primary : Theme.outlineMedium
                            border.width: isSelected ? Theme.outlineWidthFocused : Theme.layerOutlineWidth

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                Image {
                                    width: Theme.iconSizeMedium + Theme.spacingS
                                    height: Theme.iconSizeMedium + Theme.spacingS
                                    source: Paths.resolveIconUrl(modelData.icon || "application-x-executable")
                                    sourceSize.width: 28
                                    sourceSize.height: 28
                                    fillMode: Image.PreserveAspectFit
                                    anchors.verticalCenter: parent.verticalCenter
                                    onStatusChanged: {
                                        if (status === Image.Error)
                                            source = "image://icon/application-x-executable";
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXXS
                                    width: parent.width - 28 - Theme.spacingM * 3 - 24

                                    StyledText {
                                        text: modelData.name || modelData.id || ""
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Theme.fontWeightMedium
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }

                                    StyledText {
                                        text: modelData.comment || modelData.genericName || ""
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.outline
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }

                                DIcon {
                                    name: "add"
                                    size: Theme.iconSizeMedium
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: appArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const appId = modelData.id || modelData.execString || "";
                                    root.appSelected(appId);
                                    root.hide();
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.expressiveDurations.expressiveFastEffects
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                                }
                            }
                        }
                    }
                }
            }
        }

        FloatingWindowControls {
            id: windowControls
            targetWindow: root
        }
    }

    function updateFilteredApps() {
        const allApps = root.appsModel || [];
        var filtered = [];
        if (!searchQuery || searchQuery.length === 0) {
            filtered = allApps.slice();
        } else {
            var query = searchQuery.toLowerCase();
            for (var i = 0; i < allApps.length; i++) {
                var app = allApps[i];
                var name = (app.name || "").toLowerCase();
                var id = (app.id || "").toLowerCase();
                var comment = (app.comment || app.genericName || "").toLowerCase();
                if (name.indexOf(query) !== -1 || id.indexOf(query) !== -1 || comment.indexOf(query) !== -1)
                    filtered.push(app);
            }
        }
        filteredApps = filtered;
        selectedIndex = -1;
        keyboardNavigationActive = false;
    }

    function selectNext() {
        if (filteredApps.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = Math.min(selectedIndex + 1, filteredApps.length - 1);
    }

    function selectPrevious() {
        if (filteredApps.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = Math.max(selectedIndex - 1, -1);
        if (selectedIndex === -1)
            keyboardNavigationActive = false;
    }

    function selectApp() {
        if (selectedIndex < 0 || selectedIndex >= filteredApps.length)
            return;
        selectAppByIndex(selectedIndex);
    }

    function selectAppByIndex(idx) {
        const app = filteredApps[idx];
        if (!app)
            return;
        root.appSelected(app.id || app.execString || "");
        hide();
    }

    function show() {
        updateFilteredApps();
        // Rebind the model reactively (search relies on filteredApps changes flowing
        // through), and do it after populating so the ListView starts incubating from
        // a fully-formed array rather than [].
        appList.model = Qt.binding(() => root.filteredApps);
        visible = true;
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    function hide() {
        // Drop the model before clearing visible, so the ListView releases its
        // QQmlDelegateModel (and any in-flight incubators) synchronously on this
        // frame. This is the crux of the fix: a later show() will allocate a fresh
        // DelegateModel instead of reusing one whose incubation queue may hold
        // references invalidated by a concurrent refreshApplications().
        appList.model = null;
        visible = false;
        searchQuery = "";
        filteredApps = [];
        selectedIndex = -1;
        keyboardNavigationActive = false;
    }

    onVisibleChanged: {
        if (!visible) {
            // Guard against visibility being cleared without going through hide()
            // (e.g. window manager close, FloatingWindow.onClosed -> hide()).
            appList.model = null;
            searchQuery = "";
            filteredApps = [];
            selectedIndex = -1;
            keyboardNavigationActive = false;
        }
    }
}
