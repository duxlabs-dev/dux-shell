pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property string statusText: ""
    property bool statusIsError: false
    property bool operationPending: false
    property string pendingUsername: ""
    property string pendingPassword: ""
    property string pendingConfirm: ""
    property bool pendingAdmin: false
    property bool pendingGreeter: false

    Component.onCompleted: UsersService.refresh()

    function _resetForm() {
        pendingUsername = "";
        pendingPassword = "";
        pendingConfirm = "";
        pendingAdmin = false;
        pendingGreeter = false;
        usernameField.text = "";
        passwordField.text = "";
        confirmField.text = "";
    }

    function _passwordsMatch() {
        return pendingPassword.length > 0 && pendingPassword === pendingConfirm;
    }

    function _createCanProceed() {
        return !operationPending && UsersService.isValidUsername(pendingUsername) && !UsersService.userExists(pendingUsername) && _passwordsMatch();
    }

    Connections {
        target: UsersService
        function onOperationCompleted(op, username, success, message) {
            root.operationPending = false;
            root.statusIsError = !success;
            if (success) {
                root.statusText = message + (username ? (" · " + username) : "");
                if (op === "create")
                    root._resetForm();
            } else {
                root.statusText = (username ? (username + ": ") : "") + message;
            }
        }
    }

    SettingsPage {
        SettingsRow {
            visible: !PolkitService.polkitAvailable
            subtitle: I18n.tr("Polkit integration is disabled. User management requires Polkit to elevate privileges.")
            subtitleColor: Theme.error
        }

        SettingsCard {
            width: parent.width
            iconName: "person_add"
            settingKey: "createUser"
            visible: PolkitService.polkitAvailable

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    DTextField {
                        id: usernameField
                        outlined: true
                        leftIconName: "person"
                        labelText: I18n.tr("Username")
                        width: parent.width
                        placeholderText: I18n.tr("e.g. alice")
                        isError: usernameInvalid

                        readonly property bool usernameInvalid: text.length > 0 && (!UsersService.isValidUsername(text) || UsersService.userExists(text))

                        onTextEdited: {
                            root.pendingUsername = text.trim();
                        }
                    }

                    StyledText {
                        width: parent.width
                        visible: usernameField.text.length > 0 && !UsersService.isValidUsername(usernameField.text)
                        text: I18n.tr("Username must start with a lowercase letter or underscore and contain only lowercase letters, digits, hyphens, or underscores.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        width: parent.width
                        visible: usernameField.text.length > 0 && UsersService.isValidUsername(usernameField.text) && UsersService.userExists(usernameField.text)
                        text: I18n.tr("A user with that name already exists.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error
                        wrapMode: Text.WordWrap
                    }
                }
            }

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    DTextField {
                        id: passwordField
                        outlined: true
                        leftIconName: "lock"
                        labelText: I18n.tr("Password")
                        width: parent.width
                        echoMode: TextInput.Password
                        showPasswordToggle: true
                        onTextEdited: root.pendingPassword = text
                    }
                }
            }

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    DTextField {
                        id: confirmField
                        outlined: true
                        leftIconName: "lock"
                        labelText: I18n.tr("Confirm password")
                        width: parent.width
                        echoMode: TextInput.Password
                        showPasswordToggle: true
                        isError: confirmMismatch

                        readonly property bool confirmMismatch: text.length > 0 && text !== passwordField.text

                        onTextEdited: root.pendingConfirm = text
                    }

                    StyledText {
                        width: parent.width
                        visible: confirmField.text.length > 0 && confirmField.text !== passwordField.text
                        text: I18n.tr("Passwords do not match.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error
                    }
                }
            }

            SettingsToggleRow {
                settingKey: "createUserAdmin"
                tags: ["user", "admin", "sudo", "wheel"]
                text: I18n.tr("Grant administrator privileges")
                description: I18n.tr("Adds them to the %1 group so they can use sudo", "create user admin toggle description, %1 is a group name").arg(UsersService.adminGroup)
                checked: root.pendingAdmin
                onToggled: checked => root.pendingAdmin = checked
            }

            SettingsToggleRow {
                settingKey: "createUserGreeter"
                tags: ["user", "greeter", "login", "sync"]
                text: I18n.tr("Allow greeter login access")
                description: I18n.tr("Adds them to the %1 group so they can run %2", "create user greeter toggle description, %1 is a group name, %2 a command").arg(UsersService.greeterGroup).arg("dms-greeter sync --profile")
                checked: root.pendingGreeter
                onToggled: checked => root.pendingGreeter = checked
            }

            SettingsRow {
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    DButton {
                        text: root.operationPending ? I18n.tr("Working...", "create user button text while the operation runs") : I18n.tr("Add user", "button and settings page title, creates a new user account")
                        iconName: "person_add"
                        backgroundColor: Theme.primary
                        textColor: Theme.primaryText
                        enabled: root._createCanProceed()
                        onClicked: {
                            if (!root._createCanProceed())
                                return;
                            root.operationPending = true;
                            root.statusText = "";
                            UsersService.createUser(root.pendingUsername, root.pendingPassword, root.pendingAdmin, root.pendingGreeter, null);
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.statusText
                        color: root.statusIsError ? Theme.error : Theme.primary
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        width: parent.width - parent.children[0].width - Theme.spacingM
                    }
                }
            }
        }
    }
}
