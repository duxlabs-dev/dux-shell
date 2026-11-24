import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    SettingsPage {
        id: mainColumn

        SettingsDeferred {
            SettingsCard {
                tab: "motion"
                tags: ["animation", "motion", "speed", "duration", "spring", "physics", "bounce", "ripple", "fluid"]
                title: I18n.tr("Shell animations", "settings card title, motion of DMS surfaces")
                settingKey: "animations"
                iconName: "auto_awesome_motion"

                SettingsRow {
                    visible: !Theme.motionOff
                    body: Item {
                        id: motionPreview

                        readonly property real trackPadding: Theme.spacingS
                        readonly property real pillWidth: Theme.iconButtonSize * 2
                        readonly property real laneWidth: width
                        readonly property real travel: laneWidth - pillWidth - trackPadding * 2
                        readonly property var springParams: Theme.springPreset("defaultSpatial")
                        property bool atEnd: false

                        function play() {
                            atEnd = !atEnd;
                            pillSpring.retarget(atEnd ? travel : 0);
                        }

                        width: parent.width
                        height: Theme.iconButtonSize + Theme.spacingM * 2

                        SpringMotion {
                            id: pillSpring
                            enabled: !Theme.reduceMotion
                            stiffness: motionPreview.springParams.stiffness
                            damping: motionPreview.springParams.damping
                            value: 0
                            target: 0
                        }

                        Rectangle {
                            id: springLane
                            width: motionPreview.laneWidth
                            height: parent.height
                            radius: Theme.cornerRadiusM
                            color: SettingsMetrics.controlColor

                            StyledText {
                                x: parent.width - width - Theme.spacingL
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Tap to play")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                opacity: motionPreview.atEnd ? 0 : 1

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.expressiveDurations.expressiveFastEffects
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
                                    }
                                }
                            }

                            Rectangle {
                                x: motionPreview.trackPadding + pillSpring.value
                                anchors.verticalCenter: parent.verticalCenter
                                width: motionPreview.pillWidth
                                height: Theme.iconButtonSize
                                radius: Theme.fullRadius(width, height)
                                color: Theme.primary

                                DIcon {
                                    anchors.centerIn: parent
                                    name: motionPreview.atEnd ? "arrow_back" : "arrow_forward"
                                    smoothTransform: true
                                    size: Theme.iconSizeMedium
                                    color: Theme.onPrimary
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: motionPreview.play()
                        }
                    }
                }

                SettingsDropdownRow {
                    readonly property var steps: [I18n.tr("Off"), I18n.tr("Shorter", "animation duration option"), I18n.tr("Short", "animation duration option"), I18n.tr("Medium", "animation duration option"), I18n.tr("Long", "animation duration option"), I18n.tr("Longer", "animation duration option")]

                    tab: "motion"
                    tags: ["animation", "duration", "speed", "motion", "shorter", "longer", "fast", "slow", "off", "disable", "none"]
                    settingKey: "motionDuration"
                    text: I18n.tr("Duration", "animation duration slider label, also idle inhibitor duration dropdown")
                    options: steps
                    currentValue: steps[SettingsData.motionDuration + 1]
                    onValueChanged: value => SettingsData.set("motionDuration", steps.indexOf(value) - 1)
                }

                SettingsButtonGroupRow {
                    tab: "motion"
                    tags: ["animation", "spring", "physics", "bounce", "motion", "overshoot"]
                    settingKey: "springBounce"
                    visible: !Theme.motionOff
                    text: I18n.tr("Spring", "animation setting label, spring physics bounciness, not the season")
                    model: [I18n.tr("Smooth", "adjective, spring animation option with no bounce"), I18n.tr("Balanced"), I18n.tr("Playful", "adjective, spring animation option with the most bounce")]
                    currentIndex: SettingsData.springBounce
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        SettingsData.set("springBounce", index);
                    }
                }

                SettingsButtonGroupRow {
                    tab: "motion"
                    tags: ["animation", "motion", "fluid", "effect", "slide", "directional", "depth", "spring", "physics", "panels"]
                    settingKey: "motionEffect"
                    visible: !Theme.motionOff
                    text: I18n.tr("Panel motion")
                    model: [I18n.tr("Standard", "adjective, panel motion option and bar layout mode option"), I18n.tr("Directional", "adjective, panel motion effect option"), I18n.tr("Depth", "noun, panel motion effect option"), I18n.tr("Fluid", "adjective, panel motion effect option")]
                    currentIndex: SettingsData.motionEffect
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        SettingsData.set("motionEffect", index);
                    }
                }

                SettingsToggleRow {
                    tab: "motion"
                    tags: ["animation", "ripple", "effect", "material", "click"]
                    settingKey: "enableRippleEffects"
                    visible: !Theme.motionOff
                    text: I18n.tr("Ripple effects")
                    checked: SettingsData.enableRippleEffects ?? true
                    onToggled: newValue => SettingsData.set("enableRippleEffects", newValue)
                }

                SettingsNavRow {
                    visible: !Theme.motionOff
                    iconName: "accessibility_new"
                    title: I18n.tr("Reduce motion")
                    hint: SettingsTabs.page("accessibility")?.text ?? ""
                    onClicked: keyboard => {
                        SettingsSearchService.navigateToSection("reduceMotion");
                        root.parentModal?.navigateTo("accessibility", keyboard);
                    }
                }

                SettingsNavRow {
                    tab: "motion"
                    tags: ["niri", "hyprland", "mango", "window", "animations", "compositor", "spring", "bounce"]
                    settingKey: "compositorAnimationsLink"
                    visible: CompositorService.supportsAnimationsConfig
                    iconName: "animation"
                    title: I18n.tr("Compositor animations", "settings link to the compositor animations page")
                    hint: SettingsTabs.page("compositor_animations")?.hint ?? ""
                    onClicked: keyboard => root.parentModal?.navigateTo("compositor_animations", keyboard)
                }
            }
        }
    }
}
