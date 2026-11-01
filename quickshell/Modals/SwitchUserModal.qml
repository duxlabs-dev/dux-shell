import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets

DModal {
    id: root

    property bool lockOnSwitch: false

    function showFromPowerMenu() {
        root.lockOnSwitch = false;
        SessionsService.refresh();
        open();
    }

    function showFromLockScreen() {
        root.lockOnSwitch = true;
        SessionsService.refresh();
        open();
    }

    function _formatTty(s) {
        if (s.tty && s.tty.length > 0)
            return s.tty;
        if (s.seat && s.seat.length > 0)
            return s.seat;
        return I18n.tr("remote", "adjective, shown when a login session has no tty or seat");
    }

    function _formatType(s) {
        if (!s.type || s.type.length === 0)
            return "";
        switch (s.type) {
        case "wayland":
            return "Wayland";
        case "x11":
            return "X11";
        case "tty":
            return "TTY";
        default:
            return s.type.charAt(0).toUpperCase() + s.type.substring(1);
        }
    }

    function _doSwitch(sessionId, username) {
        if (root.lockOnSwitch && typeof SessionService !== "undefined" && SessionService.loginctlAvailable)
            SessionService.lock();
        SessionsService.activate(sessionId, null);
        close();
    }

    layerNamespace: "dms:switch-user-modal"
    shouldBeVisible: false
    allowStacking: true
    modalWidth: Math.min(Theme.dialogMaxWidth, screenWidth - Theme.spacingXL * 2)
    modalHeight: contentLoader.item ? Math.min(screenHeight - Theme.spacingXL * 2, contentLoader.item.implicitHeight) : 320
    enableShadow: true
    shouldHaveFocus: true
    onBackgroundClicked: close()

    Connections {
        target: SessionsService
        function onSwitchRequested() {
            root.showFromPowerMenu();
        }
    }

    content: DDialog {
        id: sessionDialog
        title: I18n.tr("Switch User")
        supportingText: SessionsService.otherSessions().length > 0 ? I18n.tr("Select an active session to switch to. The current session stays running in the background.") : ""
        acceptEnabled: false
        onRejected: root.close()

        Column {
            width: parent.width
            spacing: Theme.spacingS
            visible: SessionsService.otherSessions().length > 0

            Repeater {
                model: SessionsService.otherSessions()

                StyledButton {
                    id: sessionRow
                    required property var modelData
                    width: parent.width
                    height: Theme.listItemTwoLineHeight
                    radius: Theme.cornerRadiusL
                    color: Theme.secondaryContainer
                    Accessible.name: modelData.username
                    onClicked: root._doSwitch(modelData.sessionId, modelData.username)

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        DIcon {
                            name: "account_circle"
                            size: Theme.iconSize + 4
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - Theme.iconSize - 4 - chevron.width - Theme.spacingM * 2
                            spacing: Theme.spacingXXS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: sessionRow.modelData.username
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: {
                                    const tty = root._formatTty(sessionRow.modelData);
                                    const type = root._formatType(sessionRow.modelData);
                                    const parts = [];
                                    if (type)
                                        parts.push(type);
                                    parts.push(I18n.tr("session %1", "switch user list, %1 is the login session id").arg(sessionRow.modelData.sessionId));
                                    if (tty)
                                        parts.push(tty);
                                    return parts.join(" · ");
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }

                        DIcon {
                            id: chevron
                            name: I18n.isRtl ? "chevron_left" : "chevron_right"
                            size: Theme.iconSize
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    StateLayer {
                        control: sessionRow
                        stateColor: Theme.onSecondaryContainer
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingS
            visible: SessionsService.otherSessions().length === 0

            Rectangle {
                width: parent.width
                height: bodyCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadiusL
                color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
                border.width: Theme.layerOutlineWidth
                border.color: Theme.outlineMedium

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    DIcon {
                        name: "info"
                        size: Theme.iconSize
                        color: Theme.surfaceVariantText
                        anchors.top: parent.top
                        anchors.topMargin: 2
                    }

                    Column {
                        id: bodyCol
                        width: parent.width - Theme.iconSize - Theme.spacingM
                        spacing: Theme.spacingXS

                        StyledText {
                            text: I18n.tr("No other active sessions on this seat")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                        }

                        StyledText {
                            width: parent.width
                            text: I18n.tr("To sign in as a different user, log out and pick the account from the greeter. Creating a fresh session in parallel needs a multi-session greeter (%1).", "switch user note, %1 lists multi-session greeters").arg("greetd-flexiserver / GDM / LightDM")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        actions: [
            DButton {
                maximumWidth: sessionDialog.actionWidth
                wrapText: true
                text: I18n.tr("Close")
                backgroundColor: "transparent"
                textColor: Theme.primary
                onClicked: root.close()
            },
            DButton {
                maximumWidth: sessionDialog.actionWidth
                wrapText: true
                visible: SessionsService.otherSessions().length === 0 && !root.lockOnSwitch
                text: I18n.tr("Log out")
                iconName: "logout"
                onClicked: {
                    if (typeof SessionService !== "undefined")
                        SessionService.logout();
                    root.close();
                }
            }
        ]
    }
}
