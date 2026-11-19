pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.DCommon.Common as DCommon
import "../../../Common/BatteryPopoutMetrics.js" as BatteryPopoutMetrics

DCard {
    id: root

    property var metrics: BatteryPopoutMetrics.metrics("comfortable")
    property bool active: false
    // Heading (and the slider's current-profile tag) can be hidden when the section sits inside another card
    property bool showHeading: true
    // Without the frame there is no card background and no padding
    property bool framed: true

    readonly property string style: SettingsData.batteryPopoutPowerStyle
    readonly property var profiles: PowerProfileWatcher.availableProfiles
    readonly property int currentIndex: profiles.indexOf(PowerProfileWatcher.currentProfile)
    readonly property var profileIcons: ["eco", "balance", "speed"]
    // Off until the first layout has settled, so nothing slides in when the popout opens
    property bool settled: false
    readonly property bool animate: active && settled && !Theme.reduceMotion
    // The cookie shapes draw into a texture this many times their size, which keeps their edges smooth
    readonly property int shapeSupersampling: 4
    readonly property real compactIconSize: Theme.iconSizeSmall + Theme.spacingXS
    // A newly selected cookie grows and turns into place from these
    readonly property real popScale: 0.7
    readonly property real popRotation: -40

    function profileIcon(profile) {
        return profileIcons[profile] ?? "balance";
    }

    // The leaf's vein breaks into dashes when it is filled at icon size
    function iconFilled(name, selected) {
        return selected && name !== "eco";
    }

    function choose(index) {
        const profile = profiles[index];
        if (profile === undefined || PowerProfileWatcher.applyProfile(profile))
            return;
        ToastService.showError(PowerProfileWatcher.available ? I18n.tr("Failed to set power profile") : I18n.tr("power-profiles-daemon not available"));
    }

    component SpatialAnim: NumberAnimation {
        duration: Theme.expressiveDurations.expressiveFastSpatial
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
    }

    component EffectsAnim: DCommon.DColorAnim {}

    component SoftAnim: DCommon.DAnim {}

    component FadeAnim: NumberAnimation {
        duration: Theme.expressiveDurations.expressiveEffects
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
    }

    width: parent?.width ?? 0
    height: body.implicitHeight + pad * 2
    pad: framed ? metrics.pad : 0
    restRadius: Theme.cornerRadiusL
    color: framed ? surfaceColor : "transparent"
    border.width: framed ? Theme.layerOutlineWidth : 0
    visible: PowerProfileWatcher.available
    enabled: PowerProfileWatcher.available
    Component.onCompleted: Qt.callLater(() => settled = true)

    Column {
        id: body
        width: parent.width
        spacing: root.metrics.gap

        Item {
            visible: root.showHeading
            width: parent.width
            height: Math.max(headerLabel.implicitHeight, tag.visible ? tag.height : 0)

            StyledText {
                id: headerLabel
                anchors.left: parent.left
                anchors.right: tag.visible ? tag.left : parent.right
                anchors.rightMargin: tag.visible ? Theme.spacingS : 0
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Power profile")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.primary
                elide: Text.ElideRight
            }

            Rectangle {
                id: tag
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.style === "slider" && root.currentIndex >= 0
                width: tagText.implicitWidth + Theme.spacingS * 2
                height: tagText.implicitHeight + Theme.spacingXXS * 2
                radius: Theme.cornerRadiusS
                color: Theme.primaryContainer

                StyledText {
                    id: tagText
                    anchors.centerIn: parent
                    text: Theme.getPowerProfileLabel(root.profiles[root.currentIndex])
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: Theme.onPrimaryContainer
                }
            }
        }

        Loader {
            width: parent.width
            sourceComponent: choicesComp
        }
    }

    Component {
        id: choicesComp

        Item {
            id: choices

            readonly property bool circle: root.style === "circle"
            readonly property bool segments: root.style === "segments"
            readonly property bool buttons: root.style === "buttons"
            readonly property bool slider: root.style === "slider"
            readonly property bool joined: buttons || segments
            readonly property int count: root.profiles.length
            readonly property int current: root.currentIndex
            readonly property int focusIndex: Math.max(0, Math.min(current, count - 1))
            readonly property real gap: joined ? Theme.groupedListGap : 0
            // Buttons: shares of the row a selected, a pressed and every other button take
            readonly property real selectedShares: 2.5
            readonly property real pressedShares: 1.2
            property int pressedIndex: -1
            readonly property real totalShares: {
                let total = 0;
                for (let i = 0; i < count; i++)
                    total += shares(i);
                return total;
            }

            function shares(index) {
                if (!buttons)
                    return 1;
                return index === current ? selectedShares : (index === pressedIndex ? pressedShares : 1);
            }

            function cellWidth(index) {
                return (width - gap * (count - 1)) * shares(index) / Math.max(1, totalShares);
            }

            implicitHeight: row.implicitHeight
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true
            Accessible.role: Accessible.Grouping
            Accessible.name: I18n.tr("Power profile")
            onCurrentChanged: {
                if (slider && root.animate)
                    thumbPop.restart();
            }

            Keys.onPressed: event => {
                if (!root.enabled || (event.modifiers & ~Qt.KeypadModifier) !== Qt.NoModifier || count === 0)
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
                root.choose(next);
                event.accepted = true;
            }

            Rectangle {
                id: track
                visible: choices.slider
                width: parent.width
                height: root.metrics.powerButton
                radius: height / 2
                color: Theme.secondaryContainer
            }

            DMaterialShape {
                id: thumb
                visible: choices.slider && choices.current >= 0
                shape: "cookie9"
                color: Theme.primary
                width: root.metrics.powerButton
                height: thumb.width
                anchors.verticalCenter: track.verticalCenter
                x: {
                    const cell = row.width / Math.max(1, choices.count);
                    const column = I18n.isRtl ? choices.count - 1 - choices.current : choices.current;
                    return column * cell + (cell - thumb.width) / 2;
                }
                rotation: Math.max(0, choices.current) * 80
                layer.enabled: visible
                layer.smooth: true
                layer.mipmap: true
                layer.textureSize: Qt.size(Math.ceil(width * root.shapeSupersampling), Math.ceil(height * root.shapeSupersampling))

                Behavior on x {
                    enabled: root.animate
                    SoftAnim {}
                }

                Behavior on rotation {
                    enabled: root.animate
                    SoftAnim {}
                }

                SequentialAnimation {
                    id: thumbPop
                    SpatialAnim {
                        target: thumb
                        property: "scale"
                        from: root.popScale
                        to: 1
                    }
                }
            }

            Row {
                id: row
                width: parent.width
                spacing: choices.gap

                Repeater {
                    id: repeater
                    model: root.profiles

                    StyledButton {
                        id: cell

                        required property var modelData
                        required property int index
                        readonly property bool selected: index === choices.current
                        readonly property string profileLabel: Theme.getPowerProfileLabel(modelData)
                        readonly property string iconName: root.profileIcon(modelData)
                        readonly property color iconColor: selected ? Theme.onPrimary : (choices.circle ? Theme.onSurfaceVariant : Theme.onSecondaryContainer)
                        readonly property bool joined: choices.joined
                        readonly property real outerRadius: height / 2
                        // Inner corners are small, round off for the selected one and drop to the smallest while pressed
                        readonly property real joinRadius: pressed ? Theme.cornerRadiusXS : (selected ? outerRadius : Theme.cornerRadiusS)
                        property real startRadius: joined ? (index === 0 ? outerRadius : joinRadius) : 0
                        property real endRadius: joined ? (index === choices.count - 1 ? outerRadius : joinRadius) : 0

                        width: choices.cellWidth(index)
                        height: joined ? root.metrics.button : (choices.slider ? root.metrics.powerButton : root.metrics.powerButton + Theme.spacingXS + cellLabel.implicitHeight)
                        clip: choices.buttons
                        focusPolicy: activeFocus || index === choices.focusIndex ? Qt.StrongFocus : Qt.ClickFocus
                        checkable: true
                        checked: selected
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: profileLabel
                        onClicked: root.choose(index)
                        onPressedChanged: {
                            if (pressed)
                                choices.pressedIndex = index;
                            else if (choices.pressedIndex === index)
                                choices.pressedIndex = -1;
                        }
                        onSelectedChanged: {
                            if (selected && choices.circle && root.animate)
                                cookiePop.restart();
                        }

                        color: joined ? (selected ? Theme.primary : Theme.secondaryContainer) : "transparent"
                        topLeftRadius: Math.max(0, I18n.isRtl ? endRadius : startRadius)
                        bottomLeftRadius: topLeftRadius
                        topRightRadius: Math.max(0, I18n.isRtl ? startRadius : endRadius)
                        bottomRightRadius: topRightRadius

                        Behavior on startRadius {
                            enabled: root.animate
                            SpatialAnim {}
                        }

                        Behavior on endRadius {
                            enabled: root.animate
                            SpatialAnim {}
                        }

                        Behavior on width {
                            enabled: root.animate && choices.buttons
                            SpatialAnim {}
                        }

                        Behavior on color {
                            enabled: root.animate
                            EffectsAnim {}
                        }

                        StateLayer {
                            visible: cell.joined
                            control: cell
                            disabled: !cell.enabled
                            stateColor: cell.iconColor
                        }

                        FocusRing {
                            visible: cell.joined && cell.visualFocus
                        }

                        Row {
                            visible: cell.joined
                            anchors.centerIn: parent

                            DIcon {
                                name: cell.iconName
                                size: root.compactIconSize
                                color: cell.iconColor
                                filled: root.iconFilled(cell.iconName, cell.selected)
                                anchors.verticalCenter: parent.verticalCenter

                                Behavior on color {
                                    enabled: root.animate
                                    EffectsAnim {}
                                }
                            }

                            Item {
                                id: labelBox
                                // Buttons show the name only while selected; the box grows and the text fades with it
                                readonly property real shown: choices.buttons ? (cell.selected ? 1 : 0) : 1
                                readonly property real textWidth: Math.min(labelText.implicitWidth, Math.max(0, cell.width - root.compactIconSize - Theme.spacingM * 2 - Theme.spacingS))
                                width: (textWidth + (choices.buttons ? Theme.spacingS : Theme.spacingXS)) * (cell.selected || !choices.buttons ? 1 : 0)
                                height: labelText.implicitHeight
                                opacity: shown
                                clip: true
                                anchors.verticalCenter: parent.verticalCenter

                                Behavior on width {
                                    enabled: root.animate
                                    FadeAnim {}
                                }

                                Behavior on opacity {
                                    enabled: root.animate
                                    FadeAnim {}
                                }

                                StyledText {
                                    id: labelText
                                    anchors.left: parent.left
                                    anchors.leftMargin: choices.buttons ? Theme.spacingS : Theme.spacingXS
                                    width: labelBox.textWidth
                                    text: cell.profileLabel
                                    font.pixelSize: choices.buttons ? Theme.fontSizeMedium : Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium
                                    fontSizeMode: Text.HorizontalFit
                                    minimumPixelSize: Math.round(font.pixelSize * 0.75)
                                    color: cell.iconColor
                                    elide: Text.ElideRight

                                    Behavior on color {
                                        enabled: root.animate
                                        EffectsAnim {}
                                    }
                                }
                            }
                        }

                        Item {
                            id: face
                            visible: !cell.joined
                            width: root.metrics.powerButton
                            height: face.width
                            scale: cell.pressed ? (choices.slider ? 0.85 : 0.9) : 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: choices.circle ? parent.top : undefined
                            anchors.verticalCenter: choices.circle ? undefined : parent.verticalCenter

                            Behavior on scale {
                                enabled: root.animate
                                SpatialAnim {}
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingXS
                                visible: choices.circle && !cell.selected
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
                                visible: choices.circle && cell.selected
                                shape: "cookie9"
                                color: Theme.primary
                                layer.enabled: visible
                                layer.smooth: true
                                layer.mipmap: true
                                layer.textureSize: Qt.size(Math.ceil(width * root.shapeSupersampling), Math.ceil(height * root.shapeSupersampling))

                                ParallelAnimation {
                                    id: cookiePop
                                    SpatialAnim {
                                        target: cookie
                                        property: "scale"
                                        from: root.popScale
                                        to: 1
                                    }
                                    SpatialAnim {
                                        target: cookie
                                        property: "rotation"
                                        from: root.popRotation
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
                                filled: root.iconFilled(cell.iconName, cell.selected)

                                Behavior on color {
                                    enabled: root.animate
                                    EffectsAnim {}
                                }
                            }
                        }

                        StyledText {
                            id: cellLabel
                            visible: choices.circle
                            anchors.top: face.bottom
                            anchors.topMargin: Theme.spacingXS
                            anchors.left: parent.left
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.profileLabel
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
    }
}
