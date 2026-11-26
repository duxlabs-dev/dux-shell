import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../../Common/htmlElide.js" as HtmlElide

QtObject {
    id: root
    // null once the clicked notification closes; rule actions drop out with it
    property var notification: null
    readonly property string ruleAppName: notification?.ruleAppName ?? ""
    readonly property string desktopEntry: notification?.desktopEntry ?? ""
    readonly property string copyText: [notification?.summary, notification?.body].map(text => HtmlElide.stripHtmlTags((text || "").replace(/<br\s*\/?>/gi, "\n")).trim()).filter(text => text).join("\n")

    readonly property var items: {
        const list = notification ? [
            {
                icon: "tune",
                label: I18n.tr("Set notification rules"),
                action: "rules"
            }
        ] : [];
        if (root.copyText) {
            list.push({
                icon: "content_copy",
                label: I18n.tr("Copy"),
                action: "copy"
            });
        }
        return list;
    }

    function defaultAction(notification) {
        const actions = notification?.actions || [];
        return actions.find(action => action.identifier === "default") || actions[0] || null;
    }

    function trigger(action) {
        switch (action) {
        case "rules":
            SettingsData.requestNotificationRuleForNotification(ruleAppName, desktopEntry);
            PopoutService.openSettingsWithTab("notification_rules");
            return;
        case "copy":
            Quickshell.execDetached([Proc.dmsBin, "cl", "copy", copyText]);
            ToastService.showInfo(I18n.tr("Copied to clipboard"));
        }
    }
}
