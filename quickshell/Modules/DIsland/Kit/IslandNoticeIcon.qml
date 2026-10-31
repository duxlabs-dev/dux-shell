pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../../../Common/IslandKit.js" as Kit

// An alert sits on a shape (critical a burst, important a cookie), so its level reads by shape, not by colour alone.
Item {
    id: root

    property string imageSource: ""
    property string fallbackIcon: "material:notifications"
    property string fallbackText: ""
    property string alert: ""
    readonly property bool alarmed: root.alert !== ""
    readonly property bool critical: root.alert === "critical"
    readonly property string materialPrefix: "material:"
    readonly property bool material: root.fallbackIcon.startsWith(root.materialPrefix)
    // [shape, icon, text]: 3:1 off every island ground, in every theme, then 3:1 and 4.5:1 on it (IslandKit.alertTones).
    readonly property var tones: Kit.alertTones(root.alert, Theme)

    Accessible.role: Accessible.Graphic
    Accessible.name: root.critical ? I18n.tr("Critical", "island notification: alert level") : root.alarmed ? I18n.tr("Important", "island notification: alert level") : ""

    // Without a logo: the sender's initial or symbol in the round fallback.
    Loader {
        anchors.fill: parent
        active: !shape.visible
        sourceComponent: DCircularImage {
            imageSource: root.imageSource
            fallbackIcon: root.fallbackIcon
            fallbackText: root.fallbackText
            cacheImages: false
        }
    }

    // A logo sits on the filled shape; plain, the shape takes the tone that contrasts with the logo (31/10: a white
    // Android silhouette from the phone was lost on the light theme's round picture).
    IslandAppIcon {
        id: shape

        anchors.fill: parent
        visible: root.alarmed || shape.hasImage
        size: root.width
        restShape: root.critical ? "burst" : "cookie9"
        source: root.imageSource
        iconName: root.alarmed && root.material ? root.fallbackIcon.substring(root.materialPrefix.length) : ""
        smoothGlyph: true
        // An alert on its tones (IslandKit.alertTones); a plain logo on the tone that contrasts with it.
        shapeColor: root.tones ? root.tones[0] : shape.logoShapeColor
        iconColor: root.tones ? root.tones[1] : Theme.surfaceText
    }

    Loader {
        anchors.centerIn: parent
        width: Math.round(parent.width * shape.glyphShare)
        height: width
        active: root.alarmed && !shape.hasImage && !root.material && (root.fallbackIcon !== "" || root.fallbackText !== "")
        sourceComponent: AppIconRenderer {
            // No icon at all: the sender's initial, as the round fallback shows it; text, so on the 4.5:1 tone.
            iconValue: root.fallbackIcon || "unicode:" + root.fallbackText
            iconSize: width
            iconColor: root.tones?.[2] ?? shape.iconColor
            materialIconSizeAdjustment: 0
            fallbackText: root.fallbackText
            fallbackBackgroundColor: "transparent"
            fallbackTextColor: root.tones?.[2] ?? shape.iconColor
        }
    }
}
