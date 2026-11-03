import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.Modals.Common
import qs.Modals.FileBrowser
import qs.Common
import qs.Services
import qs.DCommon.Widgets

DModal {
    id: root
    visible: false
    layerNamespace: "dms:wifi-qrcode"

    property bool disablePopupTransparency: true
    property string wifiSSID: ""
    property string themedQrCodePath: ""
    property string normalQrCodePath: ""
    modalWidth: 420
    modalHeight: 480
    onBackgroundClicked: hide()
    onOpened: {
        Qt.callLater(() => {
            modalFocusScope.forceActiveFocus();
            contentLoader.item.wifiSSID = wifiSSID;
            contentLoader.item.themedQrCodePath = themedQrCodePath;
            contentLoader.item.saveBrowserLoader = saveBrowserLoader;
        });
    }

    function show(ssid) {
        wifiSSID = ssid;
        fetchNetworkQRCode(ssid);
    }

    function hide() {
        if (themedQrCodePath !== "") {
            deleteQRCodeFile(themedQrCodePath);
        }
        if (normalQrCodePath !== "") {
            deleteQRCodeFile(normalQrCodePath);
        }
        close();
    }

    function fetchNetworkQRCode(ssid) {
        // TODO: Add loading UI?

        DMSService.sendRequest("network.qrcode", {
            ssid: ssid
        }, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to fetch network QR code: %1", "error toast, %1 is the error details").arg(JSON.stringify(response.error)));
            } else if (response.result) {
                themedQrCodePath = response.result[0];
                normalQrCodePath = response.result[1];
                open();
            }
        });
    }

    function deleteQRCodeFile(path) {
        DMSService.sendRequest("network.delete-qrcode", {
            path: path
        }, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to remove QR code at %1: %2", "error toast, %1 is the file path, %2 is the error").arg(path).arg(JSON.stringify(response.error)));
            }
        });
    }

    LazyLoader {
        id: saveBrowserLoader
        active: false

        FileBrowserSurfaceModal {
            id: saveBrowser

            browserTitle: I18n.tr("Save QR Code")
            bucket: "qrcode"
            filters: ["*.png"]
            mode: "save"
            defaultName: `${root.wifiSSID ?? "wifi-qrcode"}.png`
            onAccepted: paths => Quickshell.execDetached(["cp", "-f", root.normalQrCodePath, paths[0]])
        }
    }

    content: Component {
        Item {
            id: theItem
            property alias themedQrCodePath: qrCodeImg.source
            property var saveBrowserLoader: null
            property string wifiSSID: ""
            anchors.fill: parent

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingL

                RowLayout {
                    id: modalTitle
                    width: parent.width

                    StyledText {
                        text: I18n.tr("WiFi QR code for %1", "%1 is the network name").arg(theItem.wifiSSID)
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.surfaceText
                        font.weight: Theme.fontWeightMedium
                        Layout.alignment: Qt.AlignLeft
                    }

                    DActionButton {
                        iconName: "save"
                        Accessible.name: I18n.tr("Save QR Code")
                        iconSize: Theme.iconSize - 4
                        iconColor: Theme.surfaceText
                        onClicked: {
                            saveBrowserLoader.active = true;
                            if (saveBrowserLoader.item) {
                                saveBrowserLoader.item.open();
                            }
                        }
                        Layout.alignment: Qt.AlignRight
                    }

                    DActionButton {
                        iconName: "close"
                        Accessible.name: I18n.tr("Close")
                        iconSize: Theme.iconSize - 4
                        iconColor: Theme.surfaceText
                        onClicked: root.hide()
                        Layout.alignment: Qt.AlignRight
                    }
                }

                Image {
                    id: qrCodeImg
                    height: parent.height - parent.spacing - modalTitle.height
                    width: height
                    anchors.horizontalCenter: parent.horizontalCenter

                    MultiEffect {
                        source: qrCodeImg
                        anchors.fill: source
                        colorization: 1.0
                        colorizationColor: Theme.primary
                    }
                }
            }
        }
    }
}
