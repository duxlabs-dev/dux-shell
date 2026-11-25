import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Row {
    id: root

    property var notification: null
    readonly property string appName: notification?.appName ?? ""
    readonly property string ruleAppName: notification?.ruleAppName ?? ""
    readonly property string desktopEntry: notification?.desktopEntry ?? ""
    property var transientSurfaceTracker: null
    property var popupSurface: null
    readonly property string appLabel: appName || I18n.tr("this app")

    signal closeRequested

    spacing: Theme.spacingXXS

    component Caption: StyledText {
        leftPadding: Theme.spacingM
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.onSurfaceVariant
    }

    DActionButton {
        id: blockButton
        property bool armed: false
        iconName: "block"
        buttonSize: NotificationMetrics.controlSize
        iconSize: Theme.iconSizeSmall
        iconColor: armed ? Theme.error : Theme.onSurfaceVariant
        backgroundColor: armed ? Theme.errorHover : "transparent"
        tooltipText: armed ? I18n.tr("Click again to block %1", "notification header button, %1 is the app name").arg(root.appLabel) : I18n.tr("Block %1", "notification header button, %1 is the app name").arg(root.appLabel)
        onClicked: {
            if (!armed) {
                armed = true;
                return;
            }
            armed = false;
            SettingsData.addIgnoreRuleForApp(root.ruleAppName, root.desktopEntry);
            root.closeRequested();
        }

        Timer {
            interval: 3000
            running: blockButton.armed
            onTriggered: blockButton.armed = false
        }
    }

    DActionButton {
        id: muteButton
        iconName: "notifications_off"
        buttonSize: NotificationMetrics.controlSize
        iconSize: Theme.iconSizeSmall
        tooltipText: I18n.tr("Mute %1…", "notification header button, %1 is the app name").arg(root.appLabel)
        onClicked: {
            muteMenuLoader.active = true;
            muteMenuLoader.item.openAt(muteButton, root.popupSurface);
        }
    }

    Loader {
        id: muteMenuLoader
        active: false
        visible: false

        sourceComponent: DContextMenu {
            id: menu

            property bool customOpen: false
            readonly property var customUnits: [
                {
                    label: I18n.tr("Min", "custom mute duration field, minutes"),
                    minutes: 1
                },
                {
                    label: I18n.tr("H", "custom mute duration field, hours"),
                    minutes: 60
                },
                {
                    label: I18n.tr("D", "custom mute duration field, days"),
                    minutes: 24 * 60
                }
            ]

            transientSurfaceTracker: root.transientSurfaceTracker
            layerNamespace: "dms:notification-mute-menu"
            minMenuWidth: NotificationMetrics.menuWidth
            // Keyboard focus only while the custom fields are open, so the plain menu never steals it.
            keyboardNavigable: customOpen
            onOpenStateChanged: {
                if (!openState)
                    customOpen = false;
            }
            menuItems: {
                const label = root.appLabel;
                const nowMs = NotificationService.notificationRuleNowMs;
                // Header actions only undo their own rules; a state set in the editor is changed there.
                const rulesItem = {
                    type: "item",
                    icon: "tune",
                    text: I18n.tr("Set by a notification rule", "notification menu item, opens the rule that mutes or allows this app"),
                    action: () => PopoutService.openSettingsWithTab("notification_rules")
                };
                const muteItems = SettingsData.hasOwnAppRule(root.ruleAppName, root.desktopEntry, "mute", false, nowMs) ? [
                    {
                        type: "item",
                        icon: "notifications",
                        text: I18n.tr("Unmute popups for %1", "notification menu action, %1 is the app name").arg(label),
                        action: () => SettingsData.removeMuteRuleForApp(root.ruleAppName, root.desktopEntry)
                    }
                ] : SettingsData.isAppMuted(root.ruleAppName, root.desktopEntry, nowMs) ? [rulesItem] : [
                    {
                        type: "item",
                        icon: "schedule",
                        text: I18n.tr("For 1 hour", "timed preset menu option"),
                        action: () => mute(60)
                    },
                    {
                        type: "item",
                        icon: "schedule",
                        text: I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(14400)),
                        action: () => mute(4 * 60)
                    },
                    {
                        type: "item",
                        icon: "notifications_off",
                        text: I18n.tr("Forever"),
                        action: () => mute(0)
                    },
                    {
                        type: "separator"
                    },
                    {
                        type: "item",
                        icon: "tune",
                        text: I18n.tr("Custom") + "…",
                        keepOpen: true,
                        action: () => customOpen = true
                    },
                    {
                        type: "component",
                        hidden: !customOpen,
                        height: Theme.fieldHeight,
                        component: customFields
                    }
                ];
                const ownDnd = SettingsData.hasOwnAppRule(root.ruleAppName, root.desktopEntry, "default", true, nowMs);
                const dndItem = !ownDnd && SettingsData.isAppDndBypassed(root.ruleAppName, root.desktopEntry) ? rulesItem : {
                    type: "item",
                    icon: "notifications_active",
                    text: ownDnd ? I18n.tr("Stop allowing %1 during Do Not Disturb", "notification menu action, %1 is the app name").arg(label) : I18n.tr("Allow %1 during Do Not Disturb", "notification menu action, %1 is the app name").arg(label),
                    action: () => SettingsData.setAppDndBypass(root.ruleAppName, root.desktopEntry, !ownDnd)
                };
                return [
                    {
                        type: "component",
                        height: Theme.buttonHeightXXS,
                        component: muteCaption
                    },
                    ...muteItems,
                    {
                        type: "separator"
                    },
                    {
                        type: "component",
                        height: Theme.buttonHeightXXS,
                        component: dndCaption
                    },
                    dndItem
                ];
            }

            function openAt(anchor, popupSurface) {
                const window = anchor.QsWindow.window;
                // The popup band can be centred, anchored to neither edge, which screenPointOf reads as x = 0
                const local = popupSurface ? anchor.mapToItem(null, 0, anchor.height) : null;
                const pos = local ? Qt.point(local.x + popupSurface.bandX, local.y + popupSurface.bandY) : QmlUtils.screenPointOf(window, anchor, 0, anchor.height);
                if (!pos)
                    return;
                open(window.screen, I18n.isRtl ? pos.x : pos.x + anchor.width - effectiveMenuWidth, pos.y, false);
            }

            function mute(minutes) {
                SettingsData.addMuteRuleForApp(root.ruleAppName, root.desktopEntry, minutes > 0 ? Date.now() + minutes * 60 * 1000 : 0);
                hide();
                root.closeRequested();
            }

            Component {
                id: muteCaption
                Caption {
                    text: I18n.tr("Mute Popups", "notification mute menu section label")
                }
            }

            Component {
                id: dndCaption
                Caption {
                    text: I18n.tr("Do not disturb", "notification mute menu section label")
                }
            }

            Component {
                id: customFields

                Row {
                    id: fieldsRow
                    readonly property bool shown: menu.customOpen
                    spacing: Theme.spacingXS
                    leftPadding: Theme.spacingS
                    onShownChanged: {
                        // After the menu's own focus binding has settled on its key handler.
                        if (shown)
                            Qt.callLater(() => units.itemAt(0)?.field.forceActiveFocus());
                    }

                    function apply() {
                        let minutes = 0;
                        for (let i = 0; i < units.count; i++)
                            minutes += units.itemAt(i).minutes;
                        if (minutes > 0)
                            menu.mute(minutes);
                    }

                    Repeater {
                        id: units
                        model: menu.customUnits

                        Row {
                            id: unit
                            required property var modelData
                            readonly property alias field: input
                            readonly property int minutes: (parseInt(input.text) || 0) * modelData.minutes
                            spacing: Theme.spacingXXS

                            DTextField {
                                id: input
                                width: Theme.buttonHeightS
                                validator: IntValidator {
                                    bottom: 0
                                }
                                onAccepted: fieldsRow.apply()
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: unit.modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.onSurfaceVariant
                            }
                        }
                    }

                    DButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("OK")
                        variant: "text"
                        minimumWidth: 0
                        horizontalPadding: NotificationMetrics.actionPadding
                        onClicked: fieldsRow.apply()
                    }
                }
            }
        }
    }
}
