pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

// The value is a DMS theme role ("primary", "secondary", "tertiary") so it follows theme changes, or a "#rrggbb" picked by hand.
NiriRow {
    id: root

    readonly property var roles: ["primary", "secondary", "tertiary"]
    readonly property string current: typeof value === "string" ? value : ""
    readonly property bool custom: current.startsWith("#")

    function roleColor(role) {
        return role === "secondary" ? Theme.secondary : role === "tertiary" ? Theme.tertiary : Theme.primary;
    }

    function roleName(role) {
        return role === "secondary" ? I18n.tr("Secondary") : role === "tertiary" ? I18n.tr("Tertiary") : I18n.tr("Primary");
    }

    function pick() {
        const modal = PopoutService.colorPickerModal;
        modal.selectedColor = root.custom ? root.current : Theme.primary;
        modal.pickerTitle = root.title;
        modal.onColorSelectedCallback = selected => root.write(selected.toString());
        modal.show();
    }

    toggle: false
    tryValue: custom ? roles[0] : roles[(roles.indexOf(current) + 1) % roles.length]

    component Swatch: Item {
        id: swatch

        property color fill
        property bool selected
        property bool filled: true
        property string iconName: ""
        property string label: ""
        signal picked

        anchors.verticalCenter: parent.verticalCenter
        width: Theme.minimumTouchTargetSize - Theme.spacingXS
        height: width
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.checkable: true
        Accessible.checked: selected
        Accessible.onPressAction: picked()
        Keys.onSpacePressed: picked()
        Keys.onReturnPressed: picked()

        Rectangle {
            anchors.centerIn: parent
            visible: swatch.selected
            width: Theme.iconSize + Theme.spacingS * 2 + Theme.outlineWidthFocused * 2
            height: width
            radius: width / 2
            color: Theme.withAlpha(Theme.surfaceText, 0)
            border.width: Theme.outlineWidthFocused
            border.color: Theme.surfaceText
        }

        DColorSwatch {
            anchors.centerIn: parent
            visible: swatch.filled
            width: Theme.iconSize + Theme.spacingXS
            height: width
            swatchColor: swatch.fill
            ringColor: Theme.outlineVariant
        }

        DIcon {
            anchors.centerIn: parent
            visible: !swatch.filled
            name: swatch.iconName
            size: Theme.iconSizeMedium
            color: Theme.surfaceVariantText
        }

        FocusRing {
            radius: width / 2
        }

        StateLayer {
            id: swatchState
            anchors.fill: parent
            cornerRadius: width / 2
            stateColor: Theme.primary
            tooltipText: swatch.label
            onClicked: swatch.picked()
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            model: root.roles

            Swatch {
                required property string modelData
                fill: root.roleColor(modelData)
                selected: root.current === modelData
                label: I18n.tr("%1, from the DMS theme").arg(root.roleName(modelData))
                onPicked: root.write(modelData)
            }
        }

        Swatch {
            fill: root.custom ? root.current : Theme.primary
            filled: root.custom
            selected: root.custom
            iconName: "colorize"
            label: I18n.tr("Pick a color")
            onPicked: root.pick()
        }
    }
}
