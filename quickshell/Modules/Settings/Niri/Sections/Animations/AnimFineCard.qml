import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import qs.Modules.Settings.Widgets
import "../../../../../Common/niri/anim.js" as Anim

// Expert only: spring or curve of the picked animation, with a preview and its motion curve.
NiriCard {
    id: root

    property string name: "window-open"
    property var anim: null
    property real slowdown: 1
    property bool animationsOn: true

    readonly property string key: "animations." + name + "."
    readonly property bool isSpring: anim?.kind === "spring"
    readonly property bool sideBySide: width >= Theme.iconButtonSize * 18
    readonly property real half: sideBySide ? (width - Theme.spacingL * 2 - Theme.spacingL) / 2 : width - Theme.spacingL * 2

    icon: "tune"
    title: I18n.tr("Fine tune · %1", "niri page animation editor card; %1 is the animation's KDL name").arg(name)

    Flow {
        width: parent.width
        spacing: Theme.spacingL

        Column {
            width: root.half

            NiriSeg {
                width: parent.width
                settingKey: root.key + "kind"
                icon: "category"
                title: I18n.tr("Type", "niri page animation kind row")
                kdlKey: "spring / duration-ms + curve"
                options: [
                    {
                        "value": "spring",
                        "text": I18n.tr("Spring", "niri page animation kind")
                    },
                    {
                        "value": "curve",
                        "text": I18n.tr("Curve", "niri page animation kind")
                    }
                ]
            }

            NiriSlider {
                visible: root.isSpring
                width: parent.width
                settingKey: root.key + "damping"
                icon: "waves"
                title: I18n.tr("Damping ratio", "niri page spring setting")
                tip: I18n.tr("Below 1 bounces", "niri page spring damping tip")
                kdlKey: "damping-ratio 0.1..10"
                from: 0.1
                to: 2
                stepSize: 0.05
                decimals: 2
            }

            NiriSlider {
                visible: root.isSpring
                width: parent.width
                settingKey: root.key + "stiffness"
                icon: "compress"
                title: I18n.tr("Stiffness", "niri page spring setting")
                tip: I18n.tr("Higher is faster", "niri page spring stiffness tip")
                kdlKey: "stiffness"
                from: 100
                to: 2000
                stepSize: 50
            }

            NiriSeg {
                visible: root.isSpring
                width: parent.width
                settingKey: root.key + "epsilon"
                icon: "target"
                title: I18n.tr("Epsilon", "niri page spring setting")
                tip: I18n.tr("How close to the end the spring stops", "niri page spring epsilon tip")
                kdlKey: "epsilon"
                options: Anim.epsilons.map(e => ({
                            "value": e,
                            "text": String(e)
                        }))
            }

            NiriSlider {
                visible: !root.isSpring
                width: parent.width
                settingKey: root.key + "ms"
                icon: "timer"
                title: I18n.tr("Duration", "niri page animation curve setting")
                kdlKey: "duration-ms"
                from: 50
                to: 1000
                stepSize: 10
                unit: " ms"
            }

            NiriSeg {
                visible: !root.isSpring
                width: parent.width
                settingKey: root.key + "curve"
                icon: "show_chart"
                title: I18n.tr("Curve", "niri page animation curve setting")
                kdlKey: "curve"
                options: [
                    {
                        "value": "ease-out-quad",
                        "text": I18n.tr("Quad", "niri page easing curve"),
                        "tooltip": "ease-out-quad"
                    },
                    {
                        "value": "ease-out-cubic",
                        "text": I18n.tr("Cubic", "niri page easing curve"),
                        "tooltip": "ease-out-cubic"
                    },
                    {
                        "value": "ease-out-expo",
                        "text": I18n.tr("Expo", "niri page easing curve"),
                        "tooltip": "ease-out-expo"
                    },
                    {
                        "value": "linear",
                        "text": I18n.tr("Linear", "niri page easing curve"),
                        "tooltip": "linear"
                    }
                ]
            }
        }

        Column {
            width: root.half
            spacing: Theme.spacingS

            AnimStage {
                id: stage
                width: parent.width
                height: Theme.iconButtonSize * 3.75
                anim: root.anim
                effect: Anim.effects[root.name] ?? "open"
                slowdown: root.slowdown
                animationsOn: root.animationsOn
                windowWidth: 0.4
                windowHeight: 0.6
            }

            Rectangle {
                width: parent.width
                height: Theme.iconButtonSize * 3.75
                radius: Theme.cornerRadiusS
                color: SettingsMetrics.controlColor

                AnimCurve {
                    anchors.fill: parent
                    samples: stage.samples
                    mark: stage.markIndex
                }
            }

            Row {
                spacing: Theme.spacingM

                DButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Play", "niri page animation preview button")
                    iconName: "play_arrow"
                    enabled: root.animationsOn
                    onClicked: stage.play()
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.animationsOn ? I18n.tr("%1 ms", "niri page animation length").arg(Math.round(stage.last * root.slowdown)) : I18n.tr("Animations are off", "niri page animation editor")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
