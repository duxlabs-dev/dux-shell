import QtQuick
import qs.Common
import qs.Modules.ControlCenter

CcTile {
    id: root

    readonly property string action: widgetData?.id ?? ""
    readonly property bool finishing: action === "edit" && (host?.editMode ?? false)

    toggle: false
    tooltips: !finishing
    iconName: finishing ? "check" : widgetDef?.icon ?? ""
    title: widgetDef?.text ?? ""
    restIconColor: action === "power" ? Theme.error : CcMetrics.tileInactiveIcon

    onClicked: {
        switch (action) {
        case "lock":
            host?.lockRequested();
            return;
        case "power":
            host?.powerRequested();
            return;
        case "settings":
            host?.settingsRequested();
            return;
        case "edit":
            host?.editRequested();
            return;
        }
    }
}
