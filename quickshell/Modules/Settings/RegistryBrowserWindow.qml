import QtQuick
import qs.Common
import qs.Modals.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

DFloatingWindow {
    id: root

    property var parentModal: null
    parentWindow: parentModal
    property string searchQuery: ""
    property int selectedIndex: -1
    property bool keyboardNavigationActive: false
    property bool isLoading: false
    property bool showLoadingSpinner: true
    property bool pendingInstallHandled: false
    property string headerTitle: title
    property string searchPlaceholder: ""
    property alias aboveSearch: aboveSearchSlot.data
    property alias belowSearch: belowSearchSlot.data
    property alias listContent: listSlot.data
    property alias overlay: overlaySlot.data
    property bool overlayActive: false
    readonly property alias installConfirm: urlInstallConfirm
    readonly property alias listArea: listSlot

    function refresh() {
    }

    function resetContent() {
    }

    function applySearch() {
    }

    function selectNext() {
    }

    function selectPrevious() {
    }

    function selectStep(delta) {
    }

    function activateSelected() {
        return false;
    }

    function handleEscape() {
        hide();
    }

    function pendingInstallId() {
        return "";
    }

    function checkPendingInstall() {
    }

    function focusSearch() {
        Qt.callLater(() => browserSearchField.forceActiveFocus());
    }

    function restoreParentFocus() {
        if (!parentModal)
            return;
        parentModal.shouldHaveFocus = Qt.binding(() => parentModal.shouldBeVisible);
        Qt.callLater(() => {
            if (parentModal.modalFocusScope)
                parentModal.modalFocusScope.forceActiveFocus();
        });
    }

    function show() {
        if (parentModal)
            parentModal.shouldHaveFocus = false;
        const wasVisible = visible;
        visible = true;
        if (wasVisible && pendingInstallId() !== "") {
            pendingInstallHandled = false;
            checkPendingInstall();
        }
        focusSearch();
    }

    function hide() {
        visible = false;
        restoreParentFocus();
    }

    minimumSize: Qt.size(SettingsMetrics.windowMinWidth, SettingsMetrics.windowMinHeight)
    implicitWidth: SettingsMetrics.windowWidth
    implicitHeight: SettingsMetrics.windowHeight
    visible: false

    onClosed: hide()

    onVisibleChanged: {
        if (visible) {
            pendingInstallHandled = false;
            refresh();
            Qt.callLater(() => {
                browserSearchField.forceActiveFocus();
                checkPendingInstall();
            });
            return;
        }
        searchQuery = "";
        selectedIndex = -1;
        keyboardNavigationActive = false;
        isLoading = false;
        resetContent();
    }

    ConfirmDialogOverlay {
        id: urlInstallConfirm

        onDialogClosed: root.focusSearch()
    }

    FocusScope {
        id: browserKeyHandler

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                root.handleEscape();
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
            case Qt.Key_Left:
                if (!root.keyboardNavigationActive)
                    return;
                root.selectStep(I18n.isRtl ? 1 : -1);
                event.accepted = true;
                return;
            case Qt.Key_Right:
                if (!root.keyboardNavigationActive)
                    return;
                root.selectStep(I18n.isRtl ? -1 : 1);
                event.accepted = true;
                return;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (!root.activateSelected())
                    return;
                event.accepted = true;
                return;
            }
        }

        DWindowHeader {
            id: headerArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            controls: windowControls
            title: root.headerTitle
            onCloseRequested: root.hide()

            DRefreshButton {
                buttonSize: Theme.buttonHeightXXS
                iconSize: Theme.iconSizeSmall
                iconColor: Theme.surfaceText
                busy: root.isLoading
                onClicked: root.refresh()
            }
        }

        Item {
            id: browserContent
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerArea.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.windowInset
            anchors.rightMargin: Theme.windowInset
            anchors.bottomMargin: Theme.windowInset

            Item {
                id: browserBody
                anchors.fill: parent

                Column {
                    id: aboveSearchSlot
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Theme.spacingS
                }

                DSearchField {
                    id: browserSearchField
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: aboveSearchSlot.bottom
                    anchors.topMargin: aboveSearchSlot.height > 0 ? Theme.spacingM : 0
                    textColor: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    placeholderText: root.searchPlaceholder
                    text: root.searchQuery
                    focus: true
                    ignoreLeftRightKeys: true
                    keyForwardTargets: [browserKeyHandler]
                    onTextEdited: {
                        root.searchQuery = text;
                        root.applySearch();
                    }
                }

                Column {
                    id: belowSearchSlot
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: browserSearchField.bottom
                    anchors.topMargin: height > 0 ? Theme.spacingM : 0
                    spacing: Theme.spacingS
                }

                Item {
                    id: listSlot
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: belowSearchSlot.bottom
                    anchors.topMargin: Theme.spacingM
                    anchors.bottom: parent.bottom

                    Item {
                        anchors.fill: parent
                        visible: root.isLoading && root.showLoadingSpinner

                        DSpinner {
                            anchors.centerIn: parent
                            running: root.isLoading && root.showLoadingSpinner
                        }
                    }
                }
            }
        }

        Item {
            id: overlayLayer
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true
            anchors.fill: parent
            opacity: root.overlayActive ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.expressiveDurations.expressiveEffects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.backdropColor
                opacity: Theme.scrimAlpha
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.handleEscape()
                onWheel: wheel => wheel.accepted = true
            }

            Item {
                id: overlaySlot
                anchors.fill: parent
            }
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: root
    }
}
