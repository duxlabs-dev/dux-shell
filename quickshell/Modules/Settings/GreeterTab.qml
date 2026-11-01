pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    ConfirmModal {
        id: greeterActionConfirm
    }

    ConfirmModal {
        id: unlinkConfirm
    }

    ConfirmModal {
        id: unlinkFinalConfirm
    }

    function promptUnlink() {
        unlinkConfirm.showWithOptions({
            "title": I18n.tr("Unlink login screen", "greeter advanced action"),
            "message": I18n.tr("The login screen stops following your DMS theme, wallpaper, widgets and settings. greetd, authentication and other users are not affected.", "greeter unlink confirmation"),
            "confirmText": I18n.tr("Unlink", "verb, greeter unlink button"),
            "cancelText": I18n.tr("Cancel"),
            "confirmColor": Theme.error,
            "onConfirm": () => Qt.callLater(root.promptUnlinkFinal),
            "onCancel": () => {}
        });
    }

    function promptUnlinkFinal() {
        unlinkFinalConfirm.showWithOptions({
            "title": I18n.tr("Unlink now?", "greeter unlink second confirmation"),
            "message": I18n.tr("Your greeter slot and any cache links to your home are removed. Administrator access may be required. Set up links them again.", "greeter unlink second confirmation"),
            "confirmText": I18n.tr("Unlink", "verb, greeter unlink button"),
            "cancelText": I18n.tr("Cancel"),
            "confirmColor": Theme.error,
            "onConfirm": () => GreeterService.unlink(),
            "onCancel": () => {}
        });
    }

    property string greeterStatusText: ""
    property bool greeterStatusRunning: false
    readonly property bool greeterSyncRunning: GreeterService.syncing
    readonly property string greeterSyncStatus: GreeterService.syncStatus
    property bool greeterInstallActionRunning: false
    property string greeterStatusStdout: ""
    property string greeterStatusStderr: ""
    readonly property bool greeterBinaryExists: GreeterService.binaryExists
    readonly property bool greeterEnabled: GreeterService.enabled
    readonly property bool busy: greeterSyncRunning || greeterInstallActionRunning

    readonly property string greeterState: {
        if (!greeterBinaryExists)
            return "missing";
        if (!greeterEnabled)
            return "inactive";
        switch (GreeterService.slotState) {
        case "live":
            return "linked";
        case "snapshot":
            return "snapshot";
        }
        return "unlinked";
    }
    readonly property bool greeterStateWarn: greeterState !== "linked"
    readonly property string greeterStateIcon: {
        switch (greeterState) {
        case "linked":
            return "link";
        case "snapshot":
            return "history";
        case "inactive":
            return "login";
        case "unlinked":
            return "link_off";
        }
        return "info";
    }
    readonly property string greeterStateTitle: {
        switch (greeterState) {
        case "linked":
            return I18n.tr("Linked", "greeter status, login screen follows DMS settings live");
        case "snapshot":
            return I18n.tr("Linked as a snapshot", "greeter status, login screen reads a copy of DMS settings");
        case "inactive":
            return I18n.tr("Not active", "greeter status, greetd does not run the DMS greeter");
        case "unlinked":
            return I18n.tr("Not linked", "greeter status, no greeter slot for this user");
        }
        return I18n.tr("Not installed", "greeter status");
    }
    readonly property string greeterStateSubtitle: {
        switch (greeterState) {
        case "linked":
            return I18n.tr("The login screen follows your theme, wallpaper, widgets and behavior live. Only authentication changes need applying.", "greeter status");
        case "snapshot":
            return I18n.tr("This system cannot link settings live. Sync again after changing them.", "greeter status");
        case "inactive":
            return I18n.tr("greetd is not using the DMS greeter yet.", "greeter status");
        case "unlinked":
            return GreeterService.profileSyncSufficient ? I18n.tr("Link your DMS settings so the login screen follows them.", "greeter status") : I18n.tr("Link your DMS settings so the login screen follows them. Administrator access is required.", "greeter status");
        }
        return I18n.tr("%1 is not installed. Install the package to manage the greeter.", "greeter status placeholder, %1 is the dms-greeter binary").arg("dms-greeter");
    }
    readonly property string greeterStateAction: {
        switch (greeterState) {
        case "inactive":
            return I18n.tr("Activate");
        case "unlinked":
            return I18n.tr("Set up", "greeter setup button, links DMS settings to the login screen");
        case "snapshot":
            return I18n.tr("Sync", "verb, button that copies settings to the login greeter");
        }
        return "";
    }

    function runStateAction() {
        if (greeterState === "inactive") {
            promptGreeterActionConfirm();
            return;
        }
        GreeterService.link();
    }

    readonly property string greeterStatusOutput: greeterStatusRunning ? I18n.tr("Checking...", "greeter status loading") : greeterStatusText

    onGreeterSyncStatusChanged: greeterStatusText = greeterSyncStatus

    function checkGreeterInstallState() {
        GreeterService.refresh();
    }

    function runGreeterStatus() {
        greeterStatusText = "";
        greeterStatusStdout = "";
        greeterStatusStderr = "";
        greeterStatusRunning = true;
        greeterStatusProcess.running = true;
    }

    function runGreeterInstallAction() {
        greeterStatusText = I18n.tr("Opening terminal: %1", "%1 is the action name").arg(I18n.tr("Activate")) + "...";
        greeterInstallActionRunning = true;
        greeterInstallActionProcess.running = true;
    }

    function promptGreeterActionConfirm() {
        greeterActionConfirm.showWithOptions({
            "title": I18n.tr("Activate Greeter", "greeter action confirmation"),
            "message": I18n.tr("Activate the DMS greeter? A terminal will open for sudo authentication. Run Sync after activation to apply your settings."),
            "confirmText": I18n.tr("Activate", "verb, enable the greeter, also activate a wired network profile"),
            "cancelText": I18n.tr("Cancel"),
            "confirmColor": Theme.primary,
            "onConfirm": () => root.runGreeterInstallAction(),
            "onCancel": () => {}
        });
    }

    Component.onCompleted: {
        Qt.callLater(checkGreeterInstallState);
    }

    Process {
        id: greetdEnabledCheckProcess
        command: ["sh", "-c", "if [ \"$(uname -s)\" = FreeBSD ]; then service -e 2>/dev/null | grep -Eq \"/greetd$\" && echo enabled || echo disabled; else systemctl is-enabled greetd 2>/dev/null; fi"]
        running: false
    }

    function showWidgetBrowser() {
        greeterWidgetBrowserLoader.active = true;
        greeterWidgetBrowserLoader.item?.show();
    }

    LazyLoader {
        id: greeterWidgetBrowserLoader
        active: false

        DesktopWidgetBrowser {
            parentModal: root.parentModal
            listKey: "greeterWidgetInstances"
            title: I18n.tr("Add widget")
            onWidgetAdded: ToastService.showInfo(I18n.tr("Widget added"))
        }
    }

    Process {
        id: greeterStatusProcess
        command: ["dms-greeter", "status"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.greeterStatusStdout = text || "";
            }
        }

        stderr: StdioCollector {
            onStreamFinished: root.greeterStatusStderr = text || ""
        }

        onExited: exitCode => {
            root.greeterStatusRunning = false;
            const out = (root.greeterStatusStdout || "").trim();
            const err = (root.greeterStatusStderr || "").trim();
            if (exitCode === 0) {
                root.greeterStatusText = out !== "" ? out : I18n.tr("No status output.");
                if (err !== "")
                    root.greeterStatusText = root.greeterStatusText + "\n\nstderr:\n" + err;
                return;
            }
            var failure = I18n.tr("Failed to run '%1'. Ensure the %2 package is installed.", "greeter status error, %1 is a command, %2 a package name").arg("dms-greeter status").arg("dux-greeter") + " " + I18n.tr("(exit %1)", "process exit code").arg(exitCode);
            if (out !== "")
                failure = failure + "\n\n" + out;
            if (err !== "")
                failure = failure + "\n\nstderr:\n" + err;
            root.greeterStatusText = failure;
        }
    }

    Connections {
        target: GreeterService

        function onSyncFinished() {
            root.checkGreeterInstallState();
        }
    }

    Process {
        id: greeterInstallActionProcess
        command: ["dms-greeter", "enable", "--terminal"]
        running: false

        onExited: exitCode => {
            root.greeterInstallActionRunning = false;
            root.checkGreeterInstallState();
            if (exitCode !== 0) {
                root.greeterStatusText = I18n.tr("Action failed or terminal was closed.") + " " + I18n.tr("(exit %1)", "process exit code").arg(exitCode);
                return;
            }
            root.greeterStatusText = I18n.tr("Greeter activated. greetd is now enabled.");
        }
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width
            iconName: "info"
            title: I18n.tr("Status")
            settingKey: "greeterStatus"
            tags: ["greeter", "login", "sync", "status", "link"]

            SettingsRow {
                iconName: root.greeterStateIcon
                iconColor: root.greeterStateWarn ? Theme.warning : Theme.primary
                title: root.greeterStateTitle
                subtitle: root.greeterStateSubtitle

                DButton {
                    visible: root.greeterStateAction !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.greeterStateAction
                    busy: root.greeterSyncRunning
                    enabled: !root.busy
                    onClicked: root.runStateAction()
                }
            }

            SettingsNoteRow {
                visible: root.greeterStatusOutput !== ""
                noteIconName: ""
                monospace: true
                maxHeight: SettingsMetrics.noteMaxHeight
                text: root.greeterStatusOutput
                tint: root.greeterStatusRunning ? Theme.surfaceVariantText : Theme.surfaceText
                tintBackground: SettingsMetrics.controlColor
            }
        }

        SettingsCard {
            SettingsNavRow {
                settingKey: "greeterAuth"
                tags: ["greeter", "login", "authentication", "pam", "fingerprint", "security", "key"]
                title: I18n.tr("Authentication")
                iconName: "fingerprint"
                onClicked: keyboard => root.parentModal?.navigateTo("greeter_auth", keyboard)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "widgets"
            title: I18n.tr("Widgets")
            settingKey: "greeterWidgets"
            tags: ["greeter", "login", "widgets", "clock", "session", "layout"]

            SettingsToggleRow {
                settingKey: "greeterFollowLockScreen"
                tags: ["greeter", "login", "lock", "widgets", "layout", "follow"]
                text: I18n.tr("Follow lock screen", "greeter widgets toggle")
                description: I18n.tr("The login screen shows the lock screen widgets it supports and its own session picker. Turn off to arrange it separately.", "greeter widgets toggle")
                checked: SettingsData.greeterFollowLockScreen
                onToggled: checked => SettingsData.setGreeterFollowLockScreen(checked)
            }

            SettingsReorderList {
                id: greeterWidgetList

                model: SettingsData.greeterWidgetInstances || []

                delegate: DesktopWidgetInstanceCard {
                    required property var modelData

                    reorderList: greeterWidgetList
                    reorderEnabled: false
                    instanceData: modelData
                    fixed: SettingsData.greeterFollowLockScreen || modelData.widgetType === "lockAuth" || modelData.widgetType === "greeterSession"

                    onConfigureRequested: {
                        SettingsUiState.selectedDesktopWidgetId = instanceId;
                        SettingsUiState.selectedWidgetTitle = widgetName;
                        root.parentModal?.navigateTo("desktop_widget");
                    }
                    onDuplicateRequested: SettingsData.duplicateDesktopWidgetInstance(instanceId)
                    onDeleteRequested: {
                        SettingsData.removeDesktopWidgetInstance(instanceId);
                        ToastService.showInfo(I18n.tr("Widget removed"));
                    }
                }
            }

            SettingsRow {
                iconName: "restart_alt"
                title: I18n.tr("Reset to default")
                visible: !SettingsData.greeterFollowLockScreen
                clickable: true
                onClicked: SettingsData.resetGreeterWidgets()
            }
        }

        SettingsCard {
            title: I18n.tr("Appearance")
            settingKey: "greeterAppearance"
            tags: ["greeter", "login", "sync", "theme", "wallpaper"]

            SettingsRow {
                subtitle: I18n.tr("Uses your wallpaper, fonts and lock screen settings.", "login screen appearance")
            }

            SettingsNavRow {
                title: I18n.tr("Wallpaper & colors")
                iconName: "wallpaper"
                onClicked: keyboard => root.parentModal?.navigateTo("personalization", keyboard)
            }

            SettingsNavRow {
                title: I18n.tr("Fonts & motion")
                iconName: "text_fields"
                onClicked: keyboard => root.parentModal?.navigateTo("typography", keyboard)
            }

            SettingsNavRow {
                title: I18n.tr("Lock screen")
                iconName: "lock"
                onClicked: keyboard => root.parentModal?.navigateTo("lock_screen", keyboard)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "history"
            title: I18n.tr("Behavior")
            settingKey: "greeterBehavior"

            SettingsToggleRow {
                settingKey: "greeterRememberLastSession"
                tags: ["greeter", "session", "remember", "login"]
                text: I18n.tr("Remember last session")
                checked: SettingsData.greeterRememberLastSession
                onToggled: checked => SettingsData.set("greeterRememberLastSession", checked)
            }

            SettingsToggleRow {
                settingKey: "greeterRememberLastUser"
                tags: ["greeter", "user", "remember", "login", "username"]
                text: I18n.tr("Remember last user")
                checked: SettingsData.greeterRememberLastUser
                onToggled: checked => SettingsData.set("greeterRememberLastUser", checked)
            }

            SettingsToggleRow {
                settingKey: "greeterAutoLogin"
                tags: ["greeter", "autologin", "login", "startup", "password"]
                text: I18n.tr("Auto-login on startup")
                description: SettingsData.greeterRememberLastUser && SettingsData.greeterRememberLastSession ? I18n.tr("Skip the greeter password after boot until you sign out. Lock screen unlock is unchanged. Takes effect on the next reboot after sync.") : I18n.tr("Requires remembering the last user and session. Enable those options first.")
                checked: SettingsData.greeterAutoLogin
                enabled: SettingsData.greeterRememberLastUser && SettingsData.greeterRememberLastSession
                onToggled: checked => SettingsData.set("greeterAutoLogin", checked)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "tune"
            title: I18n.tr("Advanced")
            settingKey: "greeterAdvanced"
            tags: ["greeter", "login", "sync", "status", "repair"]
            collapsible: true
            expanded: false

            SettingsRow {
                iconName: "sync"
                title: I18n.tr("Run full sync", "greeter advanced action")
                subtitle: I18n.tr("Re-applies the greetd command, permissions and PAM authentication. Needs administrator access.", "greeter advanced action")
                clickable: true
                enabled: root.greeterBinaryExists && !root.busy
                onClicked: GreeterService.sync()
            }

            SettingsRow {
                iconName: "fact_check"
                title: I18n.tr("Check status", "greeter settings button, runs dms-greeter status")
                clickable: true
                enabled: root.greeterBinaryExists && !root.greeterStatusRunning
                onClicked: root.runGreeterStatus()
            }

            SettingsRow {
                iconName: "link_off"
                iconColor: Theme.error
                title: I18n.tr("Unlink login screen", "greeter advanced action")
                subtitle: I18n.tr("Stops syncing your DMS settings to the greeter. Set up links them again.", "greeter advanced action")
                visible: GreeterService.slotState !== ""
                clickable: true
                enabled: root.greeterBinaryExists && !root.busy
                onClicked: root.promptUnlink()
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "extension"
            title: I18n.tr("Dependencies & documentation")
            settingKey: "greeterDeps"

            SettingsRow {
                body: StyledText {
                    text: I18n.tr("Requires %1, %2, and your user in the %3 group (plus %4 for fingerprint, %5 for security keys).", "greeter requirements note, %1 and %2 are package names, %3 a group name, %4 and %5 PAM modules").arg("greetd").arg("dms-greeter").arg("greeter").arg("fprintd/pam_fprintd").arg("pam_u2f")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    width: parent.width
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignLeft
                }
            }

            SettingsRow {
                body: StyledText {
                    text: I18n.tr("Installation and PAM setup are documented in the %1.", "%1 is a link to the greeter docs").arg("<a href=\"" + Site.docs + "/dms-greeter/installation\" style=\"text-decoration:none; color:" + Theme.primary + ";\">" + I18n.tr("Dux Greeter docs", "link text") + "</a>")
                    textFormat: Text.RichText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    linkColor: Theme.primary
                    width: parent.width
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignLeft
                    onLinkActivated: url => Qt.openUrlExternally(url)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                        acceptedButtons: Qt.NoButton
                        propagateComposedEvents: true
                    }
                }
            }
        }

        SettingsFabBar {
            id: greeterFabs

            readonly property bool syncPending: SessionData.greeterSyncPending && GreeterService.binaryExists

            DFab {
                visible: greeterFabs.syncPending
                text: I18n.tr("Revert")
                iconName: "undo"
                colorRole: "secondaryContainer"
                enabled: !GreeterService.syncing
                onClicked: SettingsData.revertGreeterSyncPending()
            }

            DFab {
                visible: greeterFabs.syncPending
                text: GreeterService.syncing ? I18n.tr("Syncing...", "greeter settings status while sync is running") : I18n.tr("Apply changes")
                iconName: "check"
                colorRole: "primary"
                busy: GreeterService.syncing
                enabled: !root.busy
                onClicked: GreeterService.sync()
            }

            DFab {
                visible: !greeterFabs.syncPending
                text: I18n.tr("Edit widgets")
                iconName: "edit"
                colorRole: "secondaryContainer"
                onClicked: SessionService.greeterEditorRequested()
            }

            DFab {
                visible: !greeterFabs.syncPending && !SettingsData.greeterFollowLockScreen
                text: I18n.tr("Add widget")
                iconName: "add"
                onClicked: root.showWidgetBrowser()
            }
        }
    }
}
