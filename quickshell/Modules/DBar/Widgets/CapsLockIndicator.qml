import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets

BasePill {
    id: root

    opacity: DMSService.capsLockState ? 1 : 0

    states: [
        State {
            name: "hidden_horizontal"
            when: !DMSService.capsLockState && !isVerticalOrientation
            PropertyChanges {
                target: root
                width: 0
            }
        },
        State {
            name: "hidden_vertical"
            when: !DMSService.capsLockState && isVerticalOrientation
            PropertyChanges {
                target: root
                height: 0
            }
        }
    ]

    transitions: [
        Transition {
            NumberAnimation {
                properties: "width,height"
                duration: Theme.expressiveDurations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }
    ]

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
        }
    }

    content: Component {
        Item {
            implicitWidth: icon.width
            implicitHeight: root.contentThickness

            DIcon {
                id: icon
                anchors.centerIn: parent
                name: "shift_lock"
                size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: Theme.primary
            }
        }
    }
}
