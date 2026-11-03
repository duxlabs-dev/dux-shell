.pragma library

const secondsPerHour = 3600;
const weekLength = 7;
const monthLength = 30;
const retentionDays = 92;
const msPerDay = 86400000;

function dateKey(date) {
    const pad = n => String(n).padStart(2, "0");
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function parseKey(key) {
    const [year, month, day] = String(key).split("-").map(Number);
    return new Date(year, month - 1, day);
}

function emptyDay(key) {
    return {
        date: key,
        active: 0,
        apps: {}
    };
}

function byDate(days) {
    const map = {};
    for (const day of Array.isArray(days) ? days : []) {
        if (day && typeof day.date === "string")
            map[day.date] = day;
    }
    return map;
}

function addDays(date, count) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + count);
}

function weekStart(anchor, firstDayOfWeek) {
    return addDays(anchor, -((anchor.getDay() - firstDayOfWeek + weekLength) % weekLength));
}

function oldestWeekOffset(today, firstDayOfWeek) {
    const current = weekStart(today, firstDayOfWeek);
    const oldest = weekStart(addDays(today, 1 - retentionDays), firstDayOfWeek);
    return -Math.round((current - oldest) / (weekLength * msPerDay));
}

function weeksBack(days, today, firstDayOfWeek) {
    const count = 1 - oldestWeekOffset(today, firstDayOfWeek);
    const weeks = [];
    for (let i = 0; i < count; i++)
        weeks.push(weekDays(days, addDays(today, (i - count + 1) * weekLength), firstDayOfWeek, today));
    return weeks;
}

function weekDays(days, anchor, firstDayOfWeek, today) {
    const map = byDate(days);
    const todayKey = dateKey(today ?? anchor);
    const start = weekStart(anchor, firstDayOfWeek);
    const result = [];
    for (let i = 0; i < weekLength; i++) {
        const date = addDays(start, i);
        const key = dateKey(date);
        result.push({
            date: key,
            weekday: date.getDay(),
            active: map[key]?.active ?? 0,
            apps: map[key]?.apps ?? {},
            today: key === todayKey,
            future: key > todayKey
        });
    }
    return result;
}

function periodDays(days, anchor, firstDayOfWeek, period, today) {
    const anchorKey = dateKey(anchor);
    switch (period) {
    case "day":
        return weekDays(days, anchor, firstDayOfWeek, today).filter(day => day.date === anchorKey);
    case "week":
        return weekDays(days, anchor, firstDayOfWeek, today).filter(day => !day.future);
    default:
        return (Array.isArray(days) ? days : []).filter(day => day?.date <= anchorKey).slice(-monthLength);
    }
}

function totalSeconds(days) {
    return days.reduce((sum, day) => sum + (day?.active ?? 0), 0);
}

function topApps(days, limit) {
    const totals = {};
    for (const day of days) {
        const apps = day?.apps ?? {};
        for (const appId in apps) {
            if (apps[appId] > 0)
                totals[appId] = (totals[appId] ?? 0) + apps[appId];
        }
    }
    return Object.keys(totals).map(appId => ({
                appId,
                seconds: totals[appId]
            })).sort((a, b) => b.seconds - a.seconds || a.appId.localeCompare(b.appId)).slice(0, limit ?? Infinity);
}

function axisStepHours(hours) {
    if (hours <= 4)
        return 1;
    if (hours <= 8)
        return 2;
    if (hours <= 16)
        return 4;
    return 6;
}

function axis(peakSeconds) {
    const hours = Math.max(1, Math.ceil(peakSeconds / secondsPerHour));
    const step = axisStepHours(hours);
    const top = Math.ceil(hours / step) * step;
    const ticks = [];
    for (let hour = 0; hour <= top; hour += step)
        ticks.push(hour);
    return {
        top: top * secondsPerHour,
        ticks
    };
}

function monthDayFormat(shortDateFormat) {
    return String(shortDateFormat).replace(/[^A-Za-z]*y+[^A-Za-z]*/, "");
}

function splitDuration(seconds) {
    const total = Math.max(0, Math.round(seconds));
    return {
        hours: Math.floor(total / secondsPerHour),
        minutes: Math.floor((total % secondsPerHour) / 60)
    };
}
