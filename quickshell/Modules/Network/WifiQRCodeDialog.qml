pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets

DDialog {
    id: root

    property string wifiSSID: ""
    property string themedQrCodePath: ""
    property string normalQrCodePath: ""

    signal ready
    signal failed

    maximumWidth: 420
    title: I18n.tr("WiFi QR code for %1", "%1 is the network name").arg(wifiSSID)

    function load(ssid) {
        cleanup();
        wifiSSID = ssid;
        DMSService.sendRequest("network.qrcode", {
            ssid: ssid
        }, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to fetch network QR code: %1", "error toast, %1 is the error details").arg(JSON.stringify(response.error)));
                failed();
            } else if (response.result) {
                themedQrCodePath = response.result[0];
                normalQrCodePath = response.result[1];
                ready();
            } else {
                failed();
            }
        });
    }

    function cleanup() {
        const paths = [themedQrCodePath, normalQrCodePath];
        themedQrCodePath = "";
        normalQrCodePath = "";
        for (const path of paths) {
            if (path === "")
                continue;
            DMSService.sendRequest("network.delete-qrcode", {
                path: path
            }, response => {
                if (response.error) {
                    ToastService.showError(I18n.tr("Failed to remove QR code at %1: %2", "error toast, %1 is the file path, %2 is the error").arg(path).arg(JSON.stringify(response.error)));
                }
            });
        }
    }

    Component.onDestruction: cleanup()

    headerActions: [
        DActionButton {
            iconName: "save"
            Accessible.name: I18n.tr("Save QR Code")
            iconSize: Theme.iconSize - 4
            iconColor: Theme.surfaceText
            onClicked: {
                saveBrowserLoader.active = true;
                if (saveBrowserLoader.item)
                    (saveBrowserLoader.item as FileBrowserSurfaceModal).open();
            }
        }
    ]

    LazyLoader {
        id: saveBrowserLoader
        active: false

        FileBrowserSurfaceModal {
            browserTitle: I18n.tr("Save QR Code")
            bucket: "qrcode"
            filters: ["*.png"]
            mode: "save"
            defaultName: `${root.wifiSSID ?? "wifi-qrcode"}.png`
            onAccepted: paths => Quickshell.execDetached(["cp", "-f", root.normalQrCodePath, paths[0]])
        }
    }

    Image {
        id: qrCodeImg
        width: parent.width
        height: width
        source: root.themedQrCodePath

        MultiEffect {
            source: qrCodeImg
            anchors.fill: source
            colorization: 1.0
            colorizationColor: Theme.primary
        }
    }
}
