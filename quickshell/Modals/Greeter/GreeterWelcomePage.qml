pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    readonly property int columns: 3
    readonly property real cardWidth: (content.width - Theme.spacingS * (columns - 1)) / columns
    readonly property var features: [
        {
            "icon": "palette",
            "shape": "softBurst",
            "hoverShape": "flower",
            "accent": "purple",
            "heading": I18n.tr("Dynamic Theming", "greeter feature card title"),
            "description": I18n.tr("Colors from wallpaper", "greeter feature card description"),
            "target": "theme"
        },
        {
            "icon": "toolbar",
            "shape": "pill",
            "hoverShape": "cookie4",
            "accent": "blue",
            "heading": I18n.tr("Bar"),
            "description": I18n.tr("Modular widget bar", "greeter feature card description"),
            "target": "dankbar_settings"
        },
        {
            "icon": "extension",
            "shape": "puffy",
            "hoverShape": "clover8",
            "accent": "green",
            "heading": I18n.tr("Plugins", "greeter feature card title"),
            "description": I18n.tr("Extensible architecture", "greeter feature card description"),
            "target": "plugins"
        },
        {
            "icon": "monitor",
            "shape": "gem",
            "hoverShape": "cookie6",
            "accent": "orange",
            "heading": I18n.tr("Multi-Monitor", "greeter feature card title"),
            "description": I18n.tr("Per-screen config", "greeter feature card description"),
            "target": CompositorService.supportsDisplayConfig ? "display_config" : "display_widgets"
        },
        {
            "icon": "nightlight",
            "shape": "sunny",
            "hoverShape": "softBurst",
            "accent": "pink",
            "heading": I18n.tr("Display Control", "greeter feature card title"),
            "description": I18n.tr("Night mode & gamma", "greeter feature card description"),
            "target": "display_gamma"
        },
        {
            "icon": "tune",
            "shape": "cookie9",
            "hoverShape": "sunny",
            "accent": "teal",
            "heading": I18n.tr("Control Center", "greeter feature card title"),
            "description": I18n.tr("Quick system toggles", "greeter feature card description"),
            "target": "control_center"
        }
    ]

    function open(target) {
        switch (target) {
        case "control_center":
            BarWidgetService.getBarWindowOnFocusedScreen()?.triggerControlCenter();
            return;
        }
        PopoutService.openSettingsWithTab(target);
    }

    DFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, content.height)

        Column {
            id: content
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: Math.min(640, parent.width - Theme.spacingXL * 2)
            spacing: Theme.spacingL

            DShapeHero {
                id: hero
                width: parent.width
                height: Math.max(implicitHeight, flick.height - grid.height - content.spacing)
                paddingV: Theme.spacingXL

                Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    Item {
                        width: Theme.buttonHeightM * 2
                        height: width
                        anchors.horizontalCenter: parent.horizontalCenter

                        Image {
                            readonly property real dpr: Screen.devicePixelRatio

                            anchors.centerIn: parent
                            height: parent.height
                            width: height * (506.50931 / 569.94629)
                            // 2x raster plus mipmap keeps the thin rings smooth at fractional scales
                            sourceSize.height: Math.ceil(height * dpr * 2)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            asynchronous: true
                            source: "file://" + Theme.shellDir + "/assets/danklogonormal.svg"
                            layer.enabled: true
                            layer.smooth: true
                            layer.textureSize: Qt.size(Math.ceil(width * dpr), Math.ceil(height * dpr))
                            layer.effect: MultiEffect {
                                saturation: 0
                                colorization: 1
                                colorizationColor: hero.accentColor
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("Welcome to %1", "greeter welcome page title, %1 is the product name").arg("Dux Shell")
                        font.pixelSize: Theme.fontSizeXXLarge
                        font.weight: Theme.fontWeightBold
                        color: hero.contentColor
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("A modern desktop shell for Wayland", "greeter welcome page tagline")
                        font.pixelSize: Theme.fontSizeLarge
                        color: hero.contentColor
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Grid {
                id: grid

                readonly property real cellHeight: {
                    let tallest = 0;
                    for (const card of children)
                        tallest = Math.max(tallest, card.implicitHeight ?? 0);
                    return tallest;
                }

                width: parent.width
                columns: root.columns
                rowSpacing: Theme.spacingS
                columnSpacing: Theme.spacingS
                layoutDirection: I18n.isRtl ? Qt.RightToLeft : Qt.LeftToRight

                Repeater {
                    model: root.features

                    delegate: FeatureCard {
                        required property var modelData

                        width: root.cardWidth
                        height: grid.cellHeight
                        iconName: modelData.icon
                        shape: modelData.shape
                        hoverShape: modelData.hoverShape
                        accent: modelData.accent
                        heading: modelData.heading
                        description: modelData.description
                        onClicked: root.open(modelData.target)
                    }
                }
            }
        }
    }
}
