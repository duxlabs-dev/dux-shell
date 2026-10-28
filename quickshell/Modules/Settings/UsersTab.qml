pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    property string statusText: ""
    property bool statusIsError: false
    property bool operationPending: false

    Component.onCompleted: UsersService.refresh()

    Connections {
        target: UsersService
        function onOperationCompleted(op, username, success, message) {
            root.operationPending = false;
            root.statusIsError = !success;
            if (success) {
                root.statusText = message + (username ? (" · " + username) : "");
            } else {
                root.statusText = (username ? (username + ": ") : "") + message;
            }
        }
    }

    ConfirmModal {
        id: deleteUserConfirm
    }

    ConfirmModal {
        id: adminToggleConfirm
    }

    ConfirmModal {
        id: greeterToggleConfirm
    }

    SettingsPage {
        id: mainColumn

        SettingsRow {
            visible: root.statusText !== ""
            subtitle: root.statusText
            subtitleColor: root.statusIsError ? Theme.error : Theme.primary
        }

        StyledText {
            width: parent.width
            visible: !PolkitService.polkitAvailable
            text: I18n.tr("Polkit integration is disabled. User management requires Polkit to elevate privileges.")
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.error
            wrapMode: Text.WordWrap
        }

        SettingsCard {
            width: parent.width
            iconName: "group"
            settingKey: "usersList"
            visible: PolkitService.polkitAvailable

            SettingsRow {
                visible: UsersService.refreshing
                title: I18n.tr("Refreshing...", "status row while the user list reloads")
            }

            Repeater {
                model: UsersService.users

                SettingsRow {
                    id: userRow
                    required property var modelData

                    readonly property bool isLastAdmin: modelData.isAdmin && UsersService.adminMembers.length <= 1

                    settingKey: "userAccount_" + modelData.username
                    tags: ["user", "account", "admin", "login"]
                    iconName: "account_circle"
                    title: modelData.username
                    subtitle: [modelData.gecos || "", "UID " + modelData.uid].filter(Boolean).join(" · ")
                    trailingBadge: [modelData.isAdmin ? I18n.tr("admin", "noun, lowercase badge on a user account with admin rights") : "", modelData.isGreeter ? I18n.tr("Greeter") : ""].filter(Boolean).join(" · ")

                    Row {
                        id: actionButtons
                        spacing: Theme.spacingS

                        DActionButton {
                            id: greeterToggleBtn
                            readonly property bool actionBlocked: root.operationPending
                            buttonSize: Theme.iconButtonSize
                            iconSize: Theme.iconSizeMedium
                            iconName: userRow.modelData.isGreeter ? "login" : "how_to_reg"
                            iconColor: userRow.modelData.isGreeter ? Theme.secondary : Theme.surfaceVariantText
                            enabled: !actionBlocked
                            tooltipText: userRow.modelData.isGreeter ? I18n.tr("Remove greeter login access") : I18n.tr("Allow greeter login access")
                            tooltipSide: "left"
                            onClicked: {
                                if (actionBlocked)
                                    return;
                                const enableGreeter = !userRow.modelData.isGreeter;
                                greeterToggleConfirm.showWithOptions({
                                    title: enableGreeter ? I18n.tr("Allow greeter access?") : I18n.tr("Remove greeter access?"),
                                    message: enableGreeter ? I18n.tr("Add \"%1\" to the %2 group? They must log out and back in, then run %3 to publish their login-screen theme.", "confirm dialog message, %1 is the username, %2 is the group name, %3 a command").arg(userRow.modelData.username).arg(UsersService.greeterGroup).arg("dms-greeter sync --profile") : I18n.tr("Remove \"%1\" from the %2 group?").arg(userRow.modelData.username).arg(UsersService.greeterGroup),
                                    confirmText: enableGreeter ? I18n.tr("Allow", "verb, confirm button granting a user greeter access") : I18n.tr("Remove"),
                                    confirmColor: Theme.primary,
                                    onConfirm: () => {
                                        root.operationPending = true;
                                        root.statusText = "";
                                        UsersService.setGreeterAccess(userRow.modelData.username, enableGreeter, null);
                                    }
                                });
                            }
                        }

                        DActionButton {
                            id: adminToggleBtn
                            readonly property bool actionBlocked: root.operationPending || (userRow.isLastAdmin && userRow.modelData.isAdmin)
                            buttonSize: Theme.iconButtonSize
                            iconSize: Theme.iconSizeMedium
                            iconName: userRow.modelData.isAdmin ? "shield_person" : "shield"
                            iconColor: userRow.modelData.isAdmin ? Theme.primary : Theme.surfaceVariantText
                            enabled: !actionBlocked
                            tooltipText: (userRow.isLastAdmin && userRow.modelData.isAdmin) ? I18n.tr("Cannot remove the only administrator") : (userRow.modelData.isAdmin ? I18n.tr("Remove admin") : I18n.tr("Make admin"))
                            tooltipSide: "left"
                            onClicked: {
                                if (actionBlocked)
                                    return;
                                const makeAdmin = !userRow.modelData.isAdmin;
                                adminToggleConfirm.showWithOptions({
                                    title: makeAdmin ? I18n.tr("Make admin") : I18n.tr("Remove admin"),
                                    message: makeAdmin ? I18n.tr("Add \"%1\" to the %2 group?", "confirm dialog message, %1 is the username, %2 is the group name").arg(userRow.modelData.username).arg(UsersService.adminGroup) : I18n.tr("Remove \"%1\" from the %2 group?", "confirm dialog message, %1 is the username, %2 is the group name").arg(userRow.modelData.username).arg(UsersService.adminGroup),
                                    confirmText: makeAdmin ? I18n.tr("Grant", "verb, confirm button granting a user admin rights") : I18n.tr("Remove"),
                                    confirmColor: Theme.primary,
                                    onConfirm: () => {
                                        root.operationPending = true;
                                        root.statusText = "";
                                        UsersService.setAdmin(userRow.modelData.username, makeAdmin, null);
                                    }
                                });
                            }
                        }

                        DActionButton {
                            id: deleteBtn
                            readonly property bool actionBlocked: root.operationPending || !UsersService.canDelete(userRow.modelData.username)
                            buttonSize: Theme.iconButtonSize
                            iconSize: Theme.iconSizeMedium
                            iconName: "delete"
                            iconColor: Theme.error
                            enabled: !actionBlocked
                            tooltipText: userRow.isLastAdmin ? I18n.tr("Cannot delete the only administrator") : I18n.tr("Delete user")
                            tooltipSide: "left"
                            onClicked: {
                                if (actionBlocked)
                                    return;
                                deleteUserConfirm.showWithOptions({
                                    title: I18n.tr("Delete user"),
                                    message: I18n.tr("Delete \"%1\" and remove the home directory? This cannot be undone.", "confirm dialog message, %1 is the username").arg(userRow.modelData.username),
                                    confirmText: I18n.tr("Delete"),
                                    confirmColor: Theme.primary,
                                    onConfirm: () => {
                                        root.operationPending = true;
                                        root.statusText = "";
                                        UsersService.deleteUser(userRow.modelData.username, null);
                                    }
                                });
                            }
                        }
                    }
                }
            }

            SettingsRow {
                visible: UsersService.users.length === 0 && !UsersService.refreshing
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("No human user accounts found.")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }

        SettingsFabBar {
            shown: PolkitService.polkitAvailable

            DFab {
                text: I18n.tr("Add user", "button and settings page title, creates a new user account")
                iconName: "person_add"
                onClicked: keyboard => root.parentModal?.navigateTo("user_create", keyboard)
            }
        }
    }
}
