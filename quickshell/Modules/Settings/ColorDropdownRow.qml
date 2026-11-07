pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    readonly property bool isSettingsRow: true

    property string text: ""
    property string description: ""
    property string settingKey: ""
    property string tab: ""
    property var tags: []
    property var options: []
    property string currentMode: "default"
    property color customColor: "#6750A4"
    property string pickerTitle: text
    property int dropdownWidth: 230
    property color defaultColor: Theme.primary

    readonly property var optionColorMap: {
        var map = {};
        for (var i = 0; i < options.length; i++) {
            const option = options[i];
            map[option.label] = option.previewColor ?? root.colorForValue(option.value);
        }
        return map;
    }

    function colorForValue(value) {
        switch (value) {
        case "custom":
            return root.customColor;
        case "none":
            return "transparent";
        case "default":
            return root.defaultColor;
        default:
            return Theme.roleColor(value);
        }
    }

    property alias resetStore: modeRow.resetStore
    property alias resetKeys: modeRow.resetKeys
    property alias modified: modeRow.modified
    property alias resetByKeys: modeRow.resetByKeys

    signal resetRequested
    signal modeSelected(string mode)
    signal customColorSelected(color selectedColor)

    width: parent?.width ?? 0
    spacing: 0

    function optionLabels() {
        return options.map(option => option.label);
    }

    function optionLabel(value) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].value === value)
                return options[i].label;
        }
        return options.length > 0 ? options[0].label : "";
    }

    function optionValue(label) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].label === label)
                return options[i].value;
        }
        return options.length > 0 ? options[0].value : "default";
    }

    function openCustomColorPicker() {
        PopoutService.colorPickerModal.selectedColor = root.customColor;
        PopoutService.colorPickerModal.pickerTitle = root.pickerTitle;
        PopoutService.colorPickerModal.onColorSelectedCallback = function (selectedColor) {
            root.customColorSelected(selectedColor);
            root.modeSelected("custom");
        };
        PopoutService.colorPickerModal.show();
    }

    SettingsDropdownRow {
        id: modeRow
        groupItem: root
        onResetRequested: root.resetRequested()
        text: root.text
        description: root.description
        tab: root.tab
        settingKey: root.settingKey
        tags: root.tags
        options: root.optionLabels()
        optionColorMap: root.optionColorMap
        currentValue: root.optionLabel(root.currentMode)
        dropdownWidth: root.dropdownWidth
        paintBackground: !(root.parent?.isSettingsGroupHost ?? false)
        onValueChanged: value => root.modeSelected(root.optionValue(value))
    }

    Item {
        width: parent.width
        height: root.currentMode === "custom" ? customChip.y + customChip.height + Theme.spacingM : 0
        opacity: root.currentMode === "custom" ? 1 : 0
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: SettingsMetrics.transitionDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: SettingsMetrics.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        Rectangle {
            id: customChip

            x: SettingsMetrics.rowPaddingH
            y: Theme.focusRingOffset
            width: parent.width - SettingsMetrics.rowPaddingH * 2
            height: Theme.listItemHeight
            radius: Theme.cornerRadiusM
            color: SettingsMetrics.controlColor
            activeFocusOnTab: root.currentMode === "custom"
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("Custom color")
            Accessible.onPressAction: root.openCustomColorPicker()
            Keys.onSpacePressed: root.openCustomColorPicker()
            Keys.onReturnPressed: root.openCustomColorPicker()
            Keys.onEnterPressed: root.openCustomColorPicker()

            FocusRing {
                id: chipRing
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: SettingsMetrics.rowPaddingH
                anchors.rightMargin: SettingsMetrics.rowPaddingH
                spacing: Theme.spacingM
                opacity: root.enabled ? 1 : SettingsMetrics.disabledOpacity

                DColorSwatch {
                    width: Theme.avatarSize
                    height: Theme.avatarSize
                    swatchColor: root.customColor
                    anchors.verticalCenter: parent.verticalCenter

                    DIcon {
                        anchors.centerIn: parent
                        name: "colorize"
                        size: Theme.iconSizeSmall
                        color: Theme.isLightColor(root.customColor) ? Theme.contrastDark : Theme.contrastLight
                    }
                }

                Column {
                    width: parent.width - Theme.avatarSize - editIcon.width - Theme.spacingM * 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Custom color")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        width: parent.width
                        horizontalAlignment: Text.AlignLeft
                    }

                    StyledText {
                        text: root.customColor.toString()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        width: parent.width
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                    }
                }

                DIcon {
                    id: editIcon
                    name: "edit"
                    size: Theme.iconSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StateLayer {
                stateColor: Theme.surfaceText
                cornerRadius: customChip.radius
                focused: chipRing.visible
                onClicked: {
                    chipRing.pointerFocused = true;
                    customChip.forceActiveFocus(Qt.MouseFocusReason);
                    root.openCustomColorPicker();
                }
            }
        }
    }
}
