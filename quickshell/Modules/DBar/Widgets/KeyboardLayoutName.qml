import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import "KeyboardLayoutLabels.js" as KeyboardLayoutLabels

BasePill {
    id: root

    property var widgetData: null
    property bool compactMode: SettingsData.widgetOption("keyboard_layout_name", widgetData, "keyboardLayoutNameCompactMode")
    property bool showIcon: SettingsData.widgetOption("keyboard_layout_name", widgetData, "keyboardLayoutNameShowIcon")
    readonly property var labelOverrides: SettingsData.widgetOption("keyboard_layout_name", widgetData, "keyboardLayoutNameLabelOverrides") ?? ({})
    readonly property var validVariants: KeyboardLayoutLabels.VALID_VARIANTS
    readonly property bool codesOnly: KeyboardLayoutService.namesAreXkbCodes
    readonly property string currentLayout: compactMode ? KeyboardLayoutService.compactLayout : KeyboardLayoutService.currentLayout
    readonly property var _allLayoutLabels: (compactMode || !codesOnly ? KeyboardLayoutService.layoutNames : []).map(n => displayLabel(n))
    readonly property var _allVerticalLabels: (compactMode || !codesOnly ? KeyboardLayoutService.layoutNames : []).map(n => verticalLabel(n))

    Component.onCompleted: KeyboardLayoutService.consumers++
    Component.onDestruction: KeyboardLayoutService.consumers--

    function widestLabel(labels, metrics) {
        let widest = "";
        let widestWidth = 0;
        for (const label of labels) {
            const width = metrics.advanceWidth(label);
            if (width <= widestWidth)
                continue;
            widest = label;
            widestWidth = width;
        }
        return widest;
    }

    function displayLabel(layoutName) {
        return KeyboardLayoutLabels.displayLabel(layoutName, compactMode, codesOnly, validVariants, labelOverrides);
    }

    function verticalLabel(layoutName) {
        return KeyboardLayoutLabels.verticalLabel(layoutName, labelOverrides);
    }

    content: Component {
        Item {
            implicitWidth: root.isVerticalOrientation ? root.contentThickness : contentRow.implicitWidth
            implicitHeight: root.isVerticalOrientation ? contentColumn.implicitHeight : root.contentThickness

            FontMetrics {
                id: labelMetrics
                font: horizontalLabel.font
            }

            Column {
                id: contentColumn
                visible: root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: 1

                DIcon {
                    name: "keyboard"
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: root.contentColor
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.showIcon
                }

                NumericText {
                    text: root.verticalLabel(root.currentLayout)
                    reserveText: root.widestLabel(root._allVerticalLabels, labelMetrics)
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: root.contentColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Row {
                id: contentRow
                visible: !root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DIcon {
                    name: "keyboard"
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: root.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showIcon
                }

                NumericText {
                    id: horizontalLabel

                    text: root.displayLabel(root.currentLayout)
                    reserveText: root.widestLabel(root._allLayoutLabels, labelMetrics)
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: root.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    MouseArea {
        z: 1
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.triggerRipple(this, mouse.x, mouse.y);
        }
        onClicked: KeyboardLayoutService.cycle()
    }
}
