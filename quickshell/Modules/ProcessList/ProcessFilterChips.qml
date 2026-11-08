import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One view at a time: owner filters persist in CacheData; Online lists every connected process.
DFilterChips {
    readonly property var types: CacheData.processFilterTypes

    model: [I18n.tr("All"), I18n.tr("User", "noun, process filter and fallback display name"), I18n.tr("System"), I18n.tr("Online", "process filter: only processes with internet connections")]
    // A click replaces the currentIndex binding, so the shared filter is reapplied by hand.
    readonly property int filterIndex: ProcessListMetrics.onlineOnly ? 3 : types.length === 1 ? (types[0] === "user" ? 1 : 2) : 0
    currentIndex: filterIndex
    onFilterIndexChanged: currentIndex = filterIndex
    showCounts: false
    chipPadding: Theme.spacingM
    onSelectionChanged: index => {
        ProcessListMetrics.onlineOnly = index === 3;
        CacheData.set("processFilterTypes", index === 1 ? ["user"] : index === 2 ? ["system"] : ["user", "system"]);
    }
}
