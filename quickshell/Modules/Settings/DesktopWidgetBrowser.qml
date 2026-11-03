pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

WidgetPickerWindow {
    id: root

    property string listKey: "desktopWidgetInstances"

    signal widgetAdded(string widgetType)

    function addWidget(widget) {
        const widgetType = widget.id;
        const defaultConfig = DesktopWidgetRegistry.getDefaultConfig(widgetType);
        const name = widget.name || widgetType;
        SettingsData.createDesktopWidgetInstance(widgetType, name, defaultConfig, listKey);
        root.widgetAdded(widgetType);
        root.hide();
    }

    objectName: "desktopWidgetBrowser"
    title: I18n.tr("Add Desktop Widget")
    widgets: DesktopWidgetRegistry.getListWidgets(listKey).filter(widget => listKey === "desktopWidgetInstances" ? true : (widget.id !== "lockAuth" && widget.id !== "greeterSession"))
    featuredFirst: true
    showEmptyState: true
    widgetDelegate: tileDelegate

    onWidgetChosen: widget => addWidget(widget)

    Component {
        id: tileDelegate

        DListItem {
            id: delegateRoot

            required property var modelData
            required property int index

            width: ListView.view.width
            implicitHeight: Theme.listItemTwoLineHeight
            isSelected: root.keyboardNavigationActive && index === root.selectedIndex
            Accessible.name: modelData.name || modelData.id
            onClicked: root.addWidget(delegateRoot.modelData)

            Row {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                Rectangle {
                    width: Theme.avatarSize
                    height: Theme.avatarSize
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.primary, Theme.tonalTintAlpha)
                    anchors.verticalCenter: parent.verticalCenter

                    DIcon {
                        anchors.centerIn: parent
                        name: delegateRoot.modelData.icon || "widgets"
                        size: Theme.iconSize
                        color: Theme.primary
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXXS
                    width: parent.width - Theme.avatarSize - Theme.iconSizeMedium - Theme.spacingM * 3

                    Row {
                        spacing: Theme.spacingS

                        StyledText {
                            text: delegateRoot.modelData.name || delegateRoot.modelData.id
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                        }

                        PluginBadge {
                            visible: delegateRoot.modelData.featured || false
                            iconName: "star"
                            label: I18n.tr("featured")
                            tone: Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        PluginBadge {
                            visible: delegateRoot.modelData.type === "plugin"
                            label: I18n.tr("Plugin")
                            tone: Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    StyledText {
                        text: delegateRoot.modelData.description || ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.outline
                        elide: Text.ElideRight
                        width: parent.width
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        visible: text !== ""
                    }
                }

                DIcon {
                    name: "add"
                    size: Theme.iconSizeMedium
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
