import QtQuick
import qs.Common

CcTile {
    id: root

    iconName: "do_not_disturb_on"
    title: I18n.tr("Do not disturb")
    subtitle: {
        if (!SessionData.doNotDisturb)
            return "";
        if (SessionData.doNotDisturbUntil <= 0)
            return I18n.tr("On");
        const d = new Date(SessionData.doNotDisturbUntil);
        return I18n.tr("Until %1", "standalone tile status, %1 is a clock time").arg(Qt.formatTime(d, SettingsData.use24HourClock ? "HH:mm" : "h:mm AP"));
    }
    active: SessionData.doNotDisturb
    showExpand: true

    onClicked: SessionData.setDoNotDisturb(!SessionData.doNotDisturb)
    expandedContent: Component {
        CcDurationActions {
            onSelected: minutes => SessionData.setDoNotDisturb(true, minutes)
        }
    }
}
