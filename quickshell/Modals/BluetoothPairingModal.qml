import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets

DModal {
    id: root
    readonly property var log: Log.scoped("BluetoothPairingModal")

    layerNamespace: "dms:bluetooth-pairing"

    property string deviceName: ""
    property string deviceAddress: ""
    property string requestType: ""
    property string token: ""
    property int passkey: 0
    property string pinInput: ""
    property string passkeyInput: ""

    function show(pairingData) {
        log.debug("BluetoothPairingModal.show() called:", JSON.stringify(pairingData));
        token = pairingData.token || "";
        deviceName = pairingData.deviceName || "";
        deviceAddress = pairingData.deviceAddr || "";
        requestType = pairingData.requestType || "";
        passkey = pairingData.passkey || 0;
        pinInput = "";
        passkeyInput = "";

        log.debug("Calling open()");
        open();
        Qt.callLater(() => {
            if (contentLoader.item) {
                if (requestType === "pin" && contentLoader.item.pinInputField) {
                    contentLoader.item.pinInputField.forceActiveFocus();
                } else if (requestType === "passkey" && contentLoader.item.passkeyInputField) {
                    contentLoader.item.passkeyInputField.forceActiveFocus();
                }
            }
        });
    }

    shouldBeVisible: false
    allowStacking: true
    keepPopoutsOpen: true
    modalWidth: 420
    modalHeight: contentLoader.item ? contentLoader.item.implicitHeight + Theme.spacingM * 2 : 240

    onShouldBeVisibleChanged: () => {
        if (!shouldBeVisible) {
            pinInput = "";
            passkeyInput = "";
        }
    }

    onOpened: {
        Qt.callLater(() => {
            if (contentLoader.item) {
                if (requestType === "pin" && contentLoader.item.pinInputField) {
                    contentLoader.item.pinInputField.forceActiveFocus();
                } else if (requestType === "passkey" && contentLoader.item.passkeyInputField) {
                    contentLoader.item.passkeyInputField.forceActiveFocus();
                }
            }
        });
    }

    onBackgroundClicked: () => {
        if (token) {
            DMSService.bluetoothCancelPairing(token);
        }
        close();
        token = "";
        pinInput = "";
        passkeyInput = "";
    }

    content: Component {
        FocusScope {
            id: pairingContent

            property alias pinInputField: pinInputField
            property alias passkeyInputField: passkeyInputField

            anchors.fill: parent
            focus: true
            implicitHeight: mainColumn.implicitHeight

            Keys.onEscapePressed: event => {
                if (token) {
                    DMSService.bluetoothCancelPairing(token);
                }
                close();
                token = "";
                pinInput = "";
                passkeyInput = "";
                event.accepted = true;
            }

            Column {
                id: mainColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                anchors.topMargin: Theme.spacingM
                spacing: requestType === "pin" || requestType === "passkey" ? Theme.spacingM : Theme.spacingS

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Pair Bluetooth Device")
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.surfaceText
                        font.weight: Theme.fontWeightMedium
                    }

                    StyledText {
                        text: {
                            switch (requestType) {
                            case "confirm":
                                return I18n.tr("Confirm passkey for %1", "%1 is the device name").arg(deviceName);
                            case "display-passkey":
                                return I18n.tr("Enter this passkey on %1", "%1 is the device name").arg(deviceName);
                            case "authorize":
                                return I18n.tr("Authorize pairing with %1", "%1 is the device name").arg(deviceName);
                            case "pin":
                                return I18n.tr("Enter PIN for %1", "%1 is the device or network name").arg(deviceName);
                            case "passkey":
                                return I18n.tr("Enter passkey for %1", "%1 is the device name").arg(deviceName);
                            default:
                                if (requestType.startsWith("authorize-service"))
                                    return I18n.tr("Authorize service for %1", "%1 is the device name").arg(deviceName);
                                return deviceName;
                            }
                        }
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceTextMedium
                        width: parent.width - 40
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 50
                    radius: Theme.cornerRadius
                    color: Theme.floatingWindowFieldColor
                    border.color: pinInputField.activeFocus ? Theme.primary : Theme.outlineStrong
                    border.width: pinInputField.activeFocus ? 2 : 1
                    visible: requestType === "pin"

                    MouseArea {
                        anchors.fill: parent
                        onClicked: () => {
                            pinInputField.forceActiveFocus();
                        }
                    }

                    DTextField {
                        id: pinInputField

                        anchors.fill: parent
                        font.pixelSize: Theme.fontSizeMedium
                        textColor: Theme.surfaceText
                        text: pinInput
                        placeholderText: I18n.tr("Enter PIN")
                        backgroundColor: "transparent"
                        enabled: root.shouldBeVisible
                        onTextEdited: () => {
                            pinInput = text;
                        }
                        onAccepted: () => {
                            submitPairing();
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 50
                    radius: Theme.cornerRadius
                    color: Theme.floatingWindowFieldColor
                    border.color: passkeyInputField.activeFocus ? Theme.primary : Theme.outlineStrong
                    border.width: passkeyInputField.activeFocus ? 2 : 1
                    visible: requestType === "passkey"

                    MouseArea {
                        anchors.fill: parent
                        onClicked: () => {
                            passkeyInputField.forceActiveFocus();
                        }
                    }

                    DTextField {
                        id: passkeyInputField

                        anchors.fill: parent
                        font.pixelSize: Theme.fontSizeMedium
                        textColor: Theme.surfaceText
                        text: passkeyInput
                        placeholderText: I18n.tr("Enter 6-digit passkey")
                        backgroundColor: "transparent"
                        enabled: root.shouldBeVisible
                        onTextEdited: () => {
                            passkeyInput = text;
                        }
                        onAccepted: () => {
                            submitPairing();
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 56
                    radius: Theme.cornerRadius
                    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium
                    visible: requestType === "confirm" || requestType === "display-passkey"

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingXXS

                        StyledText {
                            text: I18n.tr("Passkey:", "bluetooth pairing dialog label before the passkey")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: String(passkey).padStart(6, "0")
                            font.pixelSize: Theme.fontSizeXLarge
                            color: Theme.surfaceText
                            font.weight: Theme.fontWeightMedium
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 36

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        Rectangle {
                            width: Math.max(70, cancelText.contentWidth + Theme.spacingM * 2)
                            height: 36
                            radius: Theme.cornerRadius
                            color: cancelArea.containsMouse ? Theme.surfaceTextHover : Theme.withAlpha(Theme.surfaceTextHover, 0)
                            border.color: Theme.surfaceVariantAlpha
                            border.width: 1

                            StyledText {
                                id: cancelText

                                anchors.centerIn: parent
                                text: I18n.tr("Cancel")
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                font.weight: Theme.fontWeightMedium
                            }

                            MouseArea {
                                id: cancelArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: () => {
                                    if (token) {
                                        DMSService.bluetoothCancelPairing(token);
                                    }
                                    close();
                                    token = "";
                                    pinInput = "";
                                    passkeyInput = "";
                                }
                            }
                        }

                        Rectangle {
                            width: Math.max(80, pairText.contentWidth + Theme.spacingM * 2)
                            height: 36
                            radius: Theme.cornerRadius
                            color: pairArea.containsMouse ? Qt.darker(Theme.primary, 1.1) : Theme.primary
                            enabled: {
                                if (requestType === "pin")
                                    return pinInput.length > 0;
                                if (requestType === "passkey")
                                    return passkeyInput.length === 6;
                                return true;
                            }
                            opacity: enabled ? 1 : 0.5

                            StyledText {
                                id: pairText

                                anchors.centerIn: parent
                                text: {
                                    switch (requestType) {
                                    case "confirm":
                                    case "display-passkey":
                                        return I18n.tr("Confirm");
                                    case "authorize":
                                        return I18n.tr("Authorize", "verb, bluetooth pairing dialog confirm button");
                                    default:
                                        if (requestType.startsWith("authorize-service"))
                                            return I18n.tr("Authorize");
                                        return I18n.tr("Pair", "verb, bluetooth device pairing button");
                                    }
                                }
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.background
                                font.weight: Theme.fontWeightMedium
                            }

                            MouseArea {
                                id: pairArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: parent.enabled
                                onClicked: () => {
                                    submitPairing();
                                }
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

            DActionButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                iconName: "close"
                Accessible.name: I18n.tr("Cancel")
                iconSize: Theme.iconSize - 4
                iconColor: Theme.surfaceText
                onClicked: () => {
                    if (token) {
                        DMSService.bluetoothCancelPairing(token);
                    }
                    close();
                    token = "";
                    pinInput = "";
                    passkeyInput = "";
                }
            }
        }
    }

    function submitPairing() {
        const secrets = {};

        switch (requestType) {
        case "pin":
            secrets["pin"] = pinInput;
            break;
        case "passkey":
            secrets["passkey"] = passkeyInput;
            break;
        case "confirm":
        case "display-passkey":
        case "authorize":
            secrets["decision"] = "yes";
            break;
        default:
            if (requestType.startsWith("authorize-service")) {
                secrets["decision"] = "yes";
            }
            break;
        }

        DMSService.bluetoothSubmitPairing(token, secrets, true, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Pairing failed"), response.error);
            }
        });

        close();
        token = "";
        pinInput = "";
        passkeyInput = "";
    }
}
