pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import "../../Common/ConnectionEditor.js" as CE

Item {
    id: networkHotspotTab

    property var parentModal

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Component.onCompleted: NetworkService.addRef()
    Component.onDestruction: NetworkService.removeRef()

    NetworkWifiDialogs {
        id: wifiDialogs
        parentModal: networkHotspotTab.parentModal
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            id: hotspotCard

            width: parent.width
            title: I18n.tr("Hotspot", "hotspot settings card title")
            iconName: "wifi_tethering"
            settingKey: "networkHotspot"
            tags: ["wifi", "wi-fi", "wireless", "network", "hotspot", "access point", "sharing", "ssid", "qr code", "channel", "wpa3", "hidden", "security"]
            visible: NetworkService.hotspotSectionAvailable

            property string ssid: NetworkService.hotspotSSID || ""
            property string password: ""
            property string device: NetworkService.hotspotDevice || ""
            property string band: NetworkService.hotspotBand || ""
            property int channel: NetworkService.hotspotChannel || 0
            property string address: NetworkService.hotspotAddress || ""
            property string security: "wpa-psk"
            property bool hidden: false
            property bool autoconnect: false
            readonly property bool extended: NetworkService.hotspotExtendedSupported
            readonly property bool secured: !extended || security !== ""
            readonly property bool addressValid: address.trim().length === 0 || CE.isValidHotspotAddress(address.trim())
            readonly property var hotspotOptions: NetworkService.hotspotExtendedSupported ? {
                "channel": channel,
                "address": address.trim(),
                "security": security,
                "hidden": hidden,
                "autoconnect": autoconnect
            } : ({})
            property bool editing: false
            property bool passwordLoading: false
            property bool passwordResolved: true
            property int passwordRequestId: 0
            property int passwordEditRevision: 0
            readonly property bool showForm: !NetworkService.hotspotConfigured || editing
            readonly property bool passwordValid: !secured || (password.length === 0 ? extended === false : ((password.length >= 8 && password.length <= 63) || /^[0-9a-fA-F]{64}$/.test(password)))
            readonly property bool starting: NetworkService.hotspotBusy || NetworkService.hotspotActivating
            property var startConfirm: ConfirmModal {}

            function confirmThenStart(targetDevice, targetBand, startFn) {
                if (!NetworkService.hotspotTargetWouldDisconnectWifi(targetDevice, targetBand)) {
                    startFn();
                    return;
                }
                startConfirm.showWithOptions({
                    title: I18n.tr("Start Hotspot?", "hotspot start confirmation title"),
                    message: I18n.tr("Starting the hotspot disconnects Wi-Fi from \"%1\". The radio can\'t do both at once, so sharing internet needs another connection such as Ethernet.", "hotspot WiFi disconnection warning, %1 is the network name").arg(NetworkService.currentWifiSSID),
                    confirmText: I18n.tr("Start", "hotspot start confirmation action"),
                    onConfirm: startFn
                });
            }

            function bandLabel(value) {
                switch (value) {
                case "bg":
                    return I18n.tr("2.4 GHz", "hotspot WiFi band option");
                case "a":
                    return I18n.tr("5 GHz", "hotspot WiFi band option");
                default:
                    return I18n.tr("Auto", "hotspot device or band option");
                }
            }

            function bandValue(label) {
                if (label === I18n.tr("2.4 GHz", "hotspot WiFi band option"))
                    return "bg";
                if (label === I18n.tr("5 GHz", "hotspot WiFi band option"))
                    return "a";
                return "";
            }

            function syncFromService() {
                ssid = NetworkService.hotspotSSID || ssid || "";
                device = NetworkService.hotspotDevice || "";
                band = NetworkService.hotspotBand || "";
                channel = NetworkService.hotspotChannel || 0;
                address = NetworkService.hotspotAddress || "";
                security = NetworkService.hotspotConfigured ? NetworkService.hotspotSecurity : "wpa-psk";
                hidden = NetworkService.hotspotHidden;
                autoconnect = NetworkService.hotspotAutoconnect;
            }

            function beginEditing() {
                syncFromService();
                password = "";
                editing = true;
                passwordRequestId++;
                const requestId = passwordRequestId;
                const editRevision = passwordEditRevision;
                passwordLoading = NetworkService.hotspotSecured;
                passwordResolved = !NetworkService.hotspotSecured;
                if (NetworkService.hotspotSecured) {
                    NetworkService.getHotspotSecrets(response => {
                        if (!editing || requestId !== passwordRequestId)
                            return;
                        passwordLoading = false;
                        if (response.error) {
                            ToastService.showError(I18n.tr("Couldn't load hotspot password", "hotspot password error title"), I18n.tr("Re-enter the password before saving.", "hotspot password recovery message"));
                        } else {
                            const storedPassword = response.result?.password ?? response.password ?? "";
                            if (!storedPassword) {
                                ToastService.showError(I18n.tr("Couldn't load hotspot password", "hotspot password error title"), I18n.tr("Re-enter the password before saving.", "hotspot password recovery message"));
                            } else {
                                passwordResolved = true;
                                if (editRevision === passwordEditRevision) {
                                    password = storedPassword;
                                }
                            }
                        }
                    });
                }
            }

            function stopEditing() {
                passwordRequestId++;
                editing = false;
                syncFromService();
                password = "";
                passwordEditRevision = 0;
                passwordLoading = false;
                passwordResolved = true;
            }

            function buildCanConfigure() {
                return ssid.trim().length > 0 && passwordValid && addressValid && (!secured || (passwordResolved && !passwordLoading)) && !NetworkService.hotspotBusy && !NetworkService.hotspotEnabled && !NetworkService.hotspotActivating;
            }

            function explainWiFiDisabled() {
                ToastService.showError(I18n.tr("Wi-Fi is disabled", "hotspot start error title"), I18n.tr("Enable Wi-Fi before starting the hotspot.", "hotspot WiFi requirement message"));
            }

            function saveOnly() {
                if (!buildCanConfigure())
                    return;
                NetworkService.configureHotspot(ssid.trim(), password, device, band, response => {
                    if (!response.error) {
                        stopEditing();
                        ToastService.showInfo(I18n.tr("Hotspot saved", "hotspot configuration success message"));
                    }
                }, hotspotOptions);
            }

            function startOrStop() {
                if (NetworkService.hotspotEnabled) {
                    NetworkService.stopHotspot(response => {
                        if (!response.error)
                            ToastService.showInfo(I18n.tr("Hotspot stopped", "hotspot stop success message"));
                    });
                    return;
                }

                if (!NetworkService.wifiEnabled) {
                    explainWiFiDisabled();
                    return;
                }

                if (showForm) {
                    if (!buildCanConfigure())
                        return;
                    confirmThenStart(device, band, () => {
                        NetworkService.configureAndStartHotspot(ssid.trim(), password, device, band, response => {
                            if (!response.error)
                                stopEditing();
                        }, hotspotOptions);
                    });
                    return;
                }

                confirmThenStart(NetworkService.hotspotDevice, NetworkService.hotspotBand, () => NetworkService.startHotspot());
            }

            onVisibleChanged: if (visible)
                syncFromService()

            SettingsRow {
                body: StyledText {
                    width: parent.width
                    text: {
                        if (NetworkService.hotspotEnabled)
                            return I18n.tr("Your hotspot is running.", "hotspot active status message");
                        if (hotspotCard.starting)
                            return I18n.tr("Starting hotspot...", "hotspot activation status message");
                        if (NetworkService.hotspotConfigured)
                            return I18n.tr("Your hotspot profile is saved and ready to start.", "configured hotspot status message");
                        return I18n.tr("Set up a Wi-Fi hotspot for sharing this connection.", "unconfigured hotspot description");
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: NetworkService.hotspotEnabled ? Theme.primary : Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            SettingsRow {
                visible: !NetworkService.wifiEnabled
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Wi-Fi is disabled. You can still edit and save hotspot settings, but starting the hotspot requires Wi-Fi to be enabled.", "hotspot WiFi requirement explanation")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                    wrapMode: Text.WordWrap
                }
            }

            SettingsRow {
                visible: NetworkService.wifiEnabled && !NetworkService.hotspotEnabled && !hotspotCard.starting && (hotspotCard.showForm ? NetworkService.hotspotTargetWouldDisconnectWifi(hotspotCard.device, hotspotCard.band) : NetworkService.hotspotWouldDisconnectWifi)
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Starting the hotspot disconnects Wi-Fi from \"%1\". The radio can\'t do both at once, so sharing internet needs another connection such as Ethernet.", "hotspot WiFi disconnection warning, %1 is the network name").arg(NetworkService.currentWifiSSID)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                    wrapMode: Text.WordWrap
                }
            }

            SettingsRow {
                visible: !hotspotCard.showForm
                iconName: NetworkService.hotspotEnabled ? "wifi_tethering" : "wifi_tethering_off"
                iconColor: NetworkService.hotspotEnabled ? Theme.primary : Theme.surfaceVariantText
                title: NetworkService.hotspotSSID
                subtitle: {
                    const parts = [NetworkService.hotspotSecured ? (NetworkService.hotspotSecurity === "sae" ? "WPA3" : "WPA2") : I18n.tr("Open network", "hotspot security summary"), hotspotCard.bandLabel(NetworkService.hotspotBand)];
                    if (NetworkService.hotspotHidden)
                        parts.push(I18n.tr("Hidden", "adjective, wifi network with hidden name"));
                    if (NetworkService.hotspotDevice)
                        parts.push(NetworkService.hotspotDevice);
                    if (NetworkService.hotspotChannel > 0)
                        parts.push(I18n.tr("Channel") + " " + NetworkService.hotspotChannel);
                    if (NetworkService.hotspotAddress)
                        parts.push(NetworkService.hotspotAddress);
                    return parts.join(" • ");
                }
            }

            SettingsRow {
                visible: hotspotCard.showForm
                body: DTextField {
                    outlined: true
                    width: parent.width
                    labelText: I18n.tr("Hotspot name", "hotspot SSID field label")
                    placeholderText: I18n.tr("SSID", "hotspot network name placeholder")
                    text: hotspotCard.ssid
                    leftIconName: "badge"
                    showClearButton: true
                    onTextEdited: hotspotCard.ssid = text
                    onAccepted: hotspotCard.saveOnly()
                }
            }

            SettingsDropdownRow {
                visible: hotspotCard.showForm && hotspotCard.extended
                text: I18n.tr("Security", "noun, settings page name and wifi security type label")
                currentValue: hotspotCard.security === "sae" ? "WPA3" : (hotspotCard.security === "wpa-psk" ? "WPA2" : I18n.tr("Open", "network security type", true))
                options: [I18n.tr("Open", "network security type", true), "WPA2", "WPA3"]
                onValueChanged: value => hotspotCard.security = value === "WPA3" ? "sae" : (value === "WPA2" ? "wpa-psk" : "")
            }

            SettingsRow {
                visible: hotspotCard.showForm && hotspotCard.secured
                body: DTextField {
                    outlined: true
                    width: parent.width
                    labelText: I18n.tr("Password", "hotspot password field label")
                    placeholderText: hotspotCard.extended ? "" : I18n.tr("Optional; leave blank for open hotspot", "hotspot password field placeholder")
                    text: hotspotCard.password
                    leftIconName: "key"
                    showPasswordToggle: true
                    echoMode: passwordVisible ? TextInput.Normal : TextInput.Password
                    onTextEdited: {
                        if (text === hotspotCard.password)
                            return;
                        hotspotCard.password = text;
                        hotspotCard.passwordEditRevision++;
                        if (text.length > 0)
                            hotspotCard.passwordResolved = true;
                    }
                    onAccepted: hotspotCard.saveOnly()
                }
            }

            SettingsRow {
                visible: hotspotCard.showForm && hotspotCard.secured && !hotspotCard.passwordValid && hotspotCard.passwordEditRevision > 0
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Password must be 8 to 63 characters, or a 64-digit hex key.", "hotspot password length requirement")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    wrapMode: Text.WordWrap
                }
            }

            SettingsDropdownRow {
                visible: hotspotCard.showForm
                text: I18n.tr("Device", "hotspot WiFi device field label")
                currentValue: hotspotCard.device || I18n.tr("Auto", "hotspot device or band option")
                options: {
                    const devices = NetworkService.wifiDevices || [];
                    return [I18n.tr("Auto", "hotspot device or band option")].concat(devices.filter(d => d.apCapable).map(d => d.name));
                }
                onValueChanged: value => hotspotCard.device = value === I18n.tr("Auto", "hotspot device or band option") ? "" : value
            }

            SettingsDropdownRow {
                visible: hotspotCard.showForm
                text: I18n.tr("Band", "hotspot WiFi band field label")
                currentValue: hotspotCard.bandLabel(hotspotCard.band)
                options: [I18n.tr("Auto", "hotspot device or band option"), I18n.tr("2.4 GHz", "hotspot WiFi band option"), I18n.tr("5 GHz", "hotspot WiFi band option")]
                onValueChanged: value => {
                    hotspotCard.band = hotspotCard.bandValue(value);
                    if (hotspotCard.channel > 0 && CE.hotspotChannels(hotspotCard.band).indexOf(hotspotCard.channel) < 0)
                        hotspotCard.channel = 0;
                }
            }

            SettingsDropdownRow {
                visible: hotspotCard.showForm && NetworkService.hotspotExtendedSupported && hotspotCard.band !== ""
                text: I18n.tr("Channel")
                currentValue: hotspotCard.channel > 0 ? String(hotspotCard.channel) : I18n.tr("Auto", "hotspot device or band option")
                options: [I18n.tr("Auto", "hotspot device or band option")].concat(CE.hotspotChannels(hotspotCard.band).map(c => String(c)))
                onValueChanged: value => hotspotCard.channel = parseInt(value) || 0
            }

            SettingsRow {
                visible: hotspotCard.showForm && NetworkService.hotspotExtendedSupported
                body: DTextField {
                    outlined: true
                    width: parent.width
                    labelText: I18n.tr("IP address")
                    placeholderText: "10.42.0.1/24"
                    leftIconName: "lan"
                    text: hotspotCard.address
                    isError: !hotspotCard.addressValid
                    onTextEdited: hotspotCard.address = text
                    onAccepted: hotspotCard.saveOnly()
                }
            }

            SettingsToggleRow {
                visible: hotspotCard.showForm && hotspotCard.extended
                text: I18n.tr("Hidden", "adjective, wifi network with hidden name")
                checked: hotspotCard.hidden
                onToggled: checked => hotspotCard.hidden = checked
            }

            SettingsToggleRow {
                visible: hotspotCard.showForm && hotspotCard.extended
                text: I18n.tr("Autoconnect", "toggle, connect to this wifi or vpn automatically")
                checked: hotspotCard.autoconnect
                onToggled: checked => hotspotCard.autoconnect = checked
            }

            SettingsRow {
                DButton {
                    visible: hotspotCard.editing
                    text: I18n.tr("Cancel", "cancel hotspot editing action")
                    buttonHeight: 36
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: hotspotCard.stopEditing()
                }

                DButton {
                    visible: !hotspotCard.showForm
                    text: I18n.tr("Edit", "edit hotspot action")
                    iconName: "edit"
                    buttonHeight: 36
                    enabled: !NetworkService.hotspotEnabled && !hotspotCard.starting
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: hotspotCard.beginEditing()
                }

                DButton {
                    visible: hotspotCard.showForm
                    text: hotspotCard.passwordLoading ? I18n.tr("Loading...", "hotspot password loading status") : (NetworkService.hotspotBusy ? I18n.tr("Saving...", "hotspot configuration saving status") : I18n.tr("Save", "save hotspot configuration action"))
                    iconName: "save"
                    buttonHeight: 36
                    enabled: hotspotCard.buildCanConfigure()
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: hotspotCard.saveOnly()
                }

                DButton {
                    visible: NetworkService.hotspotEnabled && NetworkService.hotspotSecured && NetworkService.hotspotExtendedSupported
                    text: I18n.tr("Show QR Code")
                    iconName: "qr_code"
                    buttonHeight: 36
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: wifiDialogs.openQRCode(NetworkService.hotspotSSID)
                }

                DButton {
                    text: {
                        if (NetworkService.hotspotEnabled)
                            return I18n.tr("Stop", "stop hotspot action");
                        if (!NetworkService.hotspotAvailable)
                            return I18n.tr("No adapter", "hotspot start button when no Wi-Fi adapter can host a hotspot");
                        if (hotspotCard.starting)
                            return I18n.tr("Starting...", "hotspot activation status");
                        return hotspotCard.showForm ? I18n.tr("Save & Start", "save and start hotspot action") : I18n.tr("Start", "start hotspot action");
                    }
                    iconName: NetworkService.hotspotEnabled ? "stop" : "wifi_tethering"
                    buttonHeight: 36
                    enabled: !hotspotCard.starting && (NetworkService.hotspotEnabled || (NetworkService.hotspotAvailable && hotspotCard.buildCanConfigure()))
                    danger: NetworkService.hotspotEnabled
                    onClicked: hotspotCard.startOrStop()
                }
            }
        }
    }
}
