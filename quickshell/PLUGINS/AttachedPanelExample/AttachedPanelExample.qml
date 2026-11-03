import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    horizontalBarPill: Component {
        DIcon {
            name: "sticky_note_2"
            size: root.iconSize
        }
    }
    verticalBarPill: horizontalBarPill
    attachedContent: Component {
        Column {
            spacing: Theme.spacingM
            padding: Theme.spacingM
            StyledText {
                width: parent.width - Theme.spacingM * 2
                text: I18n.trFor("attachedPanelExample", "Notes")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeLarge
            }
            DTextField {
                width: parent.width - Theme.spacingM * 2
                placeholderText: I18n.trFor("attachedPanelExample", "Type here…")
                Accessible.name: I18n.trFor("attachedPanelExample", "Notes")
            }
            DButton {
                text: I18n.trFor("attachedPanelExample", "Close")
                onClicked: root.surfaceContext.dismissExpansion()
            }
        }
    }
    popoutWidth: Theme.listItemHeight * 6
    popoutHeight: Theme.listItemHeight * 3
    popoutContent: Component {
        PopoutComponent {
            headerText: I18n.trFor("attachedPanelExample", "Notes")
            detailsText: I18n.trFor("attachedPanelExample", "This widget opens an attached panel in the dock.")
        }
    }
}
