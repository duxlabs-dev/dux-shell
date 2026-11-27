import QtQuick
import qs.Common
import "../../../Common/Format.js" as Format

CcTile {
    id: root

    iconName: "do_not_disturb_on"
    title: I18n.tr("Do not disturb")
    subtitle: {
        if (!SessionData.doNotDisturb)
            return "";
        if (SessionData.doNotDisturbUntil <= 0)
            return I18n.tr("On");
        return I18n.tr("Until %1", "standalone tile status, %1 is a clock time").arg(Format.formatUntil(SessionData.doNotDisturbUntil, SettingsData.use24HourClock));
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
