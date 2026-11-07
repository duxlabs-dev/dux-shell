import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

SettingsRow {
    id: root

    property string text: ""
    property string description: ""
    property string currentValue: ""
    property alias options: dropdown.options
    property alias optionValues: dropdown.optionValues
    property alias optionIcons: dropdown.optionIcons
    property alias optionImages: dropdown.optionImages
    property alias optionIconMap: dropdown.optionIconMap
    property alias optionColorMap: dropdown.optionColorMap
    property alias enableFuzzySearch: dropdown.enableFuzzySearch
    property alias popupWidthOffset: dropdown.popupWidthOffset
    property alias maxPopupHeight: dropdown.maxPopupHeight
    property alias openUpwards: dropdown.openUpwards
    property alias popupWidth: dropdown.popupWidth
    property alias alignPopupRight: dropdown.alignPopupRight
    property alias dropdownWidth: dropdown.dropdownWidth
    property alias emptyText: dropdown.emptyText
    property alias menuBlurEnabled: dropdown.menuBlurEnabled
    property alias transientSurfaceTracker: dropdown.transientSurfaceTracker
    property alias menuOpen: dropdown.menuOpen
    property bool addHorizontalPadding: true

    signal valueChanged(string value)

    function openDropdownMenu() {
        dropdown.openDropdownMenu();
    }

    function closeDropdownMenu() {
        dropdown.closeDropdownMenu();
    }

    title: text
    subtitle: description
    onCurrentValueChanged: dropdown.currentValue = currentValue

    DDropdown {
        id: dropdown
        downKeyOpens: false
        backgroundColor: SettingsMetrics.controlSurface
        enabled: root.enabled
        Accessible.name: root.text
        Accessible.description: root.description + (root.description ? " · " : "") + currentValue
        width: Math.min(dropdownWidth, root.width - SettingsMetrics.rowPaddingH * 2)
        Component.onCompleted: currentValue = root.currentValue
        onValueChanged: value => root.valueChanged(value)
    }
}
