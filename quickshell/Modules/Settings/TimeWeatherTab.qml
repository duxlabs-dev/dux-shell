import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    readonly property string _systemDefaultLabel: I18n.tr("System default")
    readonly property var presetDateFormats: ["ddd d", "ddd MMM d", "MMM d", "M/d", "d/M", "ddd d MMM yyyy", "yyyy-MM-dd", "dddd, MMMM d"]
    property bool editingBarFormat: false
    property bool editingLockFormat: false

    function isCustomFormat(format) {
        return !!format && !presetDateFormats.includes(format);
    }

    function weekStartQt() {
        if (SettingsData.firstDayOfWeek < 0 || SettingsData.firstDayOfWeek >= 7)
            return Qt.locale().firstDayOfWeek;
        return SettingsData.firstDayOfWeek;
    }

    function weekStartJs() {
        return weekStartQt() % 7;
    }

    function _dayNames() {
        // Local noon on Sunday 1 March 2026 onwards; a UTC midnight is the day before west of UTC.
        return Array(7).fill(0).map((_, i) => new Date(2026, 2, 1 + i, 12, 0, 0).toLocaleDateString(I18n.locale(), "dddd")).map(d => d[0].toUpperCase() + d.slice(1));
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            tab: "time"
            tags: ["time", "clock", "format", "24hour"]
            title: I18n.tr("Time")
            settingKey: "timeFormat"
            iconName: "schedule"

            SettingsDropdownRow {
                tab: "time"
                tags: ["time", "24hour", "12hour", "format", "locale"]
                settingKey: "clockFormat"
                text: I18n.tr("Format", "noun, time or date format setting label")
                readonly property var _sample: new Date(2000, 0, 1, 13, 0, 0)
                readonly property string _twelve: Qt.formatTime(_sample, "h:mm AP")
                readonly property string _twentyFour: Qt.formatTime(_sample, "HH:mm")
                options: [I18n.tr("System default"), _twelve, _twentyFour]
                currentValue: {
                    switch (SettingsData.clockFormat) {
                    case "12h":
                        return _twelve;
                    case "24h":
                        return _twentyFour;
                    default:
                        return I18n.tr("System default");
                    }
                }
                onValueChanged: value => {
                    if (value === _twelve) {
                        SettingsData.set("clockFormat", "12h");
                        return;
                    }
                    if (value === _twentyFour) {
                        SettingsData.set("clockFormat", "24h");
                        return;
                    }
                    SettingsData.set("clockFormat", "auto");
                }
            }

            SettingsToggleRow {
                tab: "time"
                tags: ["time", "seconds", "clock"]
                settingKey: "showSeconds"
                text: I18n.tr("Show seconds")
                checked: SettingsData.showSeconds
                onToggled: checked => SettingsData.set("showSeconds", checked)
            }

            SettingsToggleRow {
                enabled: !SettingsData.use24HourClock
                tab: "time"
                tags: ["time", "12hour", "format", "padding", "leading", "zero"]
                settingKey: "padHours12Hour"
                text: I18n.tr("Leading zero on hours")
                checked: SettingsData.padHours12Hour
                onToggled: checked => SettingsData.set("padHours12Hour", checked)
            }
        }

        SettingsCard {
            tab: "time"
            tags: ["date", "format", "calendar"]
            title: I18n.tr("Date")
            settingKey: "dateFormat"
            iconName: "calendar_today"

            SettingsToggleRow {
                tab: "time"
                tags: ["show", "week"]
                settingKey: "showWeekNumber"
                text: I18n.tr("Show week number")
                checked: SettingsData.showWeekNumber
                onToggled: checked => SettingsData.set("showWeekNumber", checked)
            }

            SettingsDropdownRow {
                tab: "time"
                tags: ["first", "day", "week"]
                settingKey: "firstDayOfWeek"
                text: I18n.tr("First day of week")
                options: [root._systemDefaultLabel].concat(root._dayNames())
                currentValue: {
                    if (SettingsData.firstDayOfWeek < 0 || SettingsData.firstDayOfWeek >= 7)
                        return root._systemDefaultLabel;
                    return root._dayNames()[root.weekStartJs()];
                }
                onValueChanged: value => {
                    if (value === root._systemDefaultLabel) {
                        SettingsData.set("firstDayOfWeek", -1);
                        return;
                    }
                    SettingsData.set("firstDayOfWeek", root._dayNames().indexOf(value));
                }
            }

            SettingsDropdownRow {
                tab: "time"
                tags: ["date", "format", "topbar"]
                settingKey: "clockDateFormat"
                text: I18n.tr("Bar format")
                description: I18n.tr("Preview: %1", "date format setting description, %1 is the current date formatted").arg(SettingsData.clockDateFormat ? new Date().toLocaleDateString(I18n.locale(), SettingsData.clockDateFormat) : new Date().toLocaleDateString(I18n.locale(), "ddd d"))
                options: [I18n.tr("System default", "date format option"), I18n.tr("Day date", "date format option"), I18n.tr("Day month date", "date format option"), I18n.tr("Month date", "date format option"), I18n.tr("Numeric (M/D)", "date format option"), I18n.tr("Numeric (D/M)", "date format option"), I18n.tr("Full with year", "date format option"), I18n.tr("ISO date", "date format option"), I18n.tr("Full day & month", "date format option"), I18n.tr("Custom", "date format option") + "…"]
                currentValue: {
                    if (!SettingsData.clockDateFormat || SettingsData.clockDateFormat.length === 0)
                        return I18n.tr("System default", "date format option");
                    const presets = [
                        {
                            "format": "ddd d",
                            "label": I18n.tr("Day date", "date format option")
                        },
                        {
                            "format": "ddd MMM d",
                            "label": I18n.tr("Day month date", "date format option")
                        },
                        {
                            "format": "MMM d",
                            "label": I18n.tr("Month date", "date format option")
                        },
                        {
                            "format": "M/d",
                            "label": I18n.tr("Numeric (M/D)", "date format option")
                        },
                        {
                            "format": "d/M",
                            "label": I18n.tr("Numeric (D/M)", "date format option")
                        },
                        {
                            "format": "ddd d MMM yyyy",
                            "label": I18n.tr("Full with year", "date format option")
                        },
                        {
                            "format": "yyyy-MM-dd",
                            "label": I18n.tr("ISO date", "date format option")
                        },
                        {
                            "format": "dddd, MMMM d",
                            "label": I18n.tr("Full day & month", "date format option")
                        }
                    ];
                    const match = presets.find(p => p.format === SettingsData.clockDateFormat);
                    return match ? match.label : I18n.tr("Custom") + ": " + SettingsData.clockDateFormat;
                }
                onValueChanged: value => {
                    const formatMap = {};
                    formatMap[I18n.tr("System default", "date format option")] = "";
                    formatMap[I18n.tr("Day date", "date format option")] = "ddd d";
                    formatMap[I18n.tr("Day month date", "date format option")] = "ddd MMM d";
                    formatMap[I18n.tr("Month date", "date format option")] = "MMM d";
                    formatMap[I18n.tr("Numeric (M/D)", "date format option")] = "M/d";
                    formatMap[I18n.tr("Numeric (D/M)", "date format option")] = "d/M";
                    formatMap[I18n.tr("Full with year", "date format option")] = "ddd d MMM yyyy";
                    formatMap[I18n.tr("ISO date", "date format option")] = "yyyy-MM-dd";
                    formatMap[I18n.tr("Full day & month", "date format option")] = "dddd, MMMM d";
                    root.editingBarFormat = value === I18n.tr("Custom", "date format option") + "…";
                    if (root.editingBarFormat)
                        return;
                    SettingsData.set("clockDateFormat", formatMap[value]);
                }
            }

            DTextField {
                id: customFormatInput
                outlined: true
                leftIconName: "calendar_today"
                labelText: I18n.tr("Format")
                visible: root.editingBarFormat || root.isCustomFormat(SettingsData.clockDateFormat)
                placeholderText: I18n.tr("Enter custom top bar format (e.g., ddd MMM d)")
                text: SettingsData.clockDateFormat
                onTextChanged: {
                    if (visible && text)
                        SettingsData.set("clockDateFormat", text);
                }
            }

            SettingsDropdownRow {
                tab: "time"
                tags: ["date", "format", "lock", "screen"]
                settingKey: "lockDateFormat"
                text: I18n.tr("Lock screen format")
                description: I18n.tr("Preview: %1").arg(SettingsData.lockDateFormat ? new Date().toLocaleDateString(I18n.locale(), SettingsData.lockDateFormat) : new Date().toLocaleDateString(I18n.locale(), Locale.LongFormat))
                options: [I18n.tr("System default", "date format option"), I18n.tr("Day date", "date format option"), I18n.tr("Day month date", "date format option"), I18n.tr("Month date", "date format option"), I18n.tr("Numeric (M/D)", "date format option"), I18n.tr("Numeric (D/M)", "date format option"), I18n.tr("Full with year", "date format option"), I18n.tr("ISO date", "date format option"), I18n.tr("Full day & month", "date format option"), I18n.tr("Custom", "date format option") + "…"]
                currentValue: {
                    if (!SettingsData.lockDateFormat || SettingsData.lockDateFormat.length === 0)
                        return I18n.tr("System default", "date format option");
                    const presets = [
                        {
                            "format": "ddd d",
                            "label": I18n.tr("Day date", "date format option")
                        },
                        {
                            "format": "ddd MMM d",
                            "label": I18n.tr("Day month date", "date format option")
                        },
                        {
                            "format": "MMM d",
                            "label": I18n.tr("Month date", "date format option")
                        },
                        {
                            "format": "M/d",
                            "label": I18n.tr("Numeric (M/D)", "date format option")
                        },
                        {
                            "format": "d/M",
                            "label": I18n.tr("Numeric (D/M)", "date format option")
                        },
                        {
                            "format": "ddd d MMM yyyy",
                            "label": I18n.tr("Full with year", "date format option")
                        },
                        {
                            "format": "yyyy-MM-dd",
                            "label": I18n.tr("ISO date", "date format option")
                        },
                        {
                            "format": "dddd, MMMM d",
                            "label": I18n.tr("Full day & month", "date format option")
                        }
                    ];
                    const match = presets.find(p => p.format === SettingsData.lockDateFormat);
                    return match ? match.label : I18n.tr("Custom") + ": " + SettingsData.lockDateFormat;
                }
                onValueChanged: value => {
                    const formatMap = {};
                    formatMap[I18n.tr("System default", "date format option")] = "";
                    formatMap[I18n.tr("Day date", "date format option")] = "ddd d";
                    formatMap[I18n.tr("Day month date", "date format option")] = "ddd MMM d";
                    formatMap[I18n.tr("Month date", "date format option")] = "MMM d";
                    formatMap[I18n.tr("Numeric (M/D)", "date format option")] = "M/d";
                    formatMap[I18n.tr("Numeric (D/M)", "date format option")] = "d/M";
                    formatMap[I18n.tr("Full with year", "date format option")] = "ddd d MMM yyyy";
                    formatMap[I18n.tr("ISO date", "date format option")] = "yyyy-MM-dd";
                    formatMap[I18n.tr("Full day & month", "date format option")] = "dddd, MMMM d";
                    root.editingLockFormat = value === I18n.tr("Custom", "date format option") + "…";
                    if (root.editingLockFormat)
                        return;
                    SettingsData.set("lockDateFormat", formatMap[value]);
                }
            }

            DTextField {
                id: customLockFormatInput
                outlined: true
                leftIconName: "calendar_today"
                labelText: I18n.tr("Format")
                visible: root.editingLockFormat || root.isCustomFormat(SettingsData.lockDateFormat)
                placeholderText: I18n.tr("Enter custom lock screen format (e.g., dddd, MMMM d)")
                text: SettingsData.lockDateFormat
                onTextChanged: {
                    if (visible && text)
                        SettingsData.set("lockDateFormat", text);
                }
            }

            SettingsRow {
                visible: customFormatInput.visible || customLockFormatInput.visible
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Format legend")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.primary
                        font.weight: Theme.fontWeightMedium
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingL

                        Column {
                            width: (parent.width - Theme.spacingL) / 2
                            spacing: Theme.spacingXXS

                            StyledText {
                                text: I18n.tr("• d - Day (1-31)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: I18n.tr("• dd - Day (01-31)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: I18n.tr("• ddd - Day name (Mon)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: I18n.tr("• dddd - Day name (Monday)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: I18n.tr("• M - Month (1-12)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }

                        Column {
                            width: (parent.width - Theme.spacingL) / 2
                            spacing: Theme.spacingXXS

                            StyledText {
                                text: I18n.tr("• MM - Month (01-12)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: I18n.tr("• MMM - Month (Jan)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: I18n.tr("• MMMM - Month (January)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: I18n.tr("• yy - Year (24)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: I18n.tr("• yyyy - Year (2024)")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            tab: "time"
            title: I18n.tr("Calendar")
            settingKey: "calendarSettings"
            iconName: "event"
            tags: ["calendar", "backend", "tasks", "events"]

            SettingsDropdownRow {
                tab: "time"
                tags: ["calendar", "backend", "daemon", "khal", "dankcalendar", "events"]
                settingKey: "calendarBackend"
                text: I18n.tr("Calendar backend")
                readonly property var _backendValues: ["auto", "khal", "dankcal"]
                readonly property var _backendLabels: [I18n.tr("Auto", "calendar backend option"), I18n.tr("khal", "calendar backend option"), I18n.tr("Dux Calendar", "calendar backend option")]
                options: _backendLabels
                currentValue: _backendLabels[Math.max(0, _backendValues.indexOf(SettingsData.calendarBackend))]
                onValueChanged: value => {
                    const idx = _backendLabels.indexOf(value);
                    if (idx < 0)
                        return;
                    SettingsData.set("calendarBackend", _backendValues[idx]);
                }
            }

            SettingsDropdownRow {
                tab: "time"
                tags: ["calendar", "tasks", "list", "default", "caldav", "todo"]
                settingKey: "defaultTaskCalendarId"
                visible: CalendarService.isDankActive && _taskLists.length > 0
                text: I18n.tr("Default task list")
                readonly property var _taskLists: (CalendarService.calendars || []).filter(c => c.holdsTasks && !c.readOnly && !c.hidden)
                readonly property var _labels: [I18n.tr("Auto")].concat(_taskLists.map(c => c.name))
                options: _labels
                currentValue: {
                    const idx = _taskLists.findIndex(c => c.id === SettingsData.defaultTaskCalendarId);
                    return idx >= 0 ? _labels[idx + 1] : I18n.tr("Auto");
                }
                onValueChanged: value => {
                    const idx = _labels.indexOf(value);
                    SettingsData.set("defaultTaskCalendarId", idx > 0 ? _taskLists[idx - 1].id : "");
                }
            }
        }

        SettingsCard {
            SettingsNavRow {
                tab: "time"
                settingKey: "weather"
                tags: ["weather", "location", "units"]
                title: I18n.tr("Weather")
                iconName: "partly_cloudy_day"
                onClicked: keyboard => root.parentModal?.navigateTo("weather", keyboard)
            }
        }
    }
}
