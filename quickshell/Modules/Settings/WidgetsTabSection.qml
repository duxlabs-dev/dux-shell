pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Settings.Widgets
import "../DBar/OverflowLayout.js" as OverflowLayout

Column {
    id: root
    readonly property var log: Log.scoped("WidgetsTabSection")

    Component.onCompleted: DgopService.ensureMeta()

    property var items: []
    property var allWidgets: []
    property string title: ""
    property string sectionId: ""
    property string barId: ""
    property bool overflowSettingsExpanded: false
    readonly property var barConfig: SettingsData.getBarConfig(barId)
    readonly property bool autoOverflow: barConfig?.[sectionId + "OverflowMode"] !== "bar"
    readonly property int overflowPosition: barConfig?.[sectionId + "OverflowPosition"] ?? OverflowLayout.defaultPosition(sectionId, items.length)
    // An omitted key is the default; resetting clears it so the position keeps following the widget count.
    readonly property var overflowStore: ({
            "isDefault": keys => keys.every(key => (root.barConfig?.[key] ?? root.overflowDefault(key)) === root.overflowDefault(key)),
            "resetToDefault": keys => root.clearOverflowOptions(keys)
        })

    function overflowDefault(key) {
        return key.endsWith("Mode") ? "auto" : OverflowLayout.defaultPosition(sectionId, items.length);
    }

    function clearOverflowOptions(keys) {
        const patch = {};
        for (const key of keys)
            patch[key] = undefined;
        SettingsData.updateBarConfig(barId, patch);
    }

    function setOverflowOption(name, value) {
        SettingsData.updateBarConfig(barId, {
            [sectionId + "Overflow" + name]: value
        });
    }

    signal itemEnabledChanged(string sectionId, string itemId, bool enabled)
    signal itemOrderChanged(string sectionId, var indices)
    signal addWidget(string sectionId)
    signal removeWidget(string sectionId, int widgetIndex)
    signal spacerSizeChanged(string sectionId, int widgetIndex, int newSize)
    signal configureWidget(string sectionId, int widgetIndex)

    signal dragStarted(string sectionId, string itemId)

    property var reorderGroup: null
    property string highlightedId: ""
    property string highlightedSection: ""

    width: parent.width
    height: implicitHeight
    spacing: Theme.spacingM

    SettingsSectionLabel {
        text: root.title
        actions: [
            DActionButton {
                buttonSize: Theme.buttonHeightXXS
                iconName: "more_horiz"
                tooltipText: I18n.tr("Overflow")
                Accessible.name: root.title + ": " + I18n.tr("Overflow")
                iconSize: Theme.iconSizeSmall
                iconColor: root.overflowSettingsExpanded ? Theme.primary : Theme.outline
                visible: root.barId !== ""
                onClicked: root.overflowSettingsExpanded = !root.overflowSettingsExpanded
            },
            DActionButton {
                buttonSize: Theme.buttonHeightXXS
                iconName: "format_list_numbered"
                tooltipText: I18n.tr("Index centering")
                iconSize: Theme.iconSizeSmall
                iconColor: SettingsData.centeringMode === "index" ? Theme.primary : Theme.outline
                visible: root.sectionId === "center"
                onClicked: SettingsData.set("centeringMode", "index")
            },
            DActionButton {
                buttonSize: Theme.buttonHeightXXS
                iconName: "center_focus_weak"
                tooltipText: I18n.tr("Geometric centering")
                iconSize: Theme.iconSizeSmall
                iconColor: SettingsData.centeringMode === "geometric" ? Theme.primary : Theme.outline
                visible: root.sectionId === "center"
                onClicked: SettingsData.set("centeringMode", "geometric")
            }
        ]
    }

    SettingsCard {
        visible: root.overflowSettingsExpanded
        title: I18n.tr("Overflow")

        SettingsToggleRow {
            text: I18n.tr("Auto overflow")
            description: I18n.tr("Widgets in this section move into overflow when space runs out", "bar section overflow description")
            checked: root.autoOverflow
            onToggled: checked => root.setOverflowOption("Mode", checked ? "auto" : "bar")
        }

        SettingsDropdownRow {
            readonly property var positionLabels: {
                const labels = [I18n.tr("Start", "noun, overflow button position before the first widget", true)];
                const seen = {};
                for (const item of root.items) {
                    seen[item.text] = (seen[item.text] ?? 0) + 1;
                    labels.push(I18n.tr("After %1", "overflow button position option, %1 is a widget name").arg(seen[item.text] > 1 ? item.text + " " + seen[item.text] : item.text));
                }
                return labels;
            }

            text: I18n.tr("Overflow button position", "bar section dropdown label")
            resetStore: root.overflowStore
            resetKeys: [root.sectionId + "OverflowPosition"]
            options: positionLabels
            currentValue: positionLabels[Math.min(root.overflowPosition, positionLabels.length - 1)]
            onValueChanged: value => root.setOverflowOption("Position", positionLabels.indexOf(value))
        }
    }

    SettingsReorderList {
        id: reorderArea

        model: root.items
        group: root.reorderGroup
        groupKey: root.sectionId
        dropArea: root
        onReordered: indices => root.itemOrderChanged(root.sectionId, indices)
        onDragStarted: (index, position) => root.dragStarted(root.sectionId, root.items[index].id)

        delegate: SettingsReorderRow {
            id: widgetRow

            required property var modelData

            readonly property bool configurable: BarWidgetCatalog.configurable(modelData)

            reorderList: reorderArea
            highlighted: !dragging && root.highlightedId === modelData.id && root.highlightedSection === root.sectionId
            opacity: dragging && reorderArea.crossSectionActive ? 0 : 1
            title: modelData.text
            iconName: modelData.icon
            iconColor: modelData.enabled ? Theme.primary : Theme.onSurfaceVariant
            titleColor: modelData.enabled ? Theme.onSurface : Theme.onSurfaceVariant
            subtitle: {
                if (modelData.id !== "gpuTemp")
                    return modelData.description ?? "";
                const selectedIndex = modelData.selectedGpuIndex ?? 0;
                const gpu = DgopService.availableGpus?.[selectedIndex];
                if (!gpu)
                    return I18n.tr("No GPU detected", "empty state when no graphics card is found");
                return gpu.driver?.toUpperCase() ?? "";
            }
            clickable: configurable
            onClicked: root.configureWidget(root.sectionId, index)

            Item {
                width: Theme.iconButtonSize
                height: Theme.iconButtonSize
                visible: !!widgetRow.modelData.warning
                anchors.verticalCenter: parent.verticalCenter

                DIcon {
                    name: "warning"
                    size: Theme.iconSizeMedium
                    color: Theme.error
                    anchors.centerIn: parent
                }

                MouseArea {
                    id: warningArea
                    anchors.fill: parent
                    hoverEnabled: true
                }

                DTooltipHost {
                    text: widgetRow.modelData.warning
                    target: parent
                    hoverArea: warningArea
                }
            }

            DIcon {
                name: "chevron_right"
                size: Theme.iconSize
                color: Theme.onSurfaceVariant
                rotation: I18n.isRtl ? 180 : 0
                visible: widgetRow.configurable
                anchors.verticalCenter: parent.verticalCenter
            }

            SettingsDivider {
                vertical: true
                visible: widgetRow.configurable
            }

            DNumberStepper {
                visible: widgetRow.modelData.id === "spacer"
                anchors.verticalCenter: parent.verticalCenter
                text: (widgetRow.modelData.size || 20).toString()
                decrementEnabled: (widgetRow.modelData.size || 20) > 5
                incrementEnabled: (widgetRow.modelData.size || 20) < 5000
                onDecrement: () => root.spacerSizeChanged(root.sectionId, widgetRow.index, Math.max(5, (widgetRow.modelData.size || 20) - 5))
                onIncrement: () => root.spacerSizeChanged(root.sectionId, widgetRow.index, Math.min(5000, (widgetRow.modelData.size || 20) + 5))
            }

            DToggle {
                hideText: true
                visible: widgetRow.modelData.id !== "spacer"
                checked: widgetRow.modelData.enabled
                anchors.verticalCenter: parent.verticalCenter
                onToggled: value => root.itemEnabledChanged(root.sectionId, widgetRow.modelData.id, value)
            }

            DActionButton {
                iconName: "close"
                iconColor: Theme.error
                Accessible.name: I18n.tr("Remove")
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.removeWidget(root.sectionId, widgetRow.index)
            }
        }
    }

    DButton {
        anchors.horizontalCenter: parent.horizontalCenter
        text: I18n.tr("Add widget")
        iconName: "add"
        backgroundColor: Theme.secondaryContainer
        textColor: Theme.onSecondaryContainer
        onClicked: root.addWidget(root.sectionId)
    }
}
