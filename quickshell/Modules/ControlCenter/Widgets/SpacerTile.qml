import QtQuick
import qs.Common

CcTile {
    toggle: false
    acceptsInput: false
    opacity: host?.editMode ? 1 : 0
    iconName: widgetDef?.icon ?? ""
    title: widgetDef?.text ?? ""
}
