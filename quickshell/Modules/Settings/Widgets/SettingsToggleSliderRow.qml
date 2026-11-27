pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

Item {
    id: root

    readonly property bool isSettingsRow: true

    property string tab: ""
    property var tags: []
    property string settingKey: ""

    property string text: ""
    property string description: ""
    property string sliderText: ""
    property bool checked: false
    property bool sliderVisible: true
    property real value: 0
    property alias minimum: sliderRow.minimum
    property alias maximum: sliderRow.maximum
    property alias step: sliderRow.step
    property alias unit: sliderRow.unit
    property alias decimals: sliderRow.decimals
    property bool userToggled: false

    property alias resetStore: header.resetStore
    property var accessoryKeys: []
    property var valueKeys: []
    property alias modified: header.modified
    property bool valueModified: valueKeys.length > 0 && !resetStore.isDefault(valueKeys)
    property alias accessory: header.accessory

    readonly property bool standalone: !(parent?.isSettingsGroupHost ?? false)
    readonly property bool firstInGroup: standalone || parent.isEdge(root, true)
    readonly property bool lastInGroup: standalone || parent.isEdge(root, false)

    signal toggled(bool checked)
    signal sliderValueChanged(int newValue)
    signal sliderDragFinished(int finalValue)
    signal resetRequested
    signal valueResetRequested

    width: parent?.width ?? 0
    height: column.height

    Rectangle {
        anchors.fill: parent
        radius: Theme.groupedListOuterRadius
        color: SettingsMetrics.rowColor
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        visible: root.standalone
    }

    Column {
        id: column
        width: parent.width

        SettingsToggleRow {
            id: header
            width: parent.width
            topRadius: root.firstInGroup ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            bottomRadius: root.lastInGroup && !root.checked ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            tab: root.tab
            tags: root.tags
            settingKey: root.settingKey
            modified: root.checked && root.accessoryKeys.length > 0 && !resetStore.isDefault(root.accessoryKeys)
            onResetRequested: {
                resetStore.resetToDefault(root.accessoryKeys);
                root.resetRequested();
            }
            text: root.text
            description: root.description
            checked: root.checked
            paintBackground: false
            onToggled: value => {
                root.userToggled = true;
                root.toggled(value);
            }
        }

        // The slider sits outside the header so presses around it never reach the header's toggle click area
        Item {
            width: parent.width
            visible: root.sliderVisible && (root.checked || height > 0)
            height: root.sliderVisible && root.checked ? sliderRow.height : 0
            clip: true

            Behavior on height {
                enabled: root.userToggled
                NumberAnimation {
                    duration: SettingsMetrics.expandDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                    onRunningChanged: {
                        if (!running)
                            root.userToggled = false;
                    }
                }
            }

            SettingsSliderRow {
                id: sliderRow
                width: parent.width
                paintBackground: false
                topRadius: SettingsMetrics.groupInnerRadius
                bottomRadius: root.lastInGroup ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
                enabled: root.checked
                text: root.sliderText
                accessibleName: root.text + " " + root.sliderText
                value: root.value
                resetStore: root.resetStore
                resetKeys: root.valueKeys
                modified: root.valueModified
                onResetRequested: root.valueResetRequested()
                onSliderValueChanged: newValue => root.sliderValueChanged(newValue)
                onSliderDragFinished: finalValue => root.sliderDragFinished(finalValue)
            }
        }
    }
}
