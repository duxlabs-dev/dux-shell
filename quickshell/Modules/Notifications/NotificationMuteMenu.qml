import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

DContextMenu {
    id: root

    property alias notification: actions.notification
    readonly property string appName: notification?.appName ?? ""
    readonly property string ruleAppName: notification?.ruleAppName ?? ""
    readonly property string desktopEntry: notification?.desktopEntry ?? ""
    property bool canClear: false
    property bool blockArmed: false

    signal muted
    signal clearRequested

    minMenuWidth: NotificationMetrics.menuWidth
    onOpenStateChanged: {
        if (!openState) {
            blockArmed = false;
            durations.hide();
        }
    }
    menuItems: {
        const label = appName || I18n.tr("this app");
        const nowMs = NotificationService.notificationRuleNowMs;
        // Header actions only undo their own rules; a state set in the editor is changed there.
        const rulesItem = {
            type: "item",
            icon: "tune",
            text: I18n.tr("Set by a notification rule", "notification menu item, opens the rule that mutes or allows this app"),
            action: () => PopoutService.openSettingsWithTab("notification_rules")
        };
        const muteItems = SettingsData.hasOwnAppRule(ruleAppName, desktopEntry, "mute", false, nowMs) ? [
            {
                type: "item",
                icon: "notifications",
                text: I18n.tr("Unmute popups for %1", "notification menu action, %1 is the app name").arg(label),
                action: () => SettingsData.removeMuteRuleForApp(ruleAppName, desktopEntry)
            }
        ] : SettingsData.isAppMuted(ruleAppName, desktopEntry, nowMs) ? [rulesItem] : [
            {
                type: "item",
                icon: "notifications_off",
                text: I18n.tr("Mute Popups", "notification rule action option"),
                trailingIcon: I18n.isRtl ? "chevron_left" : "chevron_right",
                keepOpen: true,
                action: () => openDurations()
            }
        ];
        const ownDnd = SettingsData.hasOwnAppRule(ruleAppName, desktopEntry, "default", true, nowMs);
        const dndItem = !ownDnd && SettingsData.isAppDndBypassed(ruleAppName, desktopEntry) ? rulesItem : {
            type: "item",
            icon: "bedtime",
            text: ownDnd ? I18n.tr("Stop allowing %1 during Do Not Disturb", "notification menu action, %1 is the app name").arg(label) : I18n.tr("Allow %1 during Do Not Disturb", "notification menu action, %1 is the app name").arg(label),
            action: () => SettingsData.setAppDndBypass(ruleAppName, desktopEntry, !ownDnd)
        };
        return [
            ...muteItems,
            {
                type: "item",
                icon: "block",
                text: blockArmed ? I18n.tr("Click again to block %1", "notification header button, %1 is the app name").arg(label) : I18n.tr("Block %1", "notification header button, %1 is the app name").arg(label) + "…",
                keepOpen: !blockArmed,
                action: () => {
                    if (!blockArmed) {
                        blockArmed = true;
                        return;
                    }
                    SettingsData.addIgnoreRuleForApp(ruleAppName, desktopEntry);
                    hide();
                    muted();
                }
            },
            {
                type: "item",
                hidden: !canClear,
                icon: "cleaning_services",
                text: I18n.tr("Clear from history"),
                action: () => {
                    hide();
                    clearRequested();
                }
            },
            ...(muteItems[0] === rulesItem && dndItem === rulesItem ? [] : [dndItem]),
            {
                type: "separator"
            },
            ...actions.items.map(item => ({
                        type: "item",
                        icon: item.icon,
                        text: item.label,
                        action: () => actions.trigger(item.action)
                    }))
        ];
    }

    function openAt(anchor, popupSurface, x, y) {
        const window = anchor.QsWindow.window;
        const atPoint = x !== undefined;
        const px = atPoint ? x : 0;
        const py = atPoint ? y : anchor.height;
        // The popup band can be centred, anchored to neither edge, which screenPointOf reads as x = 0
        const local = popupSurface ? anchor.mapToItem(null, px, py) : null;
        const pos = local ? Qt.point(local.x + popupSurface.bandX, local.y + popupSurface.bandY) : QmlUtils.screenPointOf(window, anchor, px, py);
        if (!pos)
            return;
        open(window.screen, atPoint || I18n.isRtl ? pos.x : pos.x + anchor.width - effectiveMenuWidth, pos.y, false);
    }

    // Mirrors DContextMenu's on-screen clamp; the mute row is the first row, so the submenu shares the menu's top.
    function openDurations() {
        const x = Math.max(menuMargin, Math.min(contextWindow.width - effectiveMenuWidth - menuMargin, anchorX));
        const y = Math.max(menuMargin, Math.min(contextWindow.height - effectiveMenuHeight - menuMargin, anchorY));
        const fitsRight = x + effectiveMenuWidth + durations.effectiveMenuWidth <= contextWindow.width - menuMargin;
        const fitsLeft = x - durations.effectiveMenuWidth >= menuMargin;
        const toRight = I18n.isRtl ? fitsRight && !fitsLeft : fitsRight || !fitsLeft;
        durations.open(targetScreen, toRight ? x + effectiveMenuWidth : x - durations.effectiveMenuWidth, y, keyboardNavigation);
    }

    function mute(minutes) {
        SettingsData.addMuteRuleForApp(ruleAppName, desktopEntry, minutes > 0 ? Date.now() + minutes * 60 * 1000 : 0);
        hide();
        muted();
    }

    DContextMenu {
        id: durations

        property bool customOpen: false
        readonly property var customUnits: [
            {
                label: I18n.tr("D", "custom mute duration field, days", true),
                minutes: 24 * 60
            },
            {
                label: I18n.tr("H", "custom mute duration field, hours", true),
                minutes: 60
            },
            {
                label: I18n.tr("M", "custom mute duration field, minutes", true),
                minutes: 1
            }
        ]

        transientSurfaceTracker: root.transientSurfaceTracker
        minMenuWidth: NotificationMetrics.menuWidth
        // Keyboard focus only while the custom fields are open, so the plain menu never steals it.
        keyboardNavigable: customOpen
        // Its fullscreen backdrop covers the main menu, so any dismissal closes both.
        onOpenStateChanged: {
            if (!openState) {
                customOpen = false;
                root.hide();
            }
        }
        menuItems: [
            {
                type: "item",
                icon: "schedule",
                text: I18n.tr("For 1 hour", "timed preset menu option"),
                action: () => root.mute(60)
            },
            {
                type: "item",
                icon: "schedule",
                text: I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(14400)),
                action: () => root.mute(4 * 60)
            },
            {
                type: "item",
                icon: "notifications_off",
                text: I18n.tr("Forever"),
                action: () => root.mute(0)
            },
            {
                type: "separator"
            },
            {
                type: "item",
                icon: "tune",
                text: I18n.tr("Custom") + "…",
                keepOpen: true,
                action: () => durations.customOpen = true
            },
            {
                type: "component",
                hidden: !durations.customOpen,
                height: Theme.fieldHeight,
                component: customFields
            }
        ]

        Component {
            id: customFields

            // Takes clicks on labels and gaps, and keys the fields leave unhandled, before the menu backdrop and key
            // handler see them: Enter would activate the hovered row, Left would close, Up/Down move the highlight.
            MouseArea {
                id: fields
                // customOpen rebuilds menuItems, so the row is created already shown; focus once the menu's own
                // focus binding has settled on its key handler.
                Component.onCompleted: {
                    if (durations.customOpen)
                        Qt.callLater(() => units.itemAt(0)?.field.forceActiveFocus());
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        apply();
                    event.accepted = [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Left, Qt.Key_Up, Qt.Key_Down].includes(event.key);
                }

                function apply() {
                    let minutes = 0;
                    for (let i = 0; i < units.count; i++)
                        minutes += units.itemAt(i).minutes;
                    if (minutes > 0)
                        root.mute(minutes);
                }

                Row {
                    spacing: Theme.spacingXS
                    leftPadding: Theme.spacingS

                    Repeater {
                        id: units
                        model: durations.customUnits

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
                                    top: 999
                                }
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
                        onClicked: fields.apply()
                    }
                }
            }
        }
    }

    NotificationActions {
        id: actions
    }

    Timer {
        interval: 3000
        running: root.blockArmed
        onTriggered: root.blockArmed = false
    }

    Connections {
        target: PopoutManager

        function onPopoutOpening() {
            root.hide();
        }
    }
}
