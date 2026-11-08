import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.DCommon.Widgets
import "../utils/widgets.js" as WidgetUtils

Rectangle {
    id: root

    property var widgets: []
    readonly property var matches: WidgetUtils.filterWidgets(widgets, searchField.text)

    signal chosen(string widgetId)
    signal dismissed

    function reset() {
        searchField.text = "";
        widgetList.positionViewAtBeginning();
        searchField.forceActiveFocus();
    }

    implicitWidth: CcMetrics.libraryPanelWidth
    implicitHeight: CcMetrics.libraryPanelHeight
    radius: Theme.windowRadius
    color: Theme.readableSurface
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => mouse.accepted = true
    }

    Item {
        anchors.fill: parent
        anchors.margins: Theme.spacingL

        Row {
            id: headerRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Theme.spacingM

            DIcon {
                name: "add_circle"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: I18n.tr("Add widget")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        DSearchField {
            id: searchField
            anchors.top: headerRow.bottom
            anchors.topMargin: Theme.spacingM
            anchors.left: parent.left
            anchors.right: parent.right
            textColor: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            placeholderText: I18n.tr("Search widgets...")
            onAccepted: {
                if (root.matches.length > 0)
                    root.chosen(root.matches[0].id);
            }
            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Escape)
                    return;
                root.dismissed();
                event.accepted = true;
            }
        }

        DListView {
            id: widgetList

            anchors.top: searchField.bottom
            anchors.topMargin: Theme.spacingM
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Theme.groupedListGap
            clip: true
            model: root.matches

            delegate: CcListRow {
                required property var modelData
                required property int index

                width: widgetList.width
                iconName: modelData.icon
                title: modelData.text
                subtitle: modelData.description ?? ""
                clickable: true
                topRadius: index === 0 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                bottomRadius: index === widgetList.count - 1 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                onClicked: root.chosen(modelData.id)

                DIcon {
                    name: "add"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
