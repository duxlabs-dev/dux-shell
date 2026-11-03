import QtQuick
import qs.Common
import qs.Modals.DLauncherV2
import qs.Widgets

DPopout {
    id: appDrawerPopout

    layerNamespace: "dms:app-launcher"

    property string _pendingMode: ""
    property string _pendingQuery: ""

    function show() {
        open();
    }

    function openWithMode(mode) {
        _pendingMode = mode || "";
        open();
    }

    function toggleWithMode(mode) {
        if (shouldBeVisible) {
            close();
            return;
        }
        openWithMode(mode);
    }

    function openWithQuery(query) {
        _pendingQuery = query || "";
        open();
    }

    function toggleWithQuery(query) {
        if (shouldBeVisible) {
            close();
            return;
        }
        openWithQuery(query);
    }

    popupWidth: 560
    popupHeight: 640
    triggerWidth: 40
    positioning: ""
    contentHandlesKeys: contentLoader.item?.launcherContent?.editMode ?? false

    onBackgroundClicked: {
        if (contentLoader.item?.launcherContent?.editMode) {
            contentLoader.item.launcherContent.closeEditMode();
            return;
        }
        close();
    }

    onOpened: {
        var lc = contentLoader.item?.launcherContent;
        if (!lc)
            return;

        const query = _pendingQuery;
        const mode = _pendingMode || SessionData.appDrawerLastMode || "apps";
        _pendingMode = "";
        _pendingQuery = "";

        if (lc.searchField) {
            lc.searchField.text = query;
            lc.searchField.forceActiveFocus();
        }
        if (lc.controller) {
            lc.controller.explicitQuerySession = !!query;
            lc.controller.searchMode = mode;
            lc.controller.pluginFilter = "";
            lc.controller.searchQuery = "";
            if (query) {
                lc.controller.setSearchQuery(query);
            } else {
                lc.controller.performSearch();
            }
        }
        lc.resetScroll?.();
        lc.actionPanel?.hide();
    }

    Connections {
        target: contentLoader.item?.launcherContent?.controller ?? null
        function onModeChanged(mode) {
            if (contentLoader.item.launcherContent.controller.autoSwitchedToFiles)
                return;
            SessionData.setAppDrawerLastMode(mode);
        }
    }

    content: Component {
        Rectangle {
            id: contentContainer

            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            property alias launcherContent: launcherContent

            color: "transparent"

            QtObject {
                id: modalAdapter
                property bool spotlightOpen: appDrawerPopout.shouldBeVisible
                property bool isClosing: appDrawerPopout.isClosing
                readonly property var effectiveScreen: appDrawerPopout.screen
                readonly property real alignedX: appDrawerPopout.renderedAlignedX
                readonly property real alignedY: appDrawerPopout.renderedAlignedY

                function hide() {
                    appDrawerPopout.close();
                }
            }

            FocusScope {
                anchors.fill: parent
                focus: true

                LauncherContent {
                    id: launcherContent
                    anchors.fill: parent
                    parentModal: modalAdapter
                    viewModeContext: "appDrawer"
                    transientSurfaceTracker: appDrawerPopout.transientSurfaceTracker
                }

                Keys.onEscapePressed: event => {
                    if (launcherContent.editMode) {
                        launcherContent.closeEditMode();
                        event.accepted = true;
                        return;
                    }
                    appDrawerPopout.close();
                    event.accepted = true;
                }
            }
        }
    }
}
