import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets
import "../../Services/BootEntries.js" as BootEntries

Item {
    id: root

    property bool onAc: true

    readonly property var timeoutValues: [0, 15, 30, 60, 120, 180, 300, 600, 900, 1200, 1800, 3600, 5400, 7200, 10800]
    readonly property var timeoutOptions: timeoutValues.map(seconds => seconds === 0 ? I18n.tr("Never", "timeout option meaning the action never happens") : I18n.duration(seconds))
    readonly property var gracePeriodValues: [1, 2, 3, 4, 5, 10, 15, 20, 30]
    readonly property var gracePeriodOptions: gracePeriodValues.map(seconds => I18n.duration(seconds))
    readonly property string managedNote: I18n.tr("Managed by administrator policy", "settings note: the administrator lock policy sets this value")

    function sourceKey(suffix) {
        return (onAc ? "ac" : "battery") + suffix;
    }

    function timeoutText(key) {
        const index = timeoutValues.indexOf(SettingsData[key]);
        return timeoutOptions[index >= 0 ? index : 0];
    }

    function setTimeoutFromText(key, text) {
        const index = timeoutOptions.indexOf(text);
        if (index < 0)
            return;
        SettingsData.set(key, timeoutValues[index]);
    }

    function gracePeriodText(key) {
        const index = gracePeriodValues.indexOf(SettingsData[key]);
        return gracePeriodOptions[index >= 0 ? index : 4];
    }

    function setGracePeriodFromText(key, text) {
        const index = gracePeriodOptions.indexOf(text);
        if (index < 0)
            return;
        SettingsData.set(key, gracePeriodValues[index]);
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width
            iconName: "schedule"
            title: I18n.tr("Idle", "noun, settings card title for idle timeout settings")
            settingKey: "idleSettings"

            SettingsButtonGroupRow {
                text: I18n.tr("Power source")
                visible: BatteryService.batteryAvailable
                model: [I18n.tr("AC power"), I18n.tr("Battery")]
                currentIndex: root.onAc ? 0 : 1
                checkEnabled: false
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    root.onAc = index === 0;
                }
            }

            SettingsDropdownRow {
                settingKey: "lockTimeout"
                tags: ["lock", "timeout", "idle", "automatic", "security"]
                text: I18n.tr("Automatically lock after")
                description: SettingsData.isManaged(root.sourceKey("LockTimeout")) ? root.managedNote : ""
                enabled: !SettingsData.isManaged(root.sourceKey("LockTimeout"))
                resetKeys: [root.sourceKey("LockTimeout")]
                options: root.timeoutOptions
                currentValue: root.timeoutText(root.sourceKey("LockTimeout"))
                onValueChanged: value => root.setTimeoutFromText(root.sourceKey("LockTimeout"), value)
            }

            SettingsDropdownRow {
                settingKey: "monitorTimeout"
                tags: ["monitor", "display", "screen", "timeout", "off", "idle"]
                text: I18n.tr("Turn off displays after")
                resetKeys: [root.sourceKey("MonitorTimeout")]
                options: root.timeoutOptions
                currentValue: root.timeoutText(root.sourceKey("MonitorTimeout"))
                onValueChanged: value => root.setTimeoutFromText(root.sourceKey("MonitorTimeout"), value)
            }

            SettingsDropdownRow {
                settingKey: "postLockMonitorTimeout"
                tags: ["monitor", "display", "screen", "timeout", "off", "lock", "after", "post"]
                text: I18n.tr("Turn off displays after lock")
                resetKeys: [root.sourceKey("PostLockMonitorTimeout")]
                options: root.timeoutOptions
                currentValue: root.timeoutText(root.sourceKey("PostLockMonitorTimeout"))
                onValueChanged: value => root.setTimeoutFromText(root.sourceKey("PostLockMonitorTimeout"), value)
            }

            SettingsDropdownRow {
                settingKey: "suspendTimeout"
                tags: ["suspend", "sleep", "timeout", "idle", "system"]
                text: I18n.tr("Suspend system after")
                resetKeys: [root.sourceKey("SuspendTimeout")]
                options: root.timeoutOptions
                currentValue: root.timeoutText(root.sourceKey("SuspendTimeout"))
                onValueChanged: value => root.setTimeoutFromText(root.sourceKey("SuspendTimeout"), value)
            }

            SettingsDropdownRow {
                settingKey: "suspendBehavior"
                tags: ["suspend", "hibernate", "sleep", "behavior"]
                visible: SessionService.hibernateSupported
                text: I18n.tr("Suspend behavior")
                resetKeys: [root.sourceKey("SuspendBehavior")]
                options: [I18n.tr("Suspend"), I18n.tr("Hibernate"), I18n.tr("Suspend then hibernate")]
                currentValue: options[SettingsData[root.sourceKey("SuspendBehavior")]] ?? options[0]
                onValueChanged: value => {
                    const index = options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set(root.sourceKey("SuspendBehavior"), index);
                }
            }

            SettingsToggleRow {
                settingKey: "lockBeforeSuspend"
                tags: ["lock", "suspend", "hibernate", "sleep", "security"]
                text: I18n.tr("Lock before suspend")
                description: SettingsData.isManaged("lockBeforeSuspend") ? root.managedNote : ""
                enabled: !SettingsData.isManaged("lockBeforeSuspend")
                checked: SettingsData.lockBeforeSuspend
                visible: SessionService.loginctlAvailable && SettingsData.loginctlLockIntegration
                onToggled: checked => SettingsData.set("lockBeforeSuspend", checked)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "gradient"
            title: I18n.tr("Fade")
            settingKey: "idleFade"
            tags: ["fade", "grace", "period", "lock", "dpms", "display"]

            SettingsToggleRow {
                settingKey: "fadeToLockEnabled"
                tags: ["fade", "lock", "screen", "idle", "grace period"]
                text: I18n.tr("Fade to lock screen")
                description: SettingsData.isManaged("fadeToLockEnabled") ? root.managedNote : I18n.tr("Fades the screen out first. Input during the fade cancels it", "idle fade toggle description")
                enabled: !SettingsData.isManaged("fadeToLockEnabled")
                checked: SettingsData.fadeToLockEnabled
                onToggled: checked => SettingsData.set("fadeToLockEnabled", checked)
            }

            SettingsDropdownRow {
                settingKey: "fadeToLockGracePeriod"
                tags: ["fade", "grace", "period", "timeout", "lock"]
                text: I18n.tr("Lock fade grace period")
                description: SettingsData.isManaged("fadeToLockGracePeriod") ? root.managedNote : ""
                enabled: !SettingsData.isManaged("fadeToLockGracePeriod")
                visible: SettingsData.fadeToLockEnabled
                options: root.gracePeriodOptions
                currentValue: root.gracePeriodText("fadeToLockGracePeriod")
                onValueChanged: value => root.setGracePeriodFromText("fadeToLockGracePeriod", value)
            }

            SettingsToggleRow {
                settingKey: "fadeToDpmsEnabled"
                tags: ["fade", "dpms", "monitor", "screen", "idle", "grace period"]
                text: I18n.tr("Fade to display off")
                description: I18n.tr("Fades the screen out first. Input during the fade cancels it", "idle fade toggle description")
                checked: SettingsData.fadeToDpmsEnabled
                onToggled: checked => SettingsData.set("fadeToDpmsEnabled", checked)
            }

            SettingsDropdownRow {
                settingKey: "fadeToDpmsGracePeriod"
                tags: ["fade", "grace", "period", "timeout", "dpms", "monitor"]
                text: I18n.tr("Display fade grace period")
                visible: SettingsData.fadeToDpmsEnabled
                options: root.gracePeriodOptions
                currentValue: root.gracePeriodText("fadeToDpmsGracePeriod")
                onValueChanged: value => root.setGracePeriodFromText("fadeToDpmsGracePeriod", value)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "tune"
            title: I18n.tr("Power menu")
            settingKey: "powerMenu"

            SettingsToggleRow {
                settingKey: "powerMenuGridLayout"
                tags: ["power", "menu", "grid", "layout", "list"]
                text: I18n.tr("Grid layout")
                checked: SettingsData.powerMenuGridLayout
                onToggled: checked => SettingsData.set("powerMenuGridLayout", checked)
            }

            SettingsDropdownRow {
                readonly property var actionValues: ["reboot", "logout", "poweroff", "lock", "suspend", "restart", "hibernate", "softreboot"]

                settingKey: "powerMenuDefaultAction"
                tags: ["power", "menu", "default", "action", "reboot", "logout", "shutdown"]
                text: I18n.tr("Default selected action")
                options: [I18n.tr("Reboot"), I18n.tr("Log out"), I18n.tr("Power off"), I18n.tr("Lock"), I18n.tr("Suspend"), I18n.tr("Restart DMS"), I18n.tr("Hibernate"), I18n.tr("Soft reboot")]
                currentValue: {
                    const index = actionValues.indexOf(SettingsData.powerMenuDefaultAction || "logout");
                    return index >= 0 ? options[index] : I18n.tr("Log out");
                }
                onValueChanged: value => {
                    const index = options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("powerMenuDefaultAction", actionValues[index]);
                }
            }

            Repeater {
                model: [
                    {
                        key: "reboot",
                        label: I18n.tr("Show reboot")
                    },
                    {
                        key: "logout",
                        label: I18n.tr("Show log out")
                    },
                    {
                        key: "poweroff",
                        label: I18n.tr("Show power off")
                    },
                    {
                        key: "lock",
                        label: I18n.tr("Show lock")
                    },
                    {
                        key: "suspend",
                        label: I18n.tr("Show suspend")
                    },
                    {
                        key: "restart",
                        label: I18n.tr("Show restart DMS")
                    },
                    {
                        key: "switchuser",
                        label: I18n.tr("Show switch user")
                    },
                    {
                        key: "hibernate",
                        label: I18n.tr("Show hibernate"),
                        hibernate: true
                    },
                    {
                        key: "softreboot",
                        label: I18n.tr("Show soft reboot"),
                        softreboot: true
                    }
                ]

                SettingsToggleRow {
                    required property var modelData

                    settingKey: "powerMenuAction_" + modelData.key
                    tags: ["power", "menu", "action", "show", modelData.key]
                    text: modelData.label
                    visible: {
                        if (modelData.hibernate)
                            return SessionService.hibernateSupported;
                        if (modelData.softreboot)
                            return SessionService.softRebootSupported;
                        return true;
                    }
                    checked: SettingsData.powerMenuActions.includes(modelData.key)
                    onToggled: checked => {
                        const others = SettingsData.powerMenuActions.filter(action => action !== modelData.key);
                        SettingsData.set("powerMenuActions", checked ? others.concat([modelData.key]) : others);
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "restart_alt"
            title: I18n.tr("Reboot targets", "settings card title, firmware setup and EFI boot entries the power menu can reboot into once")
            settingKey: "powerMenuBootEntries"
            tags: ["power", "menu", "reboot", "boot", "efi", "uefi", "bios", "firmware", "windows", "dual boot", "bootnext"]
            // Saved entries stay listed wherever this config lands, so they can always be removed
            visible: SessionService.firmwareSetupSupported || SettingsData.powerMenuBootEntries.length > 0 || (BootEntryService.status !== "unknown" && BootEntryService.status !== "noEfi")

            Component.onCompleted: BootEntryService.refresh()

            SettingsToggleRow {
                settingKey: "powerMenuFirmwareSetup"
                tags: ["power", "menu", "reboot", "firmware", "setup", "bios", "uefi"]
                visible: SessionService.firmwareSetupSupported
                iconName: "developer_board"
                text: I18n.tr("Firmware setup", "settings toggle, adds a power menu action that reboots into the UEFI/BIOS settings screen")
                checked: SettingsData.powerMenuFirmwareSetup
                onToggled: checked => SettingsData.set("powerMenuFirmwareSetup", checked)
            }

            SettingsRow {
                visible: BootEntryService.unavailableReason !== ""
                title: BootEntryService.unavailableReason
                titleColor: Theme.surfaceVariantText
            }

            SettingsRow {
                id: bootEntryPicker

                readonly property var options: BootEntries.pickerOptions(BootEntryService.entries, BootEntryService.currentId, SettingsData.powerMenuBootEntries)

                visible: BootEntryService.status === "ready"
                title: I18n.tr("Add entry", "settings row that adds an EFI boot entry to the power menu")

                DDropdown {
                    id: bootEntryDropdown
                    downKeyOpens: false
                    backgroundColor: SettingsMetrics.controlSurface
                    enabled: bootEntryPicker.options.length > 0
                    Accessible.name: bootEntryPicker.title
                    width: Math.min(dropdownWidth, bootEntryPicker.width - SettingsMetrics.rowPaddingH * 2)
                    options: bootEntryPicker.options.map(option => option.name)
                    emptyText: I18n.tr("Select", "verb, dropdown placeholder or option that opens a picker")
                    onValueChanged: value => {
                        const option = bootEntryPicker.options.find(option => option.name === value);
                        currentValue = "";
                        if (!option)
                            return;
                        SettingsData.set("powerMenuBootEntries", SettingsData.powerMenuBootEntries.concat([
                            {
                                id: option.id,
                                label: option.label
                            }
                        ]));
                    }
                }
            }

            Repeater {
                model: SettingsData.powerMenuBootEntries

                delegate: SettingsRow {
                    id: bootEntryRow

                    required property var modelData
                    required property int index

                    title: modelData.label
                    subtitle: "Boot" + modelData.id
                    iconName: "restart_alt"

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "delete"
                        iconColor: Theme.error
                        Accessible.name: I18n.tr("Remove", "verb, button that removes an item from a list")
                        onClicked: SettingsData.set("powerMenuBootEntries", SettingsData.powerMenuBootEntries.filter((entry, i) => i !== bootEntryRow.index))
                    }
                }
            }

            SettingsRow {
                visible: BootEntryService.status === "ready" && !SettingsData.powerMenuBootEntries.length
                title: I18n.tr("No items added yet", "empty list of saved EFI boot entries")
                titleColor: Theme.surfaceVariantText
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "check_circle"
            title: I18n.tr("Confirmation", "power settings card title, hold to confirm power actions")
            settingKey: "powerConfirmation"

            SettingsToggleRow {
                settingKey: "powerActionConfirm"
                tags: ["power", "confirm", "hold", "button", "safety"]
                text: I18n.tr("Hold to confirm")
                checked: SettingsData.powerActionConfirm
                onToggled: checked => SettingsData.set("powerActionConfirm", checked)
            }

            SettingsDropdownRow {
                readonly property var durationValues: [0.25, 0.5, 0.75, 1, 2, 3, 5, 10]

                enabled: SettingsData.powerActionConfirm
                settingKey: "powerActionHoldDuration"
                tags: ["power", "hold", "duration", "confirm", "time"]
                text: I18n.tr("Hold duration")
                options: durationValues.map(seconds => I18n.duration(seconds))
                currentValue: {
                    const index = durationValues.indexOf(SettingsData.powerActionHoldDuration);
                    return index >= 0 ? options[index] : I18n.duration(0.5);
                }
                onValueChanged: value => {
                    const index = options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("powerActionHoldDuration", durationValues[index]);
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "developer_mode"
            title: I18n.tr("Custom commands")
            settingKey: "customPowerActions"
            tags: ["lock", "logout", "suspend", "hibernate", "reboot", "poweroff", "power off", "shutdown", "command", "script", "override"]

            Repeater {
                model: [
                    {
                        key: "customPowerActionLock",
                        icon: "lock",
                        label: I18n.tr("Lock"),
                        placeholder: "/usr/bin/myLock.sh"
                    },
                    {
                        key: "customPowerActionLogout",
                        icon: "logout",
                        label: I18n.tr("Log out"),
                        placeholder: "/usr/bin/myLogout.sh"
                    },
                    {
                        key: "customPowerActionSuspend",
                        icon: "bedtime",
                        label: I18n.tr("Suspend"),
                        placeholder: "/usr/bin/mySuspend.sh"
                    },
                    {
                        key: "customPowerActionHibernate",
                        icon: "ac_unit",
                        label: I18n.tr("Hibernate"),
                        placeholder: "/usr/bin/myHibernate.sh"
                    },
                    {
                        key: "customPowerActionReboot",
                        icon: "restart_alt",
                        label: I18n.tr("Reboot"),
                        placeholder: "/usr/bin/myReboot.sh"
                    },
                    {
                        key: "customPowerActionPowerOff",
                        icon: "power_settings_new",
                        label: I18n.tr("Power off"),
                        placeholder: "/usr/bin/myPowerOff.sh"
                    }
                ]

                SettingsTextFieldRow {
                    required property var modelData

                    settingKey: modelData.key
                    tags: ["power", "command", "override", modelData.label]
                    text: modelData.label
                    leftIconName: modelData.icon
                    description: SettingsData.isManaged(modelData.key) ? root.managedNote : ""
                    enabled: !SettingsData.isManaged(modelData.key)
                    value: SettingsData[modelData.key] || ""
                    placeholderText: modelData.placeholder
                    onValueEdited: value => SettingsData.set(modelData.key, value.trim())
                }
            }
        }
    }
}
