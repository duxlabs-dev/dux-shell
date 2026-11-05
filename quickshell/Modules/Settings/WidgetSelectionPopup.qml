import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

WidgetPickerWindow {
    id: root

    property string targetSection: ""
    readonly property bool blurActive: Theme.blurLayersActive
    readonly property bool floatingForegroundLayers: Theme.floatingWindowForegroundLayers
    readonly property bool transparentBlurLayers: Theme.blurLayersActive && !floatingForegroundLayers
    readonly property real rowAlpha: blurActive ? Math.min(Theme.floatingWindowTransparency, transparentBlurLayers ? 0.12 : 0.52) : 0.30

    signal widgetSelected(string widgetId, string targetSection)

    function translateSection(section) {
        switch (section.toLowerCase()) {
        case "left":
            return I18n.tr("Left section");
        case "center":
            return I18n.tr("Center section");
        case "right":
            return I18n.tr("Right section");
        default:
            return section;
        }
    }

    objectName: "widgetSelectionPopup"
    title: I18n.tr("Add widget")
    headerTitle: I18n.tr("Add widget to %1", "widget picker header, %1 is the bar section name").arg(translateSection(targetSection))
    intro: I18n.tr("Select a widget to add. You can add multiple instances of the same widget if needed.")

    onWidgetChosen: widget => {
        if (widget.disabled)
            return;
        widgetSelected(widget.id, targetSection);
        hide();
    }

    onVisibleChanged: {
        if (visible)
            return;
        widgets = [];
        targetSection = "";
    }
}
