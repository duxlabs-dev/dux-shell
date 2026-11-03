import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Item {
    id: localeTab

    readonly property string _systemDefaultLabel: I18n.tr("System default")

    function _localeDisplayName(localeCode) {
        if (!I18n.presentLocales[localeCode])
            return;
        const nativeName = I18n.presentLocales[localeCode].nativeLanguageName;
        return nativeName[0].toUpperCase() + nativeName.slice(1);
    }

    function _allLocaleOptions() {
        return [_systemDefaultLabel].concat(Object.keys(I18n.presentLocales).map(_localeDisplayName));
    }

    function _codeForDisplayName(displayName) {
        if (displayName === _systemDefaultLabel)
            return "";
        for (const code of Object.keys(I18n.presentLocales)) {
            if (_localeDisplayName(code) === displayName)
                return code;
        }
        return "";
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            tab: "locale"
            tags: ["locale", "language", "country"]
            title: I18n.tr("General")
            iconName: "language"

            SettingsDropdownRow {
                id: localeDropdown
                tab: "locale"
                tags: ["locale", "language", "country"]
                settingKey: "locale"
                text: I18n.tr("Language", "interface language dropdown label")
                options: localeTab._allLocaleOptions()
                enableFuzzySearch: true

                Component.onCompleted: {
                    currentValue = SessionData.locale ? localeTab._localeDisplayName(SessionData.locale) : localeTab._systemDefaultLabel;
                }

                onValueChanged: value => {
                    SessionData.set("locale", localeTab._codeForDisplayName(value));
                }
            }

            SettingsDropdownRow {
                id: timeLocaleDropdown
                tab: "locale"
                tags: ["locale", "time", "date", "format", "region"]
                settingKey: "timeLocale"
                text: I18n.tr("Time and date")
                options: localeTab._allLocaleOptions()
                enableFuzzySearch: true

                Component.onCompleted: {
                    currentValue = SessionData.timeLocale ? localeTab._localeDisplayName(SessionData.timeLocale) : localeTab._systemDefaultLabel;
                }

                onValueChanged: value => {
                    SessionData.set("timeLocale", localeTab._codeForDisplayName(value));
                }
            }
        }
    }
}
