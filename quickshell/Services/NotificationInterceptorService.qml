pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import "../Common/NotificationInterceptors.js" as Interceptors

Singleton {
    id: root

    property var entries: []
    property int revision: 0
    property int activitySequence: 0

    function register(source, id, priority, matcher, interceptor, label, description) {
        if (typeof priority === "function") {
            description = label;
            label = interceptor;
            interceptor = matcher;
            matcher = priority;
            priority = 0;
        }
        const next = Interceptors.register(entries, source, id, priority, matcher, interceptor, label, description);
        if (!next)
            return false;
        entries = next;
        revision++;
        return true;
    }

    function clearSource(source) {
        const next = entries.filter(entry => entry.source !== source);
        if (next.length === entries.length)
            return;
        entries = next;
        revision++;
    }

    function enabled(entry) {
        return SettingsData.getPluginSetting(entry.source, `notificationIntercept.${entry.id}.enabled`, true) !== false;
    }

    function priority(entry) {
        const value = Number(SettingsData.getPluginSetting(entry.source, `notificationIntercept.${entry.id}.priority`, entry.priority));
        return Number.isFinite(value) ? Math.max(-100, Math.min(100, value)) : entry.priority;
    }

    function setEnabled(source, id, value) {
        if (!entries.some(entry => entry.source === source && entry.id === id))
            return false;
        const key = `notificationIntercept.${id}.enabled`;
        if (value === true)
            SettingsData.removePluginSetting(source, key);
        else
            SettingsData.setPluginSetting(source, key, false);
        revision++;
        return true;
    }

    function setPriority(source, id, value) {
        if (!entries.some(entry => entry.source === source && entry.id === id))
            return false;
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return false;
        const next = Math.max(-100, Math.min(100, Math.round(numeric)));
        SettingsData.setPluginSetting(source, `notificationIntercept.${id}.priority`, next);
        revision++;
        return true;
    }

    function evaluate(info) {
        return Interceptors.evaluate(entries, info, priority, enabled);
    }
}
