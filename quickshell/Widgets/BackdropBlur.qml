import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services

// Frosted-glass backdrop: blurs the region of sourceItem directly behind the item
Item {
    id: root

    property Item sourceItem: null
    property real radius: Theme.cornerRadius
    property real blurAmount: 1.0
    property int blurMax: 96
    property bool active: BlurService.enabled

    readonly property bool blurActive: visible && active

    ShaderEffectSource {
        id: snapshot
        anchors.fill: parent
        sourceItem: root.sourceItem
        sourceRect: {
            if (!root.sourceItem)
                return Qt.rect(0, 0, 0, 0);
            const p = root.mapToItem(root.sourceItem, 0, 0);
            return Qt.rect(p.x, p.y, root.width, root.height);
        }
        live: root.blurActive
        hideSource: false
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: snapshot
        visible: root.blurActive
        blurEnabled: root.blurActive
        blurMax: root.blurMax
        autoPaddingEnabled: false
        blur: root.blurAmount
        maskEnabled: true
        maskSource: maskRect
    }

    Rectangle {
        id: maskRect
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: root.blurActive
    }
}
