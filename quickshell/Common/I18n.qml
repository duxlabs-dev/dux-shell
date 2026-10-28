pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("I18n")

    property string _resolvedLocale: "en"

    readonly property string _rawLocale: SessionData.locale === "" ? Qt.locale().name : SessionData.locale
    readonly property string _lang: _rawLocale.split(/[_-]/)[0]
    readonly property var _candidates: {
        const fullUnderscore = _rawLocale;
        const fullHyphen = _rawLocale.replace("_", "-");
        return [fullUnderscore, fullHyphen, _lang].filter(c => c && c !== "en");
    }

    readonly property var _rtlLanguages: ["ar", "he", "iw", "fa", "ur", "ps", "sd", "dv", "yi", "ku"]
    readonly property bool isRtl: _rtlLanguages.includes(_lang)

    readonly property url translationsFolder: Qt.resolvedUrl("../translations/poexports")
    readonly property url commonTranslationsFolder: Qt.resolvedUrl("../DCommon/translations/poexports")

    readonly property alias folder: dir.folder
    property var presentLocales: ({
            "en": Qt.locale("en")
        })
    property var translations: ({})
    property bool translationsLoaded: false
    property var commonTranslations: ({})
    property bool commonTranslationsLoaded: false
    property var pluginTranslations: ({})

    signal localeApplied

    property url _selectedPath: ""
    property url _commonSelectedPath: ""

    FolderListModel {
        id: dir
        folder: root.translationsFolder
        nameFilters: ["*.json"]
        showDirs: false
        showDotAndDotDot: false

        onStatusChanged: if (status === FolderListModel.Ready) {
            root._loadPresentLocales();
            root._pickTranslation();
        }
    }

    FolderListModel {
        id: commonDir
        folder: root.commonTranslationsFolder
        nameFilters: ["*.json"]
        showDirs: false
        showDotAndDotDot: false

        onStatusChanged: if (status === FolderListModel.Ready) {
            root._pickCommonTranslation();
        }
    }

    FileView {
        id: translationLoader
        path: root._selectedPath

        onLoaded: {
            try {
                root.translations = JSON.parse(text());
                root.translationsLoaded = true;
                log.info(`I18n: Loaded translations for '${root._resolvedLocale}' (${Object.keys(root.translations).length} contexts)`);
            } catch (e) {
                log.warn(`I18n: Error parsing '${root._resolvedLocale}':`, e, "- falling back to English");
                root._fallbackToEnglish();
            }
        }

        onLoadFailed: error => {
            log.warn(`I18n: Failed to load '${root._resolvedLocale}' (${error}), ` + "falling back to English");
            root._fallbackToEnglish();
        }
    }

    FileView {
        id: commonTranslationLoader
        path: root._commonSelectedPath
        printErrors: false

        onLoaded: {
            try {
                root.commonTranslations = JSON.parse(text());
                root.commonTranslationsLoaded = true;
                log.info(`I18n: Loaded DCommon translations (${Object.keys(root.commonTranslations).length} contexts)`);
            } catch (e) {
                log.warn("I18n: Error parsing DCommon translations:", e);
            }
        }
    }

    function locale() {
        if (SessionData.timeLocale)
            return Qt.locale(SessionData.timeLocale);
        return Qt.locale();
    }

    function _loadPresentLocales() {
        if (Object.keys(presentLocales).length > 1) {
            return; // already loaded
        }
        for (let i = 0; i < dir.count; i++) {
            const name = dir.get(i, "fileName"); // e.g. "zh_CN.json"
            if (name && name.endsWith(".json")) {
                const shortName = name.slice(0, -5);
                presentLocales[shortName] = Qt.locale(shortName);
            }
        }
    }

    function _pickTranslation() {
        for (let i = 0; i < _candidates.length; i++) {
            const cand = _candidates[i];
            if (presentLocales[cand] === undefined)
                continue;
            _resolvedLocale = cand;
            useLocale(cand, cand.startsWith("en") ? "" : translationsFolder + "/" + cand + ".json");
            return;
        }

        _resolvedLocale = "en";
        _fallbackToEnglish();
    }

    function useLocale(localeTag, fileUrl) {
        _resolvedLocale = localeTag || "en";
        _selectTranslationFile(fileUrl);
        log.info(`I18n: Using locale '${localeTag}' from ${fileUrl}`);
        if (commonDir.status === FolderListModel.Ready)
            _pickCommonTranslation();
        localeApplied();
    }

    function _selectTranslationFile(fileUrl) {
        const previousPath = String(_selectedPath);
        _selectedPath = fileUrl;
        if (translationsLoaded && String(_selectedPath) === previousPath)
            return;
        translationsLoaded = false;
        translations = ({});
    }

    function _fallbackToEnglish() {
        _resolvedLocale = "en";
        _selectedPath = "";
        translationsLoaded = false;
        translations = ({});
        log.warn("Falling back to built-in English strings");
        if (commonDir.status === FolderListModel.Ready)
            _pickCommonTranslation();
        localeApplied();
    }

    function localeCandidates() {
        return _candidates;
    }

    function registerPluginTranslations(pluginId, table) {
        if (!pluginId || !table)
            return;
        const next = Object.assign({}, pluginTranslations);
        next[pluginId] = table;
        pluginTranslations = next;
    }

    function unregisterPluginTranslations(pluginId) {
        if (!(pluginId in pluginTranslations))
            return;
        const next = Object.assign({}, pluginTranslations);
        delete next[pluginId];
        pluginTranslations = next;
    }

    function _pickCommonTranslation() {
        const present = {};
        for (let i = 0; i < commonDir.count; i++) {
            const name = commonDir.get(i, "fileName");
            if (name && name.endsWith(".json"))
                present[name.slice(0, -5)] = true;
        }
        const tag = _resolvedLocale || "en";
        const candidates = [tag, tag.replace("_", "-"), tag.split(/[_-]/)[0]].filter(c => c && c !== "en");
        for (let i = 0; i < candidates.length; i++) {
            if (!present[candidates[i]])
                continue;
            _commonSelectedPath = commonTranslationsFolder + "/" + candidates[i] + ".json";
            return;
        }
        _commonSelectedPath = "";
        commonTranslations = ({});
        commonTranslationsLoaded = false;
    }

    readonly property var _termIndexes: ({})

    onTranslationsChanged: delete _termIndexes["app"]
    onCommonTranslationsChanged: delete _termIndexes["common"]
    onPluginTranslationsChanged: {
        for (const catalog of Object.keys(_termIndexes)) {
            if (catalog.startsWith("plugin:"))
                delete _termIndexes[catalog];
        }
    }

    function _termIndex(catalog, table) {
        const cached = _termIndexes[catalog];
        if (cached)
            return cached;
        const index = {};
        for (const c in table) {
            const bucket = table[c];
            if (!bucket)
                continue;
            for (const term in bucket) {
                if (!index[term] && bucket[term])
                    index[term] = bucket[term];
            }
        }
        _termIndexes[catalog] = index;
        return index;
    }

    function _lookup(catalog, table, term, context) {
        if (!table)
            return "";
        if (context && table[context] && table[context][term])
            return table[context][term];
        if (table[term] && table[term][term])
            return table[term][term];
        return _termIndex(catalog, table)[term] || "";
    }

    // isRealContext is consumed by translations/extract_translations.py only:
    // pass a literal `true` (same line) to give (term, context) its own POEditor
    // translation slot. Lookup ignores it -- a real context exists as a bucket
    // in the export, a comment-only context does not.
    function tr(term, context, isRealContext) {
        if (translationsLoaded) {
            const hit = _lookup("app", translations, term, context);
            if (hit)
                return hit;
        }
        if (commonTranslationsLoaded) {
            const hit = _lookup("common", commonTranslations, term, context);
            if (hit)
                return hit;
        }
        return term;
    }

    function trFor(pluginId, term, context, isRealContext) {
        const table = pluginTranslations[pluginId];
        if (table) {
            const hit = _lookup("plugin:" + pluginId, table, term, context);
            if (hit)
                return hit;
        }
        return tr(term, context);
    }

    function duration(seconds) {
        if (seconds < 1)
            return I18n.tr("%1 ms", "duration in milliseconds, %1 is a number").arg(Math.round(seconds * 1000));
        const units = [[86400, I18n.tr("%1 day", "duration, singular, %1 is 1"), I18n.tr("%1 days", "duration, plural, %1 is a number"), I18n.tr("%1 days", "duration, 2 to 4 form (2, 3, 4, 22, 23, ...) for languages that need one, %1 is a number; leave empty to reuse the plural", true)], [3600, I18n.tr("%1 hour", "duration, singular, %1 is 1"), I18n.tr("%1 hours", "duration, plural, %1 is a number"), I18n.tr("%1 hours", "duration, 2 to 4 form (2, 3, 4, 22, 23, ...) for languages that need one, %1 is a number; leave empty to reuse the plural", true)], [60, I18n.tr("%1 minute", "duration, singular, %1 is 1"), I18n.tr("%1 minutes", "duration, plural, %1 is a number"), I18n.tr("%1 minutes", "duration, 2 to 4 form (2, 3, 4, 22, 23, ...) for languages that need one, %1 is a number; leave empty to reuse the plural", true)], [1, I18n.tr("%1 second", "duration, singular, %1 is 1"), I18n.tr("%1 seconds", "duration, plural, %1 is a number"), I18n.tr("%1 seconds", "duration, 2 to 4 form (2, 3, 4, 22, 23, ...) for languages that need one, %1 is a number; leave empty to reuse the plural", true)]];
        const parts = [];
        let rest = Math.round(seconds);
        for (const unit of units) {
            const count = Math.floor(rest / unit[0]);
            rest -= count * unit[0];
            if (count > 0)
                parts.push(unit[_durationForm(count)].arg(count));
        }
        return parts.join(" ");
    }

    // uk/ru/pl few rule; cs/sk treat 22-24 as plural, no duration here reaches them
    function _durationForm(count) {
        if (count === 1)
            return 1;
        const ones = count % 10;
        const tens = count % 100;
        if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14))
            return 3;
        return 2;
    }

    function trContext(context, term) {
        if (translationsLoaded && translations[context] && translations[context][term])
            return translations[context][term];
        if (commonTranslationsLoaded && commonTranslations[context] && commonTranslations[context][term])
            return commonTranslations[context][term];
        return term;
    }
}
