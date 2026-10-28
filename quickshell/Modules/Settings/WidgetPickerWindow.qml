import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

DFloatingWindow {
    id: root

    property var widgets: []
    property string searchQuery: ""
    property var filteredWidgets: []
    property int selectedIndex: -1
    property bool keyboardNavigationActive: false
    property var parentModal: null
    property string headerTitle: title
    property string intro: ""
    property bool featuredFirst: false
    property bool showEmptyState: false
    property Component widgetDelegate: null
    parentWindow: parentModal

    signal widgetChosen(var widget)

    function widgetMatches(widget, query) {
        const label = (widget.name || widget.text || "").toLowerCase();
        const description = (widget.description || "").toLowerCase();
        const id = (widget.id || "").toLowerCase();
        return label.indexOf(query) !== -1 || description.indexOf(query) !== -1 || id.indexOf(query) !== -1;
    }

    function updateFilteredWidgets() {
        const source = widgets || [];
        const query = (searchQuery || "").toLowerCase();
        const filtered = query ? source.filter(widget => widgetMatches(widget, query)) : source.slice();
        if (featuredFirst)
            filtered.sort((a, b) => a.featured === b.featured ? 0 : (a.featured ? -1 : 1));
        filteredWidgets = filtered;
        selectedIndex = -1;
        keyboardNavigationActive = false;
    }

    onWidgetsChanged: updateFilteredWidgets()

    function selectableIndex(from, step) {
        for (let i = from; i >= 0 && i < filteredWidgets.length; i += step) {
            if (!filteredWidgets[i].disabled)
                return i;
        }
        return -1;
    }

    function selectNext() {
        const next = selectableIndex(selectedIndex + 1, 1);
        if (next < 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = next;
    }

    function selectPrevious() {
        if (filteredWidgets.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = selectableIndex(selectedIndex - 1, -1);
        if (selectedIndex === -1)
            keyboardNavigationActive = false;
    }

    function selectWidget() {
        if (selectedIndex < 0 || selectedIndex >= filteredWidgets.length)
            return;
        widgetChosen(filteredWidgets[selectedIndex]);
    }

    function restoreParentFocus() {
        if (!parentModal)
            return;
        parentModal.shouldHaveFocus = Qt.binding(() => parentModal.shouldBeVisible);
        Qt.callLater(() => {
            if (parentModal && parentModal.modalFocusScope)
                parentModal.modalFocusScope.forceActiveFocus();
        });
    }

    function show() {
        updateFilteredWidgets();
        if (parentModal)
            parentModal.shouldHaveFocus = false;
        visible = true;
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    function hide() {
        visible = false;
        restoreParentFocus();
    }

    minimumSize: Qt.size(400, 350)
    implicitWidth: 500
    implicitHeight: 550
    visible: false

    onClosed: hide()

    onVisibleChanged: {
        if (visible) {
            updateFilteredWidgets();
            Qt.callLater(() => searchField.forceActiveFocus());
            return;
        }
        searchQuery = "";
        filteredWidgets = [];
        selectedIndex = -1;
        keyboardNavigationActive = false;
        restoreParentFocus();
    }

    FocusScope {
        id: widgetKeyHandler

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
                if (root.keyboardNavigationActive)
                    root.selectWidget();
                else if (root.selectableIndex(0, 1) >= 0)
                    root.widgetChosen(root.filteredWidgets[root.selectableIndex(0, 1)]);
                event.accepted = true;
                return;
            }
            if (!(event.modifiers & Qt.ControlModifier))
                return;
            switch (event.key) {
            case Qt.Key_N:
            case Qt.Key_J:
                root.selectNext();
                event.accepted = true;
                return;
            case Qt.Key_P:
            case Qt.Key_K:
                root.selectPrevious();
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
                title: root.headerTitle
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

                    StyledText {
                        visible: root.intro !== ""
                        text: root.intro
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.outline
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }

                    DSearchField {
                        id: searchField
                        width: parent.width
                        textColor: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        placeholderText: I18n.tr("Search widgets...")
                        text: root.searchQuery
                        focus: true
                        ignoreLeftRightKeys: true
                        keyForwardTargets: [widgetKeyHandler]
                        onTextEdited: {
                            root.searchQuery = text;
                            root.updateFilteredWidgets();
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.hide();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up || ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && text.length === 0))
                                event.accepted = false;
                        }
                    }

                    DListView {
                        id: widgetList

                        width: parent.width
                        height: parent.height - y
                        spacing: Theme.spacingS
                        model: root.filteredWidgets
                        clip: true
                        delegate: root.widgetDelegate
                        footer: root.showEmptyState ? emptyState : null
                    }
                }
            }
        }
    }

    Component {
        id: emptyState

        Item {
            width: widgetList.width
            height: emptyText.visible ? 60 : 0

            StyledText {
                id: emptyText
                visible: root.filteredWidgets.length === 0
                text: root.searchQuery.length > 0 ? I18n.tr("No widgets match your search") : I18n.tr("No widgets available")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                anchors.centerIn: parent
            }
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: root
    }
}
