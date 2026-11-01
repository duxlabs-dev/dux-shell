import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var eventData: null
    property date initialDate: new Date()
    property var transientSurfaceTracker: null

    signal saved
    signal closeRequested

    property string fTitle: ""
    property bool fAllDay: false
    property date fDate: initialDate
    property int fStartHour: 10
    property int fStartMinute: 0
    property int fEndHour: 11
    property int fEndMinute: 0
    property string fLocation: ""
    property string fDescription: ""
    property string fCalendarId: ""
    property int fReminder: -1
    property string errorText: ""
    property bool saving: false

    readonly property var _cals: CalendarService.writableCalendars()
    readonly property var _remLabels: [I18n.tr("No reminder"), I18n.tr("At start"), I18n.tr("%1 before", "calendar reminder option, %1 is a duration such as 15 minutes").arg(I18n.duration(300)), I18n.tr("%1 before", "calendar reminder option, %1 is a duration such as 15 minutes").arg(I18n.duration(600)), I18n.tr("%1 before", "calendar reminder option, %1 is a duration such as 15 minutes").arg(I18n.duration(900)), I18n.tr("%1 before", "calendar reminder option, %1 is a duration such as 15 minutes").arg(I18n.duration(1800)), I18n.tr("1 hour before", "calendar reminder option"), I18n.tr("%1 before", "calendar reminder option, %1 is a duration such as 15 minutes").arg(I18n.duration(86400))]
    readonly property var _remMins: [-1, 0, 5, 10, 15, 30, 60, 1440]

    spacing: Theme.spacingM

    function _isoFromDateTime(dateObj, h, m) {
        const d = new Date(dateObj);
        d.setHours(h, m, 0, 0);
        return d.toISOString();
    }

    function _allDayIso(dateObj, dayOffset) {
        return new Date(Date.UTC(dateObj.getFullYear(), dateObj.getMonth(), dateObj.getDate() + dayOffset)).toISOString();
    }

    function _calendarName(id) {
        for (let i = 0; i < _cals.length; i++) {
            if (_cals[i].id === id)
                return _cals[i].name;
        }
        return _cals.length > 0 ? _cals[0].name : "";
    }

    function shiftDate(days) {
        const d = new Date(fDate);
        d.setDate(d.getDate() + days);
        fDate = d;
    }

    function save() {
        const title = fTitle.trim();
        if (!title) {
            errorText = I18n.tr("Title is required");
            return;
        }
        let calId = fCalendarId;
        if (!calId) {
            const def = CalendarService.defaultCalendar();
            calId = def ? def.id : "";
        }
        if (!calId) {
            errorText = I18n.tr("No writable calendar available");
            return;
        }
        let startIso, endIso;
        if (fAllDay) {
            startIso = _allDayIso(fDate, 0);
            endIso = _allDayIso(fDate, 1);
        } else {
            startIso = _isoFromDateTime(fDate, fStartHour, fStartMinute);
            endIso = _isoFromDateTime(fDate, fEndHour, fEndMinute);
            if (new Date(endIso).getTime() <= new Date(startIso).getTime()) {
                errorText = I18n.tr("End must be after start");
                return;
            }
        }
        const fields = {
            "calendarId": calId,
            "summary": title,
            "description": fDescription,
            "location": fLocation,
            "start": startIso,
            "end": endIso,
            "allDay": fAllDay,
            "reminders": fReminder >= 0 ? [
                {
                    "method": "popup",
                    "minutes": fReminder
                }
            ] : []
        };
        saving = true;
        errorText = "";
        const cb = response => {
            saving = false;
            if (response.error) {
                errorText = response.error;
                return;
            }
            root.saved();
        };
        if (eventData && eventData.id)
            CalendarService.updateEvent(eventData.id, fields, cb);
        else
            CalendarService.createEvent(fields, cb);
    }

    Component.onCompleted: {
        if (!eventData) {
            fCalendarId = CalendarService.defaultCalendar() ? CalendarService.defaultCalendar().id : "";
            return;
        }
        fTitle = eventData.title || "";
        fAllDay = !!eventData.allDay;
        fDate = eventData.start;
        fStartHour = eventData.start.getHours();
        fStartMinute = eventData.start.getMinutes();
        fEndHour = eventData.end.getHours();
        fEndMinute = eventData.end.getMinutes();
        fLocation = eventData.location || "";
        fDescription = eventData.description || "";
        fCalendarId = eventData.calendarId || "";
        if (eventData.reminders && eventData.reminders.length > 0)
            fReminder = eventData.reminders[0].minutes;
    }

    SettingsGroup {
        width: parent.width
        slotColor: Theme.chipSurface

        SettingsTextFieldRow {
            text: I18n.tr("Title")
            leftIconName: "title"
            placeholderText: I18n.tr("Event title")
            value: root.fTitle
            onValueEdited: value => root.fTitle = value
            onAccepted: root.save()
        }

        SettingsToggleRow {
            text: I18n.tr("All day")
            checked: root.fAllDay
            onToggled: checked => root.fAllDay = checked
        }

        SettingsRow {
            title: I18n.tr("Date")
            subtitle: Qt.formatDate(root.fDate, "ddd, MMM d yyyy")
            subtitleColor: Theme.surfaceText

            DActionButton {
                iconName: I18n.isRtl ? "chevron_right" : "chevron_left"
                Accessible.name: I18n.tr("Previous")
                onClicked: root.shiftDate(-1)
            }

            DActionButton {
                iconName: I18n.isRtl ? "chevron_left" : "chevron_right"
                Accessible.name: I18n.tr("Next")
                onClicked: root.shiftDate(1)
            }
        }

        SettingsTimeRow {
            visible: !root.fAllDay
            is24Hour: SettingsData.use24HourClock
            startTitle: I18n.tr("Start")
            startHour: root.fStartHour
            startMinute: root.fStartMinute
            endTitle: I18n.tr("End")
            endHour: root.fEndHour
            endMinute: root.fEndMinute
            onStartChanged: (hour, minute) => {
                root.fStartHour = hour;
                root.fStartMinute = minute;
            }
            onEndChanged: (hour, minute) => {
                root.fEndHour = hour;
                root.fEndMinute = minute;
            }
        }

        SettingsDropdownRow {
            text: I18n.tr("Calendar")
            transientSurfaceTracker: root.transientSurfaceTracker
            options: root._cals.map(c => c.name)
            currentValue: root._calendarName(root.fCalendarId)
            onValueChanged: value => {
                const cal = root._cals.find(c => c.name === value);
                if (cal)
                    root.fCalendarId = cal.id;
            }
        }

        SettingsDropdownRow {
            text: I18n.tr("Reminder", "noun, calendar event reminder time dropdown label")
            transientSurfaceTracker: root.transientSurfaceTracker
            options: root._remLabels
            currentValue: root._remLabels[Math.max(0, root._remMins.indexOf(root.fReminder))]
            onValueChanged: value => {
                const idx = root._remLabels.indexOf(value);
                if (idx >= 0)
                    root.fReminder = root._remMins[idx];
            }
        }

        SettingsTextFieldRow {
            text: I18n.tr("Location", "calendar event venue field label", true)
            leftIconName: "place"
            placeholderText: I18n.tr("Add location")
            value: root.fLocation
            onValueEdited: value => root.fLocation = value
        }

        SettingsTextFieldRow {
            text: I18n.tr("Notes", "noun, calendar event notes field label")
            leftIconName: "notes"
            placeholderText: I18n.tr("Add notes")
            value: root.fDescription
            onValueEdited: value => root.fDescription = value
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS
        layoutDirection: Qt.RightToLeft

        DButton {
            text: root.saving ? I18n.tr("Saving...") : I18n.tr("Save")
            iconName: "check"
            enabled: !root.saving
            onClicked: root.save()
        }

        DButton {
            text: I18n.tr("Cancel")
            backgroundColor: "transparent"
            textColor: Theme.primary
            onClicked: root.closeRequested()
        }
    }
}
