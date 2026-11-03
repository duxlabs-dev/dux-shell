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
    layerNamespace: "dms:qr-generator"

    property bool disablePopupTransparency: true
    property bool generating: false
    property string themedQrCodePath: ""
    property string normalQrCodePath: ""
    property string initialText: ""
    property string _pendingPayload: ""
    property string _generatingPayload: ""
    property string _displayedPayload: ""
    modalWidth: 420
    modalHeight: 440
    onBackgroundClicked: hide()
    onOpened: {
        Qt.callLater(() => {
            modalFocusScope.forceActiveFocus();
            const item = contentLoader.item;
            if (!item)
                return;
            item.saveBrowserLoader = saveBrowserLoader;
            if (item.textInput) {
                item.textInput.text = initialText;
                item.textInput.forceActiveFocus();
            }
            if (initialText.length > 0) {
                _pendingPayload = initialText;
                generateQR(initialText);
            }
        });
    }

    function show(text) {
        generating = false;
        initialText = text || "";
        _pendingPayload = "";
        _generatingPayload = "";
        _displayedPayload = "";
        themedQrCodePath = "";
        normalQrCodePath = "";
        open();
    }

    function hide() {
        deleteQrCodeFiles(themedQrCodePath, normalQrCodePath);
        themedQrCodePath = "";
        normalQrCodePath = "";
        close();
    }

    function deleteQrCodeFiles(themed, normal) {
        if (themed.length > 0)
            DMSService.sendRequest("network.delete-qrcode", {
                path: themed
            });
        if (normal.length > 0)
            DMSService.sendRequest("network.delete-qrcode", {
                path: normal
            });
    }

    Timer {
        id: genTimer
        interval: 200
        repeat: false
        onTriggered: root.generateQR(root._pendingPayload)
    }

    function generateQR(text) {
        const trimmed = (text || "").trim();
        if (trimmed.length === 0 || trimmed === _displayedPayload || generating)
            return;

        _generatingPayload = trimmed;
        generating = true;

        DMSService.sendRequest("network.generate-qrcode", {
            text: trimmed
        }, response => {
            root.generating = false;
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to generate QR code: %1", "error toast, %1 is the error details").arg(JSON.stringify(response.error)));
                return;
            }
            if (!response.result)
                return;
            if (root._generatingPayload !== root._pendingPayload.trim()) {
                root.deleteQrCodeFiles(response.result[0], response.result[1]);
                genTimer.restart();
                return;
            }

            const oldThemed = root.themedQrCodePath;
            const oldNormal = root.normalQrCodePath;
            root._displayedPayload = root._generatingPayload;
            root.themedQrCodePath = response.result[0];
            root.normalQrCodePath = response.result[1];
            root.deleteQrCodeFiles(oldThemed, oldNormal);
        });
    }

    function onTextChanged(text) {
        _pendingPayload = text;
        const trimmed = text.trim();
        if (trimmed.length === 0 || trimmed === _displayedPayload) {
            genTimer.stop();
            return;
        }
        genTimer.restart();
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
            defaultName: "qrcode.png"
            onAccepted: paths => Quickshell.execDetached(["cp", "-f", root.normalQrCodePath, paths[0]])
        }
    }

    content: Component {
        Item {
            id: contentItem

            property alias textInput: textInput
            property var saveBrowserLoader: null

            anchors.fill: parent

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingL

                RowLayout {
                    id: modalTitle
                    width: parent.width

                    StyledText {
                        text: I18n.tr("QR Generator")
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.surfaceText
                        font.weight: Theme.fontWeightMedium
                        Layout.alignment: Qt.AlignLeft
                        Layout.fillWidth: true
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

                DTextField {
                    id: textInput
                    width: parent.width
                    placeholderText: I18n.tr("Enter text to encode")
                    showClearButton: true
                    focus: true
                    onTextEdited: root.onTextChanged(text)
                    Keys.onEscapePressed: event => {
                        event.accepted = true;
                        root.hide();
                    }
                }

                Item {
                    id: qrContainer
                    height: Math.min(parent.height - parent.spacing - modalTitle.height - textInput.height - parent.spacing * 4, 260)
                    width: height
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: 1

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 80
                            easing.type: Easing.OutCubic
                        }
                    }

                    Image {
                        id: qrCodeImg
                        anchors.fill: parent
                        source: root.themedQrCodePath
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        visible: false

                        onSourceChanged: qrContainer.opacity = 0
                        onStatusChanged: {
                            if (status === Image.Ready)
                                qrContainer.opacity = 1;
                        }
                    }

                    MultiEffect {
                        source: qrCodeImg
                        anchors.fill: qrCodeImg
                        colorization: 1.0
                        colorizationColor: Theme.primary
                    }
                }

                RowLayout {
                    width: parent.width
                    visible: root.themedQrCodePath.length > 0
                    Layout.alignment: Qt.AlignHCenter

                    Item {
                        Layout.fillWidth: true
                    }

                    DButton {
                        text: I18n.tr("Save")
                        iconName: "save"
                        backgroundColor: Theme.chipSurface
                        textColor: Theme.surfaceText
                        onClicked: {
                            contentItem.saveBrowserLoader.active = true;
                            if (contentItem.saveBrowserLoader.item) {
                                contentItem.saveBrowserLoader.item.open();
                            }
                        }
                    }

                    DButton {
                        text: I18n.tr("Copy")
                        iconName: "content_copy"
                        backgroundColor: Theme.primary
                        textColor: Theme.onPrimary
                        onClicked: {
                            if (root.normalQrCodePath.length > 0)
                                DMSService.sendRequest("clipboard.copyFile", {
                                    filePath: root.normalQrCodePath
                                });
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
