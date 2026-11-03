import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets

DModal {
    id: root

    property bool wired: false
    property bool networkInfoModalVisible: false
    property string networkName: ""
    property var networkData: null
    readonly property string details: wired ? NetworkService.networkWiredInfoDetails : NetworkService.networkInfoDetails

    layerNamespace: wired ? "dms:network-info-wired" : "dms:network-info"
    keepPopoutsOpen: true

    function showNetworkInfo(name, data) {
        networkName = name;
        networkData = data;
        networkInfoModalVisible = true;
        open();
        if (wired) {
            NetworkService.fetchWiredNetworkInfo(data.uuid);
            return;
        }
        NetworkService.fetchNetworkInfo(name);
    }

    function hideDialog() {
        networkInfoModalVisible = false;
        close();
        networkName = "";
        networkData = null;
    }

    visible: networkInfoModalVisible
    modalWidth: 600
    modalHeight: 500
    enableShadow: true
    onBackgroundClicked: hideDialog()
    onVisibleChanged: {
        if (!visible) {
            networkName = "";
            networkData = null;
        }
    }

    content: Component {
        Item {
            anchors.fill: parent

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingL

                Row {
                    width: parent.width

                    Column {
                        width: parent.width - 40
                        spacing: Theme.spacingXS

                        StyledText {
                            text: I18n.tr("Network Information")
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                            font.weight: Theme.fontWeightMedium
                        }

                        StyledText {
                            text: I18n.tr("Details for \"%1\"", "network info dialog heading, %1 is the network name").arg(root.networkName)
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceTextMedium
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }

                    DActionButton {
                        iconName: "close"
                        Accessible.name: I18n.tr("Close")
                        iconSize: Theme.iconSize - 4
                        iconColor: Theme.surfaceText
                        onClicked: root.hideDialog()
                    }
                }

                Rectangle {
                    id: detailsRect

                    width: parent.width
                    height: parent.height - 140
                    radius: Theme.cornerRadius
                    color: Theme.floatingWindowNestedSurface
                    border.color: Theme.outlineMedium
                    border.width: Theme.layerOutlineWidth
                    clip: true

                    DFlickable {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        contentHeight: detailsText.contentHeight

                        StyledText {
                            id: detailsText

                            width: parent.width
                            text: root.details && root.details.replace(/\\n/g, '\n') || I18n.tr("No information available")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 40

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(70, closeText.contentWidth + Theme.spacingM * 2)
                        height: 36
                        radius: Theme.cornerRadius
                        color: closeArea.containsMouse ? Qt.darker(Theme.primary, 1.1) : Theme.primary

                        StyledText {
                            id: closeText

                            anchors.centerIn: parent
                            text: I18n.tr("Close")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.background
                            font.weight: Theme.fontWeightMedium
                        }

                        MouseArea {
                            id: closeArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.hideDialog()
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
    }
}
