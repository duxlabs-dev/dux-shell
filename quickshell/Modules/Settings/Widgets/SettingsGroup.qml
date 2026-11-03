pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

Item {
    id: root

    readonly property bool isSettingsGroup: true
    default property alias content: host.data
    property real spacing: SettingsMetrics.groupGap
    property real customPaddingH: SettingsMetrics.rowPaddingH
    property real customPaddingV: SettingsMetrics.rowPaddingV
    property bool highlighted: false
    property color slotColor: SettingsMetrics.rowColor
    property var slots: []
    property bool layingOut: false
    property bool layoutReady: false

    width: parent?.width ?? 0
    implicitHeight: 0
    height: implicitHeight

    onWidthChanged: root.layout()
    onSpacingChanged: root.layout()
    onCustomPaddingHChanged: root.layout()
    onCustomPaddingVChanged: root.layout()
    onVisibleChanged: root.layout()
    Component.onCompleted: {
        layoutReady = true;
        layout();
    }
    Component.onDestruction: layoutReady = false

    function isRowContainer(c) {
        const kids = c.visibleChildren;
        if (!kids || kids.length === 0)
            return false;
        for (let i = 0; i < kids.length; i++) {
            if (kids[i].isSettingsRow !== true && typeof kids[i].itemAt !== "function")
                return false;
        }
        return true;
    }

    function sameSlots(a, b) {
        if (a.length !== b.length)
            return false;
        for (let i = 0; i < a.length; i++) {
            if (a[i].item !== b[i].item || a[i].y !== b[i].y || a[i].height !== b[i].height || a[i].transparent !== b[i].transparent)
                return false;
        }
        return true;
    }

    function layout() {
        if (!layoutReady || !visible || layingOut)
            return;
        layingOut = true;
        const items = [];
        for (let i = 0; i < host.children.length; i++) {
            const c = host.children[i];
            if (!c.visible || (c.isSettingsRow !== true && typeof c.itemAt === "function"))
                continue;
            if (c.isSettingsRow === true) {
                items.push(c);
                continue;
            }
            if (c.height <= 1 && c.children.length === 0 && c.border !== undefined) {
                c.height = 0;
                continue;
            }
            if (c.height <= 0)
                continue;
            items.push(c);
        }
        let y = 0;
        const next = [];
        for (let i = 0; i < items.length; i++) {
            const c = items[i];
            const container = c.isSettingsRow !== true && isRowContainer(c);
            const custom = c.isSettingsRow !== true && !container;
            const top = y;
            if (custom) {
                c.x = customPaddingH;
                c.width = root.width - customPaddingH * 2;
                c.y = top + customPaddingV;
            } else {
                c.x = 0;
                c.width = root.width;
                c.y = top;
            }
            const h = c.height + (custom ? customPaddingV * 2 : 0);
            next.push({
                "item": c,
                "y": top,
                "height": h,
                "transparent": c.transparentSlot === true || container
            });
            y += h + spacing;
        }
        if (!sameSlots(slots, next))
            slots = next;
        implicitHeight = Math.max(0, y - spacing);
        layingOut = false;
    }

    Repeater {
        model: root.slots.length

        Rectangle {
            required property int index
            readonly property var slot: root.slots[index]
            readonly property bool first: index === 0
            readonly property bool last: index === root.slots.length - 1

            z: -1
            x: 0
            y: slot.y
            width: root.width
            height: slot.height
            visible: !slot.transparent
            topLeftRadius: first ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            topRightRadius: first ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            bottomLeftRadius: last ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            bottomRightRadius: last ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            color: root.highlighted ? Theme.blend(root.slotColor, Theme.primary, SettingsMetrics.highlightBlend) : root.slotColor
            border.width: SettingsMetrics.groupEdgeWidth
            border.color: Theme.outlineMedium

            Rectangle {
                x: SettingsMetrics.rowPaddingH
                width: parent.width - SettingsMetrics.rowPaddingH * 2
                height: Theme.dividerWidth
                visible: SettingsMetrics.continuousGroups && !parent.first
                color: SettingsMetrics.groupDividerColor
            }

            Behavior on color {
                enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                ColorAnimation {
                    duration: SettingsMetrics.fadeDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 1
        radius: Theme.groupedListOuterRadius
        color: "transparent"
        border.width: SettingsMetrics.groupFrameWidth
        border.color: Theme.outlineMedium
        visible: border.width > 0
    }

    Item {
        id: host

        readonly property bool isSettingsGroupHost: true

        function isEdge(item, first) {
            const slot = root.slots[first ? 0 : root.slots.length - 1];
            return slot?.item === item;
        }

        anchors.left: parent.left
        anchors.right: parent.right
        height: root.implicitHeight

        onChildrenChanged: root.layout()
    }

    Instantiator {
        model: host.children.length

        QtObject {
            required property int index
            readonly property Item child: host.children[index] ?? null
            readonly property bool childVisible: child?.visible ?? false
            readonly property real childHeight: child?.height ?? 0

            onChildVisibleChanged: root.layout()
            onChildHeightChanged: root.layout()
        }
    }
}
