pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    property int selected: SettingsData.Position.BottomCenter
    readonly property var positions: [SettingsData.Position.Left, SettingsData.Position.TopCenter, SettingsData.Position.Top, SettingsData.Position.LeftCenter, SettingsData.Position.RightCenter, SettingsData.Position.Bottom, SettingsData.Position.BottomCenter, SettingsData.Position.Right]
    readonly property real edgeSlotLength: 0.26
    readonly property real sideSlotLength: 0.42
    readonly property real slotThickness: 0.1
    readonly property rect selectedArea: slotRect(selected)
    property int placedPosition: -1

    signal picked(int position)

    width: parent?.width ?? 0
    implicitHeight: screenMock.height
    height: implicitHeight
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    onSelectedAreaChanged: placeIndicator()
    Component.onCompleted: placeIndicator()

    function labelFor(position) {
        switch (position) {
        case SettingsData.Position.Top:
            return I18n.tr("Top Right", "screen position option");
        case SettingsData.Position.Left:
            return I18n.tr("Top Left", "screen position option");
        case SettingsData.Position.TopCenter:
            return I18n.tr("Top Center", "screen position option");
        case SettingsData.Position.Right:
            return I18n.tr("Bottom Right", "screen position option");
        case SettingsData.Position.Bottom:
            return I18n.tr("Bottom Left", "screen position option");
        case SettingsData.Position.LeftCenter:
            return I18n.tr("Left Center", "screen position option");
        case SettingsData.Position.RightCenter:
            return I18n.tr("Right Center", "screen position option");
        default:
            return I18n.tr("Bottom Center", "screen position option");
        }
    }

    function cellFor(position) {
        switch (position) {
        case SettingsData.Position.Left:
            return Qt.point(0, 0);
        case SettingsData.Position.TopCenter:
            return Qt.point(1, 0);
        case SettingsData.Position.Top:
            return Qt.point(2, 0);
        case SettingsData.Position.LeftCenter:
            return Qt.point(0, 1);
        case SettingsData.Position.RightCenter:
            return Qt.point(2, 1);
        case SettingsData.Position.Bottom:
            return Qt.point(0, 2);
        case SettingsData.Position.Right:
            return Qt.point(2, 2);
        default:
            return Qt.point(1, 2);
        }
    }

    function slotRect(position) {
        const cell = cellFor(position);
        const side = cell.y === 1;
        const inset = screenMock.inset;
        const w = Math.round(side ? screenMock.height * slotThickness : screenMock.width * edgeSlotLength);
        const h = Math.round(screenMock.height * (side ? sideSlotLength : slotThickness));
        const x = cell.x === 0 ? inset : cell.x === 2 ? screenMock.width - w - inset : Math.round((screenMock.width - w) / 2);
        const y = cell.y === 0 ? inset : cell.y === 2 ? screenMock.height - h - inset : Math.round((screenMock.height - h) / 2);
        return Qt.rect(x, y, w, h);
    }

    function neighbor(position, dx, dy) {
        const from = cellFor(position);
        let best = -1;
        let bestCost = Infinity;
        for (const candidate of positions) {
            const cell = cellFor(candidate);
            const along = dx !== 0 ? (cell.x - from.x) * dx : (cell.y - from.y) * dy;
            if (along <= 0)
                continue;
            const cost = along + 2 * (dx !== 0 ? Math.abs(cell.y - from.y) : Math.abs(cell.x - from.x));
            if (cost >= bestCost)
                continue;
            best = candidate;
            bestCost = cost;
        }
        return best;
    }

    function step(from, dx, dy) {
        const next = neighbor(from, dx, dy);
        if (next < 0)
            return;
        picked(next);
        slotRepeater.itemAt(positions.indexOf(next))?.forceActiveFocus(Qt.TabFocusReason);
    }

    function placeIndicator() {
        const animate = placedPosition >= 0 && placedPosition !== selected;
        placedPosition = selected;
        if (animate)
            indicatorSpring.retarget(selectedArea);
        else
            indicatorSpring.snapTo(selectedArea);
    }

    RectSpringMotion {
        id: indicatorSpring
        enabled: !Theme.springMotionDisabled
        reducedMotion: SettingsData.reduceMotion
        stiffness: Theme.springPreset("fast", Theme.expressiveDurations.expressiveFastSpatial).stiffness
        damping: Theme.springPreset("fast", Theme.expressiveDurations.expressiveFastSpatial).damping
    }

    Rectangle {
        id: screenMock

        readonly property real inset: Theme.spacingS

        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.width, SettingsMetrics.positionPickerMaxWidth)
        height: Math.round(width * SettingsMetrics.choiceCardPreviewRatio)
        radius: Theme.cornerRadiusM
        color: SettingsMetrics.controlColor
        border.width: Theme.outlineWidth
        border.color: Theme.outlineVariant

        Repeater {
            model: root.positions

            Rectangle {
                required property int modelData
                readonly property rect area: root.slotRect(modelData)

                x: area.x
                y: area.y
                width: area.width
                height: area.height
                radius: Theme.fullRadius(width, height)
                color: root.enabled ? Theme.outlineVariant : Theme.onSurface_12
            }
        }

        Rectangle {
            readonly property real inset: screenMock.inset

            width: indicatorSpring.value.width
            height: indicatorSpring.value.height
            x: Math.max(inset, Math.min(indicatorSpring.value.x, screenMock.width - width - inset))
            y: Math.max(inset, Math.min(indicatorSpring.value.y, screenMock.height - height - inset))
            radius: Theme.fullRadius(width, height)
            color: root.enabled ? Theme.primary : Theme.onSurface_38
        }

        Repeater {
            id: slotRepeater
            model: root.positions

            StyledButton {
                id: slot

                required property int modelData
                readonly property rect area: root.slotRect(modelData)
                readonly property bool isSelected: modelData === root.selected
                readonly property real touchPad: Math.max(0, (Theme.buttonHeightS - Math.min(area.width, area.height)) / 2)

                x: area.x - touchPad
                y: area.y - touchPad
                width: area.width + touchPad * 2
                height: area.height + touchPad * 2
                focusPolicy: isSelected || activeFocus ? Qt.StrongFocus : Qt.ClickFocus
                Accessible.role: Accessible.RadioButton
                Accessible.name: root.labelFor(modelData)
                Accessible.checked: isSelected
                onClicked: root.picked(modelData)
                Keys.onLeftPressed: root.step(modelData, -1, 0)
                Keys.onRightPressed: root.step(modelData, 1, 0)
                Keys.onUpPressed: root.step(modelData, 0, -1)
                Keys.onDownPressed: root.step(modelData, 0, 1)

                Rectangle {
                    anchors.centerIn: parent
                    width: slot.area.width
                    height: slot.area.height
                    radius: Theme.fullRadius(width, height)
                    color: "transparent"

                    StateLayer {
                        control: slot
                        disabled: !slot.enabled
                        stateColor: slot.isSelected ? Theme.onPrimary : Theme.onSurface
                    }

                    FocusRing {
                        visible: slot.visualFocus
                    }
                }
            }
        }
    }
}
