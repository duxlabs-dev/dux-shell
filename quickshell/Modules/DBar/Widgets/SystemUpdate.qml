import QtQuick
import qs.Common
import qs.Modules.DBar
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets

BasePill {
    id: root

    property var widgetData: null
    property bool isActive: false

    readonly property bool hasUpdates: SystemUpdateService.updateCount > 0
    readonly property bool isChecking: SystemUpdateService.isChecking
    readonly property bool isClean: SystemUpdateService.sysupdateAvailable && !hasUpdates && !isChecking && !SystemUpdateService.hasError
    readonly property bool hideWhenIdle: widgetData?.hideWhenIdle === true
    readonly property bool shouldHide: hideWhenIdle && isClean

    width: shouldHide ? 0 : (isVerticalOrientation ? barThickness : visualWidth)
    height: shouldHide ? 0 : (isVerticalOrientation ? visualHeight : barThickness)
    visible: !shouldHide
    opacity: shouldHide ? 0 : 1

    Behavior on width {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Ref {
        service: SystemUpdateService
    }

    content: Component {
        Item {
            implicitWidth: root.isVerticalOrientation ? root.widgetThickness : updaterIcon.implicitWidth
            implicitHeight: root.widgetThickness

            DIcon {
                id: statusIcon
                anchors.centerIn: parent
                visible: root.isVerticalOrientation
                smoothTransform: root.isChecking
                name: {
                    if (root.isChecking)
                        return "refresh";
                    if (SystemUpdateService.hasError)
                        return "error";
                    if (root.hasUpdates)
                        return "system_update_alt";
                    return "check_circle";
                }
                size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: {
                    if (SystemUpdateService.hasError)
                        return Theme.error;
                    if (root.hasUpdates)
                        return Theme.primary;
                    return root.isActive ? Theme.primary : Theme.surfaceText;
                }

                RotationAnimator on rotation {
                    id: rotationAnimation
                    from: 0
                    to: 360
                    duration: Theme.expressiveDurations.extraLarge
                    loops: Animation.Infinite
                    running: root.isChecking && root.surfaceLive

                    onRunningChanged: {
                        if (!running)
                            statusIcon.rotation = 0;
                    }
                }
            }

            Rectangle {
                width: BarMetrics.badgeSize
                height: BarMetrics.badgeSize
                radius: Theme.cornerRadiusFull
                color: Theme.error
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: (barConfig?.widgetPadding ?? SettingsData.barWidgetPaddingDefault) === 0 ? 0 : BarMetrics.badgeInset
                anchors.topMargin: (barConfig?.widgetPadding ?? SettingsData.barWidgetPaddingDefault) === 0 ? 0 : BarMetrics.badgeInset
                visible: root.isVerticalOrientation && root.hasUpdates && !root.isChecking
            }

            Row {
                id: updaterIcon
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                visible: !root.isVerticalOrientation

                DIcon {
                    id: statusIconHorizontal
                    anchors.verticalCenter: parent.verticalCenter
                    smoothTransform: root.isChecking
                    name: {
                        if (root.isChecking)
                            return "refresh";
                        if (SystemUpdateService.hasError)
                            return "error";
                        if (root.hasUpdates)
                            return "system_update_alt";
                        return "check_circle";
                    }
                    size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: {
                        if (SystemUpdateService.hasError)
                            return Theme.error;
                        if (root.hasUpdates)
                            return Theme.primary;
                        return root.isActive ? Theme.primary : Theme.surfaceText;
                    }

                    RotationAnimator on rotation {
                        id: rotationAnimationHorizontal
                        from: 0
                        to: 360
                        duration: Theme.expressiveDurations.extraLarge
                        loops: Animation.Infinite
                        running: root.isChecking && root.surfaceLive

                        onRunningChanged: {
                            if (!running)
                                statusIconHorizontal.rotation = 0;
                        }
                    }
                }

                StyledText {
                    id: countText
                    anchors.verticalCenter: parent.verticalCenter
                    text: SystemUpdateService.updateCount.toString()
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: Theme.widgetTextColor
                    visible: root.hasUpdates && !root.isChecking
                }
            }
        }
    }

    MouseArea {
        z: 1
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.triggerRipple(this, mouse.x, mouse.y);
            root.positionPopout(popoutTarget);
            root.clicked();
        }
    }
}
