import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.DCommon.Session

Item {
    id: root

    property var instanceData: null
    property var lockHost: null
    readonly property var cfg: instanceData?.config ?? ({})
    readonly property string shape: cfg.shape ?? "round"
    readonly property bool round: shape === "round"
    readonly property bool resizable: false
    readonly property real minWidth: implicitWidth
    readonly property real minHeight: implicitHeight

    implicitWidth: powerButton.width
    implicitHeight: powerButton.height

    DMaterialShape {
        anchors.fill: powerButton
        visible: !root.round
        shape: root.shape
        color: Theme.secondaryContainer
        scale: powerButton.pressed ? 0.9 : 1

        Behavior on scale {
            NumberAnimation {
                duration: LockMetrics.shakeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
            }
        }
    }

    LockActionButton {
        id: powerButton
        Accessible.name: I18n.tr("Power Options")
        iconName: "power_settings_new"
        iconColor: Theme.onSecondaryContainer
        backgroundColor: root.round ? Theme.secondaryContainer : "transparent"
        radius: pressed && Theme.shapeMorph ? Theme.cornerRadiusS : (Theme.pillControls ? Theme.fullRadius(width, height) : Math.min(Theme.cornerRadiusL, width / 2, height / 2))
        buttonSize: Theme.buttonHeightM
        onClicked: root.lockHost?.showPowerMenu()
    }
}
