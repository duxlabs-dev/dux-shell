import QtQuick
import qs.Common
import qs.Services
import "../../../Common/Format.js" as Format

CcTile {

    iconName: "local_cafe"
    title: SessionService.idleInhibited ? I18n.tr("Keeping Awake") : I18n.tr("Keep Awake")
    subtitle: {
        if (!SessionService.idleInhibited)
            return I18n.tr("Off");
        if (SessionData.idleInhibitedUntil <= 0)
            return I18n.tr("On");
        return I18n.tr("Until %1", "standalone tile status, %1 is a clock time").arg(Format.formatUntil(SessionData.idleInhibitedUntil, SettingsData.use24HourClock));
    }
    active: SessionService.idleInhibited || false
    showExpand: true

    onClicked: SessionService.toggleIdleInhibit(widgetData.durationMinutes)
    expandedContent: Component {
        CcDurationActions {
            onSelected: minutes => SessionService.enableIdleInhibit(minutes)
        }
    }
}
