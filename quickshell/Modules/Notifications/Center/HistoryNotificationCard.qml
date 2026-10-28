import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Notifications as Notifications

Notifications.NotificationCard {
    id: root
    required property var historyItem
    property bool isSelected: false
    property bool keyboardNavigationActive: false
    property bool nested: false

    surfaceColor: Theme.foregroundColor(nested ? Theme.chipSurface : Theme.cardSurface, Theme.isFloatingWindow(root))
    chipColor: nested ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerFocus) : Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))

    notificationData: ({
            appName: historyItem.appName || "",
            appIcon: historyItem.appIcon || "",
            desktopEntry: historyItem.desktopEntry || "",
            image: historyItem.image || "",
            summary: historyItem.summary || "",
            htmlBody: historyItem.htmlBody || historyItem.body || "",
            body: historyItem.body || "",
            urgency: historyItem.urgency,
            timeStr: formatHistoryTime(historyItem.timestamp),
            displayImage: NotificationService.notificationImageSource(historyItem.image || "", historyItem.appIcon || ""),
            hasDisplayImage: NotificationService.notificationHasImage(historyItem.image || ""),
            fallbackIconName: NotificationService.notificationFallbackIcon(historyItem.image || "", historyItem.appIcon || "")
        })
    descriptionExpanded: NotificationService.expandedMessages[(historyItem?.id || "") + "_hist"] || false
    keyboardSelected: isSelected && keyboardNavigationActive
    showActions: false
    onExpandRequested: NotificationService.toggleMessageExpansion((historyItem?.id || "") + "_hist")
    onBodyClicked: {
        if (canExpand)
            expandRequested();
    }
    onDismissRequested: NotificationService.removeFromHistory(historyItem.id)

    function formatHistoryTime(timestamp) {
        NotificationService.relativeTimeNow;
        NotificationService.clockFormatChanged;
        const now = new Date();
        const date = new Date(timestamp);
        const diff = now.getTime() - timestamp;
        const minutes = Math.floor(diff / 60000);
        const hours = Math.floor(minutes / 60);
        if (hours < 1) {
            if (minutes < 1)
                return I18n.tr("now", "relative timestamp for the current moment");
            return I18n.tr("%1m ago", "notification relative time, %1 is a number of minutes").arg(minutes);
        }
        const nowDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const itemDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        const daysDiff = Math.floor((nowDate - itemDate) / (1000 * 60 * 60 * 24));
        const timeStr = SettingsData.use24HourClock ? date.toLocaleTimeString(Qt.locale(), "HH:mm") : date.toLocaleTimeString(Qt.locale(), "h:mm AP");
        if (daysDiff === 0)
            return timeStr;
        try {
            const localeName = (typeof I18n !== "undefined" && I18n.locale) ? I18n.locale().name : "en-US";
            const weekday = date.toLocaleDateString(localeName, {
                weekday: "long"
            });
            return weekday + ", " + timeStr;
        } catch (e) {
            return timeStr;
        }
    }
}
