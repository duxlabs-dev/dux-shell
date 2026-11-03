pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root
    readonly property var log: Log.scoped("CalendarKhalBackend")

    property bool enabled: false
    property bool _checked: false
    property bool installed: false
    property var eventsByDate: ({})
    property bool isLoading: false
    property string lastError: ""
    property date lastStartDate
    property date lastEndDate
    property string dateFormat: "MM/dd/yyyy"

    function checkAvailability() {
        if (_checked || !enabled)
            return;
        _checked = true;
        formatProcess.running = true;
    }

    onEnabledChanged: checkAvailability()

    function loadCurrentMonth() {
        let today = new Date();
        let firstDay = new Date(today.getFullYear(), today.getMonth(), 1);
        let lastDay = new Date(today.getFullYear(), today.getMonth() + 1, 0);
        let startDate = new Date(firstDay);
        startDate.setDate(startDate.getDate() - firstDay.getDay() - 7);
        let endDate = new Date(lastDay);
        endDate.setDate(endDate.getDate() + (6 - lastDay.getDay()) + 7);
        loadEvents(startDate, endDate);
    }

    function loadEvents(startDate, endDate) {
        if (!installed)
            return;
        if (eventsProcess.running)
            return;
        root.lastStartDate = startDate;
        root.lastEndDate = endDate;
        root.isLoading = true;
        let startDateStr = Qt.formatDate(startDate, root.dateFormat);
        let endDateStr = Qt.formatDate(endDate, root.dateFormat);
        eventsProcess.requestStartDate = startDate;
        eventsProcess.requestEndDate = endDate;
        eventsProcess.command = ["khal", "list", "--json", "title", "--json", "description", "--json", "start-date", "--json", "start-time", "--json", "end-date", "--json", "end-time", "--json", "all-day", "--json", "location", "--json", "url", startDateStr, endDateStr];
        eventsProcess.running = true;
    }

    function _parseDateFormat(formatExample) {
        return formatExample.replace("12", "MM").replace("21", "dd").replace("2013", "yyyy");
    }

    Component.onCompleted: checkAvailability()

    Process {
        id: formatProcess

        command: ["khal", "printformats"]
        running: false
        onExited: exitCode => {
            if (exitCode === 127)
                return;
            checkProcess.running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let lines = text.split('\n');
                for (let line of lines) {
                    if (!line.startsWith('dateformat:'))
                        continue;
                    let formatExample = line.substring(line.indexOf(':') + 1).trim();
                    root.dateFormat = root._parseDateFormat(formatExample);
                    break;
                }
            }
        }
    }

    Process {
        id: checkProcess

        command: ["khal", "list", "today"]
        running: false
        onExited: exitCode => {
            root.installed = (exitCode === 0);
            if (root.installed)
                root.loadCurrentMonth();
        }
    }

    Process {
        id: eventsProcess

        property date requestStartDate
        property date requestEndDate
        property string rawOutput: ""

        running: false
        onExited: exitCode => {
            root.isLoading = false;
            if (exitCode !== 0) {
                root.lastError = "Failed to load events (exit code: " + exitCode + ")";
                return;
            }
            try {
                let newEventsByDate = {};
                let lines = eventsProcess.rawOutput.split('\n');
                for (let line of lines) {
                    line = line.trim();
                    if (!line || line === "[]")
                        continue;

                    let dayEvents = JSON.parse(line);
                    for (let event of dayEvents) {
                        if (!event.title)
                            continue;

                        let startDate, endDate;
                        if (event['start-date'])
                            startDate = Date.fromLocaleString(I18n.locale(), event['start-date'], root.dateFormat);
                        else
                            startDate = new Date();
                        if (event['end-date'])
                            endDate = Date.fromLocaleString(I18n.locale(), event['end-date'], root.dateFormat);
                        else
                            endDate = new Date(startDate);

                        let startTime = new Date(startDate);
                        let endTime = new Date(endDate);
                        if (event['start-time'] && event['all-day'] !== "True") {
                            let timeStr = event['start-time'];
                            if (timeStr) {
                                let timeParts = timeStr.match(/(\d+):(\d+)(?::\d+)?\s*(AM|PM)?/i);
                                if (timeParts) {
                                    let hours = parseInt(timeParts[1]);
                                    let minutes = parseInt(timeParts[2]);
                                    if (timeParts[3]) {
                                        let period = timeParts[3].toUpperCase();
                                        if (period === 'PM' && hours !== 12)
                                            hours += 12;
                                        else if (period === 'AM' && hours === 12)
                                            hours = 0;
                                    }
                                    startTime.setHours(hours, minutes);
                                    if (event['end-time']) {
                                        let endTimeParts = event['end-time'].match(/(\d+):(\d+)(?::\d+)?\s*(AM|PM)?/i);
                                        if (endTimeParts) {
                                            let endHours = parseInt(endTimeParts[1]);
                                            let endMinutes = parseInt(endTimeParts[2]);
                                            if (endTimeParts[3]) {
                                                let endPeriod = endTimeParts[3].toUpperCase();
                                                if (endPeriod === 'PM' && endHours !== 12)
                                                    endHours += 12;
                                                else if (endPeriod === 'AM' && endHours === 12)
                                                    endHours = 0;
                                            }
                                            endTime.setHours(endHours, endMinutes);
                                        }
                                    } else {
                                        endTime = new Date(startTime);
                                        endTime.setHours(startTime.getHours() + 1);
                                    }
                                }
                            }
                        }
                        let eventId = event.title + "_" + event['start-date'] + "_" + (event['start-time'] || 'allday');
                        let extractedUrl = "";
                        if (!event.url && event.description) {
                            let urlMatch = event.description.match(/https?:\/\/[^\s]+/);
                            if (urlMatch)
                                extractedUrl = urlMatch[0];
                        }
                        let eventTemplate = {
                            "id": eventId,
                            "title": event.title || "Untitled Event",
                            "start": startTime,
                            "end": endTime,
                            "location": event.location || "",
                            "description": event.description || "",
                            "url": event.url || extractedUrl,
                            "calendar": "",
                            "color": "",
                            "allDay": event['all-day'] === "True",
                            "isMultiDay": startDate.toDateString() !== endDate.toDateString()
                        };
                        let currentDate = new Date(startDate);
                        while (currentDate <= endDate) {
                            let dateKey = Qt.formatDate(currentDate, "yyyy-MM-dd");
                            if (!newEventsByDate[dateKey])
                                newEventsByDate[dateKey] = [];

                            let existingEvent = newEventsByDate[dateKey].find(e => e.id === eventId);
                            if (existingEvent) {
                                currentDate.setDate(currentDate.getDate() + 1);
                                continue;
                            }
                            let dayEvent = Object.assign({}, eventTemplate);
                            if (currentDate.getTime() === startDate.getTime()) {
                                dayEvent.start = new Date(startTime);
                            } else {
                                dayEvent.start = new Date(currentDate);
                                if (!dayEvent.allDay)
                                    dayEvent.start.setHours(0, 0, 0, 0);
                            }
                            if (currentDate.getTime() === endDate.getTime()) {
                                dayEvent.end = new Date(endTime);
                            } else {
                                dayEvent.end = new Date(currentDate);
                                if (!dayEvent.allDay)
                                    dayEvent.end.setHours(23, 59, 59, 999);
                            }
                            newEventsByDate[dateKey].push(dayEvent);
                            currentDate.setDate(currentDate.getDate() + 1);
                        }
                    }
                }
                root.eventsByDate = newEventsByDate;
                root.lastError = "";
            } catch (error) {
                root.lastError = "Failed to parse events JSON: " + error.toString();
                root.eventsByDate = {};
            }
            eventsProcess.rawOutput = "";
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                eventsProcess.rawOutput += data + "\n";
            }
        }
    }
}
