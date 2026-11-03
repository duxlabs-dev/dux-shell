import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.DCommon.Session

// Settings preview of the greeter session picker. The greeter renders the real dropdown.
Item {
    id: root

    property var instanceData: null
    property var lockHost: null
    readonly property bool resizable: false
    readonly property real minWidth: implicitWidth
    readonly property real minHeight: implicitHeight
    readonly property string sessionName: CompositorService.displayName || I18n.tr("Session", "greeter session picker widget")

    implicitWidth: Math.max(Theme.fieldDefaultWidth, sessionMetrics.width + Theme.buttonHeightM + Theme.spacingXL)
    implicitHeight: LockMetrics.fieldHeight

    StyledTextMetrics {
        id: sessionMetrics
        text: root.sessionName
    }

    DDropdown {
        anchors.fill: parent
        text: ""
        description: ""
        backgroundColor: Theme.cardSurface
        hoverBackgroundColor: Theme.blend(Theme.cardSurface, Theme.onSurface, Theme.stateLayerHover)
        normalBorderColor: Theme.outlineMedium
        currentValue: root.sessionName
        options: [root.sessionName]
        popupWidthOffset: 0
        openUpwards: true
        alignPopupRight: true
    }
}
