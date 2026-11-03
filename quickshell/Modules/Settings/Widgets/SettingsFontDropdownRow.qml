pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Common as DCommon

SettingsDropdownRow {
    id: root

    property string currentFont: ""
    property string defaultFamily: Theme.defaultFontFamily
    signal fontSelected(string family)

    property var _families: ["Default"]
    property bool _enumerated: false

    function _enumerate() {
        if (_enumerated)
            return;
        _families = ["Default"].concat(DCommon.Fonts.selectableFamilies(root.defaultFamily));
        _enumerated = true;
    }

    enableFuzzySearch: true
    popupWidthOffset: SettingsMetrics.fontMenuExtraWidth
    options: _families
    currentValue: (root.currentFont === "" || root.currentFont === root.defaultFamily) ? "Default" : root.currentFont
    onValueChanged: value => root.fontSelected(value === "Default" ? "" : value)

    Component.onCompleted: Qt.callLater(_enumerate)
}
