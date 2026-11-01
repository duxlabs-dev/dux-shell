pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import qs.Modules.Settings.Niri.Sections.Animations
import "../../../../Common/niri/anim.js" as Anim
import "../../../../Common/niri/sections/animations.js" as Section

Column {
    id: root

    readonly property string sectionId: "animations"

    property string picked: "window-open"
    readonly property var pageState: NiriPageService.state
    readonly property bool animationsOn: pageState["animations.on"] !== false
    readonly property real slowdown: Number(pageState["animations.slowdown"]) || 1
    readonly property bool expert: NiriPageService.expert
    readonly property var titles: ({
            "workspace-switch": I18n.tr("Workspace switch", "niri animation"),
            "window-open": I18n.tr("Window open", "niri animation"),
            "window-close": I18n.tr("Window close", "niri animation"),
            "horizontal-view-movement": I18n.tr("View scroll", "niri animation"),
            "window-movement": I18n.tr("Window move", "niri animation"),
            "window-resize": I18n.tr("Window resize", "niri animation"),
            "config-notification-open-close": I18n.tr("Config notice", "niri animation"),
            "exit-confirmation-open-close": I18n.tr("Exit dialog", "niri animation"),
            "screenshot-ui-open": I18n.tr("Screenshot", "niri animation"),
            "overview-open-close": I18n.tr("Overview", "niri animation"),
            "recent-windows-close": I18n.tr("Alt-Tab close", "niri animation")
        })
    readonly property Component sidePane: Component {
        AnimMotionPane {
            title: root.titles[root.picked] ?? root.picked
            anim: Section.read(root.pageState, root.picked)
            effect: Anim.effects[root.picked]
            slowdown: root.slowdown
            animationsOn: root.animationsOn
        }
    }

    spacing: Theme.spacingM

    NiriCard {

        AnimStyleRow {}

        NiriRow {
            settingKey: "animations.on"
            icon: "animation"
            // Named after windows so it never reads as DMS's own animation settings
            title: I18n.tr("Window animations", "niri page row")
            tip: I18n.tr("Turns every niri animation on or off.", "niri page animations switch tip")
            kdlKey: "animations.off"
            cost: "some"
            costTip: I18n.tr("Draws extra frames each time a window moves.", "niri page animations battery tip")
        }

        NiriSlider {
            settingKey: "animations.slowdown"
            dependsOn: "animations.on"
            icon: "slow_motion_video"
            title: I18n.tr("Slowdown", "niri page row")
            tip: I18n.tr("Multiplies the length of every animation. 1.0 is normal.", "niri page slowdown tip")
            kdlKey: "animations.slowdown"
            from: Section.limits["animations.slowdown"].from
            to: Section.limits["animations.slowdown"].to
            stepSize: 0.1
            decimals: 1
        }
    }

    NiriCard {
        id: galleryCard

        readonly property int columns: Math.max(1, Math.floor((width - Theme.spacingL * 2 + Theme.spacingS) / (Theme.iconButtonSize * 3.2 + Theme.spacingS)))

        icon: "play_circle"
        title: I18n.tr("Gallery", "niri page animation gallery card")
        aside: I18n.tr("Hover to play", "niri page animation gallery hint")

        GridLayout {
            id: gallery

            width: parent.width
            columns: galleryCard.columns
            columnSpacing: Theme.spacingS
            rowSpacing: Theme.spacingS

            Repeater {
                model: Anim.names

                AnimTile {
                    required property string modelData

                    Layout.preferredWidth: (gallery.width - gallery.columnSpacing * (gallery.columns - 1)) / gallery.columns
                    Layout.fillHeight: true
                    name: modelData
                    title: root.titles[modelData] ?? modelData
                    anim: Section.read(root.pageState, modelData)
                    effect: Anim.effects[modelData]
                    slowdown: root.slowdown
                    animationsOn: root.animationsOn
                    expert: root.expert
                    selected: root.picked === modelData
                    onPicked: root.picked = modelData
                }
            }
        }

        Row {
            visible: SettingsData.reduceMotion || Theme.currentAnimationBaseDuration <= 0
            topPadding: Theme.spacingS
            spacing: Theme.spacingS

            DIcon {
                name: "motion_photos_off"
                size: Theme.iconSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                text: I18n.tr("Reduced motion: tiles show the end state.", "niri page animation gallery note")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }

    AnimFineCard {
        visible: root.expert
        name: root.picked
        anim: Section.read(root.pageState, root.picked)
        slowdown: root.slowdown
        animationsOn: root.animationsOn
    }
}
