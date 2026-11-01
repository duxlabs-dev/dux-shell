pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/GSettings.js" as GSettings

Singleton {
    id: root
    readonly property var log: Log.scoped("PortalService")

    property bool accountsServiceAvailable: false
    property string systemProfileImage: ""
    property string profileImage: ""
    readonly property string profileImageUrl: {
        if (!profileImage.startsWith("/"))
            return profileImage;
        return "file://" + profileImage.split("/").map(part => encodeURIComponent(part)).join("/");
    }
    property bool settingsPortalAvailable: false
    property int systemColorScheme: 0
    property bool colorSchemeInitialized: false

    property bool freedeskAvailable: false
    property string pendingProfileImage: ""

    readonly property string socketPath: Quickshell.env("DMS_SOCKET")

    function init() {
    }

    function getSystemProfileImage() {
        if (!freedeskAvailable)
            return;
        const username = Quickshell.env("USER");
        if (!username)
            return;
        DMSService.sendRequest("freedesktop.accounts.getUserIconFile", {
            "username": username
        }, response => {
            if (response.result && response.result.success) {
                const iconFile = response.result.value || "";
                if (iconFile && iconFile !== "" && iconFile !== "/var/lib/AccountsService/icons/") {
                    systemProfileImage = iconFile;
                    if (!profileImage || profileImage === "") {
                        profileImage = iconFile;
                    }
                }
            }
        });
    }

    function getUserProfileImage(username) {
        if (!username) {
            profileImage = "";
            return;
        }
        if (!freedeskAvailable) {
            profileImage = "";
            return;
        }

        DMSService.sendRequest("freedesktop.accounts.getUserIconFile", {
            "username": username
        }, response => {
            if (response.result && response.result.success) {
                const icon = response.result.value || "";
                if (icon && icon !== "" && icon !== "/var/lib/AccountsService/icons/") {
                    profileImage = icon;
                } else {
                    profileImage = "";
                }
            } else {
                profileImage = "";
            }
        });
    }

    function setProfileImage(imagePath) {
        if (accountsServiceAvailable) {
            pendingProfileImage = imagePath;
            setSystemProfileImage(imagePath || "");
        } else {
            profileImage = imagePath;
        }
    }

    function canSyncColorScheme() {
        if (typeof SettingsData === "undefined" || !SettingsData.syncModeWithPortal)
            return false;
        if (!settingsPortalAvailable)
            return false;
        if (typeof SessionData !== "undefined" && SessionData.themeModeAutoEnabled)
            return false;
        if (SettingsData.matugenSmartMode && typeof Theme !== "undefined" && Theme.currentTheme === Theme.dynamic)
            return false;
        return typeof Theme !== "undefined";
    }

    // Follow only genuine portal transitions, debounced by the settle window — the
    // opt-in GTK4-refresh toggle reverts within ~400ms, and a stale portal value
    // (broken gsettings→portal bridge) must never revert a DMS-initiated change.
    function handlePortalColorScheme(scheme) {
        const isTransition = colorSchemeInitialized && scheme !== systemColorScheme;
        colorSchemeInitialized = true;
        systemColorScheme = scheme;

        if (!canSyncColorScheme())
            return;

        const shouldBeLight = scheme !== 1;
        if (Theme.isLightMode === shouldBeLight) {
            colorSchemeSettleTimer.stop();
            return;
        }
        if (!isTransition)
            return;
        colorSchemeSettleTimer.restart();
    }

    Timer {
        id: colorSchemeSettleTimer
        interval: 750
        onTriggered: {
            if (!root.canSyncColorScheme())
                return;
            const shouldBeLight = root.systemColorScheme !== 1;
            if (Theme.isLightMode === shouldBeLight)
                return;
            if (Theme.workerRunning) {
                restart();
                return;
            }
            Theme.setLightMode(shouldBeLight, true, false);
        }
    }

    function setSystemColorScheme(isLightMode) {
        const preferLight = isLightMode && systemColorScheme === 2;
        const targetScheme = isLightMode ? (preferLight ? "prefer-light" : "default") : "prefer-dark";

        Quickshell.execDetached(["sh", "-c", GSettings.setCmd("org.gnome.desktop.interface", "color-scheme", targetScheme)]);
    }

    function setSystemIconTheme(themeName) {
        if (!settingsPortalAvailable || !freedeskAvailable)
            return;
        DMSService.sendRequest("freedesktop.settings.setIconTheme", {
            "iconTheme": themeName
        }, response => {
            if (response.error) {
                log.warn("Failed to set icon theme:", response.error);
            }
        });
    }

    function setSystemProfileImage(imagePath) {
        if (!accountsServiceAvailable || !freedeskAvailable)
            return;
        DMSService.sendRequest("freedesktop.accounts.setIconFile", {
            "path": imagePath || ""
        }, response => {
            if (response.error) {
                log.warn("Failed to set icon file:", response.error);

                const errorMsg = response.error.toString();
                let userMessage = I18n.tr("Failed to set profile image");

                if (errorMsg.includes("too large")) {
                    userMessage = I18n.tr("Profile image is too large. Please use a smaller image.");
                } else if (errorMsg.includes("permission")) {
                    userMessage = I18n.tr("Permission denied to set profile image.");
                } else if (errorMsg.includes("not found") || errorMsg.includes("does not exist")) {
                    userMessage = I18n.tr("Selected image file not found.");
                } else {
                    userMessage = I18n.tr("Failed to set profile image: %1", "error message, %1 is the error detail").arg(errorMsg.split(":").pop().trim());
                }

                Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "DMS", "-i", "error", I18n.tr("Profile Image Error"), userMessage]);

                pendingProfileImage = "";
            } else {
                profileImage = pendingProfileImage;
                pendingProfileImage = "";
                Qt.callLater(() => getSystemProfileImage());
            }
        });
    }

    Component.onCompleted: {
        if (socketPath && socketPath.length > 0) {
            checkDMSCapabilities();
        } else {
            log.info("DMS_SOCKET not set");
        }
    }

    Connections {
        target: Theme
        enabled: SettingsData.syncModeWithPortal

        function onIsLightModeChanged() {
            root.setSystemColorScheme(Theme.isLightMode);
        }
    }

    Connections {
        target: typeof SettingsData !== "undefined" ? SettingsData : null

        function onSyncModeWithPortalChanged() {
            if (!SettingsData.syncModeWithPortal)
                return;
            if (typeof Theme === "undefined")
                return;
            root.setSystemColorScheme(Theme.isLightMode);
        }
    }

    Connections {
        target: DMSService

        function onFreedesktopStateUpdate(data) {
            if (!data || !data.settings)
                return;
            root.settingsPortalAvailable = data.settings.available === true;
            root.handlePortalColorScheme(data.settings.colorScheme || 0);
        }
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                checkDMSCapabilities();
            }
        }
    }

    Connections {
        target: DMSService
        enabled: DMSService.isConnected

        function onCapabilitiesChanged() {
            checkDMSCapabilities();
        }
    }

    function checkDMSCapabilities() {
        if (!DMSService.isConnected) {
            return;
        }

        if (DMSService.capabilities.length === 0) {
            return;
        }

        freedeskAvailable = DMSService.capabilities.includes("freedesktop");
        if (freedeskAvailable) {
            checkAccountsService();
            checkSettingsPortal();
        } else {
            log.info("freedesktop capability not available in DMS");
        }
    }

    function checkAccountsService() {
        if (!freedeskAvailable)
            return;
        DMSService.sendRequest("freedesktop.getState", null, response => {
            if (response.result && response.result.accounts) {
                accountsServiceAvailable = response.result.accounts.available || false;
                if (accountsServiceAvailable) {
                    getSystemProfileImage();
                }
            }
        });
    }

    function checkSettingsPortal() {
        if (!freedeskAvailable)
            return;
        DMSService.sendRequest("freedesktop.getState", null, response => {
            if (response.result && response.result.settings) {
                settingsPortalAvailable = response.result.settings.available || false;
                handlePortalColorScheme(response.result.settings.colorScheme || 0);
            }
        });
    }

    IpcHandler {
        target: "profile"

        function getImage(): string {
            return root.profileImage;
        }

        function setImage(path: string): string {
            if (!path) {
                return "ERROR: No path provided";
            }

            const absolutePath = path.startsWith("/") ? path : `${StandardPaths.writableLocation(StandardPaths.HomeLocation)}/${path}`;

            try {
                root.setProfileImage(absolutePath);
                return "SUCCESS: Profile image set to " + absolutePath;
            } catch (e) {
                return "ERROR: Failed to set profile image: " + e.toString();
            }
        }

        function clearImage(): string {
            root.setProfileImage("");
            return "SUCCESS: Profile image cleared";
        }
    }
}
