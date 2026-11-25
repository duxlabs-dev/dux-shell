.pragma library

const secondsPerHour = 3600;
const weekLength = 7;
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

function weekEnding(days, end, today) {
    const map = byDate(days);
    const todayKey = dateKey(today);
    const result = [];
    for (let i = 1 - weekLength; i <= 0; i++) {
        const date = addDays(end, i);
        const key = dateKey(date);
        result.push({
            date: key,
            weekday: date.getDay(),
            active: map[key]?.active ?? 0,
            apps: map[key]?.apps ?? {},
            today: key === todayKey
        });
    }
    return result;
}

function weeksBack(days, today) {
    const count = Math.ceil(retentionDays / weekLength);
    const weeks = [];
    for (let i = 1 - count; i <= 0; i++)
        weeks.push(weekEnding(days, addDays(today, i * weekLength), today));
    return weeks;
}

function daysAgo(key, today) {
    return Math.round((addDays(today, 0) - parseKey(key)) / msPerDay);
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

function splitDuration(seconds) {
    const total = Math.max(0, Math.round(seconds));
    return {
        hours: Math.floor(total / secondsPerHour),
        minutes: Math.floor((total % secondsPerHour) / 60)
    };
}

const breakPlans = [
    {
        id: "light",
        interval: 20,
        duration: 20,
        beforeLong: 3,
        longDuration: 5,
        warning: 5
    },
    {
        id: "balanced",
        interval: 30,
        duration: 30,
        beforeLong: 2,
        longDuration: 10,
        warning: 10
    },
    {
        id: "focused",
        interval: 60,
        duration: 60,
        beforeLong: 1,
        longDuration: 15,
        warning: 15
    }
];
const breakPlanKeys = ["interval", "duration", "beforeLong", "longDuration", "warning"];

function matchingBreakPlan(config) {
    return breakPlans.find(plan => breakPlanKeys.every(key => plan[key] === config[key]))?.id ?? "";
}

function breakTotals(days) {
    const totals = {
        completed: 0,
        skipped: 0,
        snoozed: 0
    };
    for (const day of days) {
        totals.completed += day?.completed ?? 0;
        totals.skipped += day?.skipped ?? 0;
        totals.snoozed += day?.snoozed ?? 0;
    }
    totals.total = totals.completed + totals.skipped + totals.snoozed;
    totals.rate = totals.total > 0 ? Math.round(totals.completed / totals.total * 100) : -1;
    return totals;
}

function breakStats(days) {
    const list = Array.isArray(days) ? days : [];
    return {
        today: breakTotals(list.slice(-1)),
        week: breakTotals(list.slice(-weekLength)),
        all: breakTotals(list)
    };
}

function nextBreak(kind, shortsDone, beforeLong) {
    const done = kind === "long" ? 0 : shortsDone + 1;
    return {
        shortsDone: done,
        kind: done >= beforeLong ? "long" : "short"
    };
}
