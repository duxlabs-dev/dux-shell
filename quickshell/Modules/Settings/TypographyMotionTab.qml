import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root

    SettingsPage {
        id: mainColumn

        Loader {
            width: parent.width
            active: CompositorService.isAqueous
            sourceComponent: AqueousAppearanceSettings {
                settingKey: "aqueousTypography"
                title: I18n.tr("Aqueous typography", "Aqueous compositor font synchronization settings")
                visible: CompositorService.isAqueous
            }
        }

        SettingsCard {
            tab: "typography"
            tags: ["font", "family", "text", "typography", "monospace"]
            title: I18n.tr("Font", "noun, typography settings card title and font dropdown label")
            settingKey: "typography"
            iconName: "text_fields"

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        width: parent.width
                        text: "Aa Bb Cc 123"
                        font.family: Theme.resolvedFontFamily(SettingsData.fontFamily)
                        font.pixelSize: Theme.fontSizeXXLarge
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: "Display Aa Bb Cc"
                        fontToken: "display"
                        font.pixelSize: Theme.fontSizeXLarge
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("The quick brown fox jumps over the lazy dog")
                        font.family: Theme.resolvedFontFamily(SettingsData.fontFamily)
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: "monospace { code: 0x1F; }"
                        font.family: Theme.resolvedMonoFontFamily(SettingsData.monoFontFamily)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }
                }
            }

            SettingsFontDropdownRow {
                tab: "typography"
                tags: ["font", "family", "normal", "text"]
                settingKey: "fontFamily"
                text: I18n.tr("Family", "font family dropdown label")
                maxPopupHeight: 400
                currentFont: SettingsData.fontFamily
                onFontSelected: family => SettingsData.set("fontFamily", family || Theme.defaultFontFamily)
            }

            SettingsSliderRow {
                tab: "typography"
                tags: ["font", "weight", "bold", "light"]
                settingKey: "fontWeight"
                text: I18n.tr("Weight", "font weight slider label")
                minimum: Font.Thin
                maximum: Font.Black
                step: 100
                showStops: true
                unit: ""
                value: SettingsData.fontWeight
                onSliderValueChanged: newValue => SettingsData.set("fontWeight", newValue)
            }

            SettingsSliderRow {
                tab: "typography"
                tags: ["font", "scale", "size", "zoom"]
                settingKey: "fontScale"
                text: I18n.tr("Scale", "noun, font scale slider and display scale setting label")
                minimum: 75
                maximum: 150
                value: Math.round(SettingsData.fontScale * 100)
                onSliderValueChanged: newValue => SettingsData.set("fontScale", newValue / 100)
            }
            SettingsFontDropdownRow {
                tab: "typography"
                tags: ["font", "monospace", "code", "terminal", "process"]
                settingKey: "monoFontFamily"
                text: I18n.tr("Monospace family")
                maxPopupHeight: 400
                defaultFamily: Theme.defaultMonoFontFamily
                currentFont: SettingsData.monoFontFamily
                onFontSelected: family => SettingsData.set("monoFontFamily", family || Theme.defaultMonoFontFamily)
            }

            SettingsFontDropdownRow {
                tab: "typography"
                tags: ["font", "display", "stylistic", "serif", "title", "headline"]
                settingKey: "displayFontFamily"
                text: I18n.tr("Display family")
                maxPopupHeight: 400
                defaultFamily: Theme.defaultDisplayFontFamily
                currentFont: SettingsData.displayFontFamily
                onFontSelected: family => SettingsData.set("displayFontFamily", family || Theme.defaultDisplayFontFamily)
            }
        }

        SettingsCard {
            tab: "typography"
            tags: ["animation", "motion", "speed", "duration", "spring", "physics", "bounce", "accessibility", "ripple", "fluid"]
            title: I18n.tr("Animations", "settings card title")
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
                tab: "typography"
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
                tab: "typography"
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
                tab: "typography"
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
                tab: "typography"
                tags: ["animation", "ripple", "effect", "material", "click"]
                settingKey: "enableRippleEffects"
                text: I18n.tr("Ripple effects")
                checked: SettingsData.enableRippleEffects ?? true
                onToggled: newValue => SettingsData.set("enableRippleEffects", newValue)
            }

            SettingsToggleRow {
                tab: "typography"
                tags: ["animation", "spring", "physics", "accessibility", "reduce", "motion"]
                settingKey: "reduceMotion"
                text: I18n.tr("Reduce motion")
                checked: SettingsData.reduceMotion
                onToggled: checked => SettingsData.set("reduceMotion", checked)
            }
        }

        SettingsCard {
            tab: "typography"
            tags: ["text", "render", "rendering", "quality", "animation", "popout", "modal", "sync", "duration"]
            title: I18n.tr("Advanced", "adjective, settings section title for advanced options")
            settingKey: "typographyAdvanced"
            collapsible: true
            expanded: false

            SettingsButtonGroupRow {
                tab: "typography"
                tags: ["text", "render", "rendering", "type", "native", "qt", "curve", "freetype", "distance-field", "rasterizer"]
                settingKey: "textRenderType"
                text: I18n.tr("Renderer", "text rendering engine setting label")
                model: [I18n.tr("Native", "adjective, text renderer option, native platform rendering"), "Qt", I18n.tr("Curve", "noun, text renderer option, qt curve rendering")]
                currentIndex: {
                    switch (SettingsData.textRenderType) {
                    case SettingsData.TextRenderType.Qt:
                        return 1;
                    case SettingsData.TextRenderType.Curve:
                        return 2;
                    default:
                        return 0;
                    }
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    switch (index) {
                    case 1:
                        SettingsData.set("textRenderType", SettingsData.TextRenderType.Qt);
                        break;
                    case 2:
                        SettingsData.set("textRenderType", SettingsData.TextRenderType.Curve);
                        break;
                    default:
                        SettingsData.set("textRenderType", SettingsData.TextRenderType.Native);
                        break;
                    }
                }
            }

            SettingsDropdownRow {
                id: renderQualityRow
                tab: "typography"
                tags: ["text", "render", "quality", "level"]
                settingKey: "textRenderQuality"
                text: I18n.tr("Quality", "text render quality dropdown label")
                options: [I18n.tr("Default"), I18n.tr("Low", "quality level option"), I18n.tr("Normal", "quality level option"), I18n.tr("High", "quality level option"), I18n.tr("Very High", "quality level option")]
                currentValue: options[SettingsData.textRenderQuality] ?? options[0]
                onValueChanged: value => {
                    const index = renderQualityRow.options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("textRenderQuality", index);
                }
            }

            SettingsToggleRow {
                tab: "typography"
                tags: ["animation", "sync", "popout", "modal", "global"]
                settingKey: "syncComponentAnimationSpeeds"
                text: I18n.tr("Sync popouts and modals")
                description: I18n.tr("Popouts and modals use the main animation duration", "sync popout and modal animation toggle description")
                checked: SettingsData.syncComponentAnimationSpeeds
                onToggled: checked => SettingsData.set("syncComponentAnimationSpeeds", checked)
            }

            SettingsSliderRow {
                visible: !SettingsData.syncComponentAnimationSpeeds
                tab: "typography"
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
                tab: "typography"
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
