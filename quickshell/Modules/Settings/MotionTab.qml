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

        SettingsCard {
            tab: "motion"
            tags: ["animation", "motion", "speed", "duration", "spring", "physics", "bounce", "accessibility", "ripple", "fluid"]
            title: I18n.tr("Shell animations", "settings card title, motion of DMS surfaces")
            settingKey: "animations"
            iconName: "auto_awesome_motion"

            SettingsRow {
                body: Item {
                    id: motionPreview

                    readonly property real trackPadding: Theme.spacingS
                    readonly property real pillWidth: Theme.iconButtonSize * 2
                    readonly property real laneWidth: width
                    readonly property real travel: laneWidth - pillWidth - trackPadding * 2
                    readonly property var springParams: Theme.springPreset("default", Theme.currentAnimationBaseDuration)
                    property bool atEnd: false

                    function play() {
                        atEnd = !atEnd;
                        pillSpring.retarget(atEnd ? travel : 0);
                    }

                    width: parent.width
                    height: Theme.iconButtonSize + Theme.spacingM * 2

                    SpringMotion {
                        id: pillSpring
                        enabled: !Theme.springMotionDisabled && !SettingsData.reduceMotion
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
                                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
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

            SettingsSliderRow {
                tab: "motion"
                tags: ["animation", "duration", "speed", "motion"]
                settingKey: "animationDuration"
                text: I18n.tr("Duration", "animation duration slider label, also idle inhibitor duration dropdown")
                minimumLabel: I18n.tr("Off")
                minimum: 0
                maximum: 1000
                value: SettingsData.animationDuration
                unit: "ms"
                onSliderValueChanged: newValue => SettingsData.set("animationDuration", newValue)
            }

            SettingsButtonGroupRow {
                tab: "motion"
                tags: ["animation", "spring", "physics", "bounce", "motion", "overshoot"]
                settingKey: "springBounce"
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
                text: I18n.tr("Ripple effects")
                checked: SettingsData.enableRippleEffects ?? true
                onToggled: newValue => SettingsData.set("enableRippleEffects", newValue)
            }

            SettingsToggleRow {
                tab: "motion"
                tags: ["animation", "spring", "physics", "accessibility", "reduce", "motion"]
                settingKey: "reduceMotion"
                text: I18n.tr("Reduce motion")
                checked: SettingsData.reduceMotion
                onToggled: checked => SettingsData.set("reduceMotion", checked)
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

        SettingsAdvancedSection {
            SettingsDeferred {
                SettingsCard {
                    tab: "motion"
                    tags: ["animation", "popout", "modal", "sync", "duration"]
                    title: I18n.tr("Advanced", "adjective, settings section title for advanced options")
                    settingKey: "motionAdvanced"

                    SettingsToggleRow {
                        tab: "motion"
                        tags: ["animation", "sync", "popout", "modal", "global"]
                        settingKey: "syncComponentAnimationSpeeds"
                        text: I18n.tr("Sync popouts and modals")
                        description: I18n.tr("Popouts and modals use the main animation duration", "sync popout and modal animation toggle description")
                        checked: SettingsData.syncComponentAnimationSpeeds
                        onToggled: checked => SettingsData.set("syncComponentAnimationSpeeds", checked)
                    }

                    SettingsSliderRow {
                        visible: !SettingsData.syncComponentAnimationSpeeds
                        tab: "motion"
                        tags: ["animation", "duration", "speed", "popout"]
                        settingKey: "popoutAnimationDuration"
                        text: I18n.tr("Popouts", "plural noun, shell popout panels, animation and shadow setting label")
                        minimumLabel: I18n.tr("Off")
                        minimum: 0
                        maximum: 1000
                        value: SettingsData.popoutAnimationDuration
                        unit: "ms"
                        onSliderValueChanged: newValue => SettingsData.set("popoutAnimationDuration", newValue)
                    }

                    SettingsSliderRow {
                        visible: !SettingsData.syncComponentAnimationSpeeds
                        tab: "motion"
                        tags: ["animation", "duration", "speed", "modal"]
                        settingKey: "modalAnimationDuration"
                        text: I18n.tr("Modals", "plural noun, shell modal dialogs, animation and shadow setting label")
                        minimumLabel: I18n.tr("Off")
                        minimum: 0
                        maximum: 1000
                        value: SettingsData.modalAnimationDuration
                        unit: "ms"
                        onSliderValueChanged: newValue => SettingsData.set("modalAnimationDuration", newValue)
                    }
                }
            }
        }
    }
}
