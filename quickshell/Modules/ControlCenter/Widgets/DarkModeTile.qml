import QtQuick
import qs.Common

CcTile {
    id: root

    iconName: "contrast"
    iconRotation: SessionData.isLightMode ? 180 : 0
    title: {
        if (SettingsData.matugenSmartMode && Theme.currentTheme === Theme.dynamic)
            return SessionData.isLightMode ? I18n.tr("Auto (Light Mode)", "dark mode toggle label when matugen smart mode resolved light") : I18n.tr("Auto (Dark Mode)", "dark mode toggle label when matugen smart mode resolved dark");
        return I18n.tr("Dark mode");
    }
    active: !SessionData.isLightMode

    onClicked: {
        const newMode = !SessionData.isLightMode;
        Theme.screenTransition();
        Theme.setLightMode(newMode);
    }
    expandedContent: Component {
        CcTileActions {
            actions: [false, true].map(light => ({
                        text: light ? I18n.tr("Light", "adjective, light color mode, opposite of dark") : I18n.tr("Dark", "adjective, dark color mode, opposite of light"),
                        icon: light ? "light_mode" : "dark_mode",
                        active: light === SessionData.isLightMode,
                        trigger: () => {
                            if (light === SessionData.isLightMode)
                                return;
                            Theme.screenTransition();
                            Theme.setLightMode(light);
                        }
                    }))
        }
    }
}
