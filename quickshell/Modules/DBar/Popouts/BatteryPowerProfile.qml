pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.DCommon.Common as DCommon

DCard {
    id: root

    property bool active: false
    property bool showHeading: true
    property bool framed: true

    readonly property string style: SettingsData.batteryPopoutPowerStyle
    readonly property bool slider: style === "slider"
    readonly property var profiles: PowerProfileWatcher.availableProfiles
    readonly property int currentIndex: profiles.indexOf(PowerProfileWatcher.currentProfile)
    readonly property int focusIndex: Math.max(0, Math.min(currentIndex, profiles.length - 1))
    // Off until the first layout has settled, so nothing slides in when the popout opens
    property bool settled: false
    readonly property bool animate: active && settled && !Theme.reduceMotion

    function choose(index) {
        const profile = profiles[index];
        if (profile === undefined || PowerProfileWatcher.applyProfile(profile))
            return;
        ToastService.showError(I18n.tr("Failed to set power profile"));
    }

    function stepWithArrows(event, repeater) {
        const count = profiles.length;
        if (!enabled || (event.modifiers & ~Qt.KeypadModifier) !== Qt.NoModifier || count === 0)
            return;
        const forward = I18n.isRtl ? Qt.Key_Left : Qt.Key_Right;
        const backward = I18n.isRtl ? Qt.Key_Right : Qt.Key_Left;
        if (event.key !== forward && event.key !== backward)
            return;
        let from = focusIndex;
        for (let i = 0; i < count; i++) {
            if (repeater.itemAt(i)?.activeFocus)
                from = i;
        }
        const next = (from + (event.key === forward ? 1 : count - 1)) % count;
        repeater.itemAt(next)?.forceActiveFocus(Qt.TabFocusReason);
        choose(next);
        event.accepted = true;
    }

    component SpatialAnim: NumberAnimation {
        duration: Theme.expressiveDurations.expressiveFastSpatial
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
    }

    component EffectsAnim: DCommon.DColorAnim {}

    width: parent?.width ?? 0
    height: body.implicitHeight + pad * 2
    pad: framed ? BatteryPopoutMetrics.pad : 0
    restRadius: Theme.cornerRadiusL
    color: framed ? surfaceColor : "transparent"
    border.width: framed ? Theme.layerOutlineWidth : 0
    visible: PowerProfileWatcher.available
    enabled: PowerProfileWatcher.available
    Component.onCompleted: Qt.callLater(() => settled = true)

    Column {
        id: body
        width: parent.width
        spacing: BatteryPopoutMetrics.gap

        Item {
            visible: root.showHeading
            width: parent.width
            height: Math.max(headerLabel.implicitHeight, chip.visible ? chip.height : 0)

            StyledText {
                id: headerLabel
                anchors.left: parent.left
                anchors.right: chip.visible ? chip.left : parent.right
                anchors.rightMargin: chip.visible ? Theme.spacingS : 0
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Power profile")
                font.pixelSize: root.slider ? Theme.fontSizeMedium : Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: root.slider ? Theme.surfaceText : Theme.primary
                elide: Text.ElideRight
            }

            DDetailChip {
                id: chip
                readonly property bool saver: root.profiles[root.currentIndex] === PowerProfile.PowerSaver
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.slider && root.currentIndex >= 0
                value: Theme.getPowerProfileLabel(root.profiles[root.currentIndex])
                color: saver ? Theme.tertiaryContainer : Theme.primaryContainer
                valueColor: saver ? Theme.onTertiaryContainer : Theme.onPrimaryContainer
                border.width: 0
                radius: height / 2
            }
        }

        Loader {
            width: parent.width
            sourceComponent: root.style === "circle" ? circleComp : (root.slider ? sliderComp : groupComp)
        }
    }

    Component {
        id: groupComp

        DButtonGroup {
            readonly property bool buttons: root.style === "buttons"

            fillWidth: true
            buttonHeight: BatteryPopoutMetrics.button
            checkEnabled: false
            selectedColor: Theme.primary
            selectedContentColor: Theme.onPrimary
            optionIconSize: BatteryPopoutMetrics.compactIconSize
            textSize: buttons ? Theme.fontSizeMedium : Theme.fontSizeSmall
            labelOnlySelected: buttons
            selectedWidthShare: buttons ? BatteryPopoutMetrics.selectedShare : 1
            pressedWidthShare: buttons ? BatteryPopoutMetrics.pressedShare : 1
            model: root.profiles.map(profile => ({
                        "text": Theme.getPowerProfileLabel(profile),
                        "icon": Theme.getPowerProfileIcon(profile),
                        "filled": Theme.powerProfileIconFilled(profile)
                    }))
            currentIndex: root.currentIndex
            Accessible.role: Accessible.Grouping
            Accessible.name: I18n.tr("Power profile")
            onSelectionChanged: (index, selected) => {
                if (selected)
                    root.choose(index);
            }
        }
    }

    Component {
        id: circleComp

        Row {
            id: circles

            Accessible.role: Accessible.Grouping
            Accessible.name: I18n.tr("Power profile")
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true
            Keys.onPressed: event => root.stepWithArrows(event, circleRepeater)

            Repeater {
                id: circleRepeater
                model: root.profiles

                StyledButton {
                    id: cell

                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.currentIndex
                    readonly property string iconName: Theme.getPowerProfileIcon(modelData)
                    readonly property color iconColor: selected ? Theme.onPrimary : Theme.onSurfaceVariant

                    width: circles.width / Math.max(1, root.profiles.length)
                    height: face.height + Theme.spacingXS + cellLabel.implicitHeight
                    focusPolicy: activeFocus || index === root.focusIndex ? Qt.StrongFocus : Qt.ClickFocus
                    checkable: true
                    checked: selected
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: cellLabel.text
                    onClicked: root.choose(index)
                    onSelectedChanged: {
                        if (selected && root.animate)
                            cookiePop.restart();
                    }

                    Item {
                        id: face
                        width: BatteryPopoutMetrics.powerButton
                        height: face.width
                        x: (cell.width - width) / 2
                        scale: cell.pressed ? BatteryPopoutMetrics.circlePressScale : 1

                        Behavior on scale {
                            enabled: root.animate
                            SpatialAnim {}
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingXS
                            visible: !cell.selected
                            radius: width / 2
                            color: cell.hovered ? Theme.chipSurfaceNested : Theme.chipSurface

                            Behavior on color {
                                enabled: root.animate
                                EffectsAnim {}
                            }
                        }

                        DMaterialShape {
                            id: cookie
                            anchors.fill: parent
                            visible: cell.selected
                            shape: "cookie9"
                            color: Theme.primary
                            layer.enabled: visible
                            layer.smooth: true
                            layer.mipmap: true
                            layer.textureSize: Qt.size(Math.ceil(width * BatteryPopoutMetrics.shapeSupersampling), Math.ceil(height * BatteryPopoutMetrics.shapeSupersampling))

                            ParallelAnimation {
                                id: cookiePop
                                SpatialAnim {
                                    target: cookie
                                    property: "scale"
                                    from: BatteryPopoutMetrics.popScale
                                    to: 1
                                }
                                SpatialAnim {
                                    target: cookie
                                    property: "rotation"
                                    from: BatteryPopoutMetrics.popRotation
                                    to: 0
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"

                            FocusRing {
                                visible: cell.visualFocus
                            }
                        }

                        DIcon {
                            anchors.centerIn: parent
                            name: cell.iconName
                            size: Theme.iconSize
                            color: cell.iconColor
                            filled: cell.selected && Theme.powerProfileIconFilled(cell.modelData)

                            Behavior on color {
                                enabled: root.animate
                                EffectsAnim {}
                            }
                        }
                    }

                    StyledText {
                        id: cellLabel
                        y: face.height + Theme.spacingXS
                        width: cell.width
                        horizontalAlignment: Text.AlignHCenter
                        text: Theme.getPowerProfileLabel(cell.modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: cell.selected ? Theme.primary : Theme.onSurfaceVariant
                        elide: Text.ElideRight

                        Behavior on color {
                            enabled: root.animate
                            EffectsAnim {}
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sliderComp

        Item {
            id: slider

            readonly property int count: root.profiles.length
            readonly property int current: root.currentIndex
            readonly property real cell: width / Math.max(1, count)
            // The cell whose keyboard focus ring shows; the thumb draws it when that cell is under it
            property int ringIndex: -1
            property int settledIndex: -1
            // The cell the thumb is sliding away from: its icon stays hidden until the thumb arrives.
            property int leavingIndex: -1

            implicitHeight: thumb.height
            Accessible.role: Accessible.Grouping
            Accessible.name: I18n.tr("Power profile")
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true
            Keys.onPressed: event => root.stepWithArrows(event, sliderRepeater)
            Component.onCompleted: settledIndex = current
            onCurrentChanged: {
                leavingIndex = settledIndex;
                settledIndex = current;
                if (root.animate)
                    thumbPop.restart();
            }

            Rectangle {
                width: parent.width
                height: BatteryPopoutMetrics.powerButton
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: Theme.surfaceContainerHighest
            }

            Row {
                anchors.fill: parent

                Repeater {
                    id: sliderRepeater
                    model: root.profiles

                    StyledButton {
                        id: stop

                        required property var modelData
                        required property int index
                        // Hidden while any part of the thumb overlaps it, or it peeks out beside the thumb as it slides.
                        readonly property bool covered: thumb.visible && Math.abs(thumb.x + thumb.width / 2 - stop.x - stop.width / 2) < (thumb.width + Theme.iconSize) / 2

                        width: slider.cell
                        height: slider.height
                        focusPolicy: activeFocus || index === root.focusIndex ? Qt.StrongFocus : Qt.ClickFocus
                        checkable: true
                        checked: index === slider.current
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: Theme.getPowerProfileLabel(modelData)
                        onClicked: root.choose(index)
                        onVisualFocusChanged: {
                            if (visualFocus)
                                slider.ringIndex = index;
                            else if (slider.ringIndex === index)
                                slider.ringIndex = -1;
                        }

                        Rectangle {
                            width: BatteryPopoutMetrics.powerButton
                            height: width
                            anchors.centerIn: parent
                            radius: width / 2
                            color: "transparent"

                            FocusRing {
                                visible: stop.visualFocus && stop.index !== slider.current
                            }
                        }

                        DIcon {
                            anchors.centerIn: parent
                            visible: !stop.covered && !(thumbSlide.running && stop.index === slider.leavingIndex)
                            name: Theme.getPowerProfileIcon(stop.modelData)
                            size: Theme.iconSize
                            color: Theme.onSurfaceVariant
                            scale: stop.pressed ? BatteryPopoutMetrics.sliderPressScale : 1

                            Behavior on scale {
                                enabled: root.animate
                                SpatialAnim {}
                            }
                        }
                    }
                }
            }

            Item {
                id: thumb
                readonly property string iconName: Theme.getPowerProfileIcon(root.profiles[slider.current])

                visible: slider.current >= 0
                width: Math.round(BatteryPopoutMetrics.powerButton * BatteryPopoutMetrics.sliderThumbRatio)
                height: width
                x: (I18n.isRtl ? slider.count - 1 - slider.current : slider.current) * slider.cell + (slider.cell - width) / 2

                Behavior on x {
                    enabled: root.animate
                    DCommon.DAnim {
                        id: thumbSlide
                    }
                }

                SequentialAnimation {
                    id: thumbPop
                    NumberAnimation {
                        target: thumb
                        property: "scale"
                        to: BatteryPopoutMetrics.popScale
                        duration: Theme.expressiveDurations.expressiveEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                    SpatialAnim {
                        target: thumb
                        property: "scale"
                        to: 1
                    }
                }

                DMaterialShape {
                    anchors.fill: parent
                    shape: "clover4"
                    color: Theme.primary
                    // A clover4 repeats every 90 degrees, so each step turns it while it slides and it lands looking the same
                    rotation: Math.max(0, slider.current) * 90
                    layer.enabled: thumb.visible
                    layer.smooth: true
                    layer.mipmap: true
                    layer.textureSize: Qt.size(Math.ceil(width * BatteryPopoutMetrics.shapeSupersampling), Math.ceil(height * BatteryPopoutMetrics.shapeSupersampling))

                    Behavior on rotation {
                        enabled: root.animate
                        DCommon.DAnim {}
                    }
                }

                FocusRing {
                    radius: width / 2
                    visible: slider.ringIndex >= 0 && slider.ringIndex === slider.current
                }

                DIcon {
                    anchors.centerIn: parent
                    name: thumb.iconName
                    size: Theme.iconSize
                    color: Theme.onPrimary
                    filled: Theme.powerProfileIconFilled(root.profiles[slider.current])
                }
            }
        }
    }
}
