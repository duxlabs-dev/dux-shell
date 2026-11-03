import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Details

DPopout {
    id: root

    layerNamespace: "dms:vpn"

    property bool wasVisible: false
    property var triggerScreen: null

    popupWidth: 380
    popupHeight: Math.min((screen ? screen.height : Screen.height) - 100, contentLoader.item ? contentLoader.item.implicitHeight : 320)
    triggerWidth: 70
    screen: triggerScreen
    shouldBeVisible: false

    onShouldBeVisibleChanged: {
        if (shouldBeVisible && !wasVisible) {
            DMSNetworkService.getState();
        }
        wasVisible = shouldBeVisible;
    }

    onBackgroundClicked: close()

    content: Component {
        Rectangle {
            id: content

            implicitHeight: contentColumn.height + PopoutMetrics.contentPadding * 2
            color: "transparent"
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }

            Column {
                id: contentColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: PopoutMetrics.contentPadding
                spacing: PopoutMetrics.contentGap

                Item {
                    id: actionsSlot
                    anchors.right: parent.right
                    width: childrenRect.width
                    height: childrenRect.height
                }

                VpnDetailContent {
                    id: vpnContent
                    width: parent.width
                    listHeight: CcMetrics.vpnPopoutListHeight
                    parentPopout: root

                    Component.onCompleted: headerActions.parent = actionsSlot
                }
            }
        }
    }
}
