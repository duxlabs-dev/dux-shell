pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

FocusScope {
    id: root

    property var model: []
    property string currentKey: ""
    property int historyLength: 0
    property int hiddenCount: 0
    property bool showHidden: false

    signal selected(string key)
    signal showHiddenToggled

    // Virtual devices sit below the toggle, so the toggle stays where it was clicked.
    readonly property var shownEntries: (model ?? []).filter(e => !e.hidden)
    readonly property var hiddenEntries: (model ?? []).filter(e => e.hidden)

    function move(step) {
        const items = shownEntries.concat(hiddenEntries);
        if (items.length === 0)
            return;
        const current = items.findIndex(e => e.key === root.currentKey);
        const next = Math.max(0, Math.min(items.length - 1, current < 0 ? 0 : current + step));
        root.selected(items[next].key);
        const target = next < shownEntries.length ? entries.itemAt(next) : hiddenRows.itemAt(next - shownEntries.length);
        if (!target)
            return;
        target.children[1]?.forceActiveFocus(Qt.TabFocusReason);
        const top = target.y;
        const bottom = top + target.height;
        if (top < flick.contentY)
            flick.contentY = top;
        else if (bottom > flick.contentY + flick.height)
            flick.contentY = Math.min(bottom - flick.height, Math.max(0, flick.contentHeight - flick.height));
    }

    Keys.onUpPressed: event => {
        root.move(-1);
        event.accepted = true;
    }
    Keys.onDownPressed: event => {
        root.move(1);
        event.accepted = true;
    }

    component Rows: Repeater {
        id: rows

        required property var items

        model: rows.items.length

        Column {
            id: entry

            required property int index
            readonly property var modelData: rows.items[index] ?? ({})
            readonly property bool newGroup: !modelData.hidden && (index === 0 || (modelData.group ?? "") !== (rows.items[index - 1]?.group ?? ""))
            readonly property bool lastInGroup: index === rows.items.length - 1 || (modelData.group ?? "") !== (rows.items[index + 1]?.group ?? "")

            width: column.width

            SettingsSectionLabel {
                visible: entry.newGroup
                width: parent.width
                topGap: entry.index === 0 ? 0 : Theme.spacingL
                text: entry.modelData.group ?? ""
            }

            DListItem {
                id: item
                width: parent.width
                implicitHeight: Theme.listItemHeight
                isSelected: entry.modelData.key === root.currentKey
                firstInGroup: entry.newGroup || entry.index === 0
                lastInGroup: entry.lastInGroup
                Accessible.name: entry.modelData.name + ", " + (entry.modelData.value ?? "")
                onClicked: root.selected(entry.modelData.key)

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingL
                    anchors.rightMargin: Theme.spacingM

                    DeviceIcon {
                        id: deviceIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        name: entry.modelData.icon ?? ""
                        color: item.isSelected ? item.contentColor : item.supportingContentColor
                    }

                    Column {
                        anchors.left: deviceIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: spark.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            width: parent.width
                            text: entry.modelData.name ?? ""
                            color: item.contentColor
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        StyledText {
                            id: valueLabel
                            width: parent.width
                            text: entry.modelData.value ?? ""
                            color: item.supportingContentColor
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                            maximumLineCount: 1

                            MouseArea {
                                id: valueHover
                                anchors.fill: parent
                                enabled: (entry.modelData.valueTooltip ?? "") !== ""
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                cursorShape: Qt.PointingHandCursor
                            }

                            DTooltipHost {
                                text: entry.modelData.valueTooltip ?? ""
                                target: valueLabel
                                hoverArea: valueHover
                            }
                        }
                    }

                    MetricChart {
                        id: spark
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.iconButtonSize * 1.6
                        height: Theme.iconButtonSize * 0.7
                        compact: true
                        values: entry.modelData.values ?? []
                        secondaryValues: entry.modelData.secondaryValues ?? []
                        color: item.isSelected ? item.contentColor : Theme.primary
                        secondaryColor: item.isSelected ? item.supportingContentColor : Theme.tertiary
                        maximum: entry.modelData.maximum ?? 0
                        historyLength: root.historyLength
                    }
                }
            }
        }
    }

    DFlickable {
        id: flick
        clip: true
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight

        Column {
            id: column
            width: flick.width
            spacing: Theme.groupedListGap

            Rows {
                id: entries
                items: root.shownEntries
            }

            DButton {
                visible: root.hiddenCount > 0
                text: root.showHidden ? I18n.tr("Hide") : I18n.tr("Show virtual devices")
                backgroundColor: "transparent"
                textColor: Theme.primary
                onClicked: root.showHiddenToggled()
            }

            Rows {
                id: hiddenRows
                items: root.hiddenEntries
            }
        }
    }
}
