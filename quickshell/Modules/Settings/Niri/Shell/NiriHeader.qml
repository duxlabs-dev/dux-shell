import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: header

    property bool compact: false
    property real searchMinWidth: 0
    property bool expert: false
    property bool kdlOpen: false
    property bool changedOnly: false
    property int modifiedTotal: 0

    signal searchRequested(string text)
    signal comboCaptured(string combo)
    signal kdlToggled
    signal changedOnlyToggled

    // Compact: status row first, tools across the full width last
    readonly property real gap: Theme.spacingM
    readonly property real rowHeight: Math.max(searchBar.height, tools.implicitHeight, status.height)
    readonly property bool oneLine: !compact && width - tools.implicitWidth - status.width - gap * 2 >= searchMinWidth
    readonly property real searchY: gap + (compact ? rowHeight + gap : 0)
    readonly property real lowerY: gap + rowHeight + gap + (compact ? rowHeight + gap : 0)

    function focusSearch() {
        searchBar.focusSearch();
    }

    height: (oneLine ? gap + rowHeight : lowerY + rowHeight) + gap

    NiriSearchBar {
        id: searchBar
        y: header.searchY + (header.rowHeight - height) / 2
        width: header.oneLine ? header.width - tools.width - status.width - header.gap * 2 : header.width
        onSearchRequested: text => header.searchRequested(text)
        onComboCaptured: combo => header.comboCaptured(combo)
    }

    RowLayout {
        id: tools

        x: header.oneLine ? searchBar.width + header.gap : 0
        y: (header.oneLine ? header.gap : header.lowerY) + (header.rowHeight - height) / 2
        width: header.compact ? header.width : implicitWidth
        spacing: Theme.spacingS

        DButton {
            Layout.fillWidth: header.compact
            text: I18n.tr("Styles", "niri page header button, presets and saved profiles")
            iconName: "palette"
            backgroundColor: Theme.surfaceContainerHighest
            textColor: Theme.surfaceText
            onClicked: {
                stylesLoader.active = true;
                const popup = stylesLoader.item as Popup;
                if (popup.opened)
                    popup.close();
                else
                    popup.open();
            }

            // A source URL, not the type: the popup and its thumbnails are not even compiled before the first click
            Loader {
                id: stylesLoader
                anchors.fill: parent
                active: false
                source: "NiriStylesPopup.qml"
            }
        }

        DButton {
            visible: header.expert
            text: I18n.tr("KDL", "niri page header button, the config text format")
            iconName: "code"
            tooltipText: I18n.tr("KDL of this section (Ctrl+E)", "niri page header button that opens the KDL text drawer")
            backgroundColor: header.kdlOpen ? Theme.primaryContainer : "transparent"
            textColor: header.kdlOpen ? Theme.onPrimaryContainer : Theme.surfaceText
            onClicked: header.kdlToggled()
        }

        DButton {
            text: header.modifiedTotal > 0 ? String(header.modifiedTotal) : ""
            iconName: "filter_list"
            minimumWidth: Theme.iconButtonSize
            tooltipText: I18n.tr("Changed only", "niri page header filter that shows only modified settings")
            Accessible.name: tooltipText
            Accessible.checked: header.changedOnly
            backgroundColor: header.changedOnly ? Theme.primaryContainer : "transparent"
            textColor: header.changedOnly ? Theme.onPrimaryContainer : Theme.surfaceText
            onClicked: header.changedOnlyToggled()
        }
    }

    Row {
        id: status

        // Two-line narrow: pack right after the tools instead of floating alone at the far right
        // of a half-empty line
        x: header.oneLine || header.compact ? header.width - width : tools.x + tools.width + header.gap
        y: (header.oneLine || header.compact ? header.gap : header.lowerY) + (header.rowHeight - height) / 2
        spacing: Theme.spacingS

        NiriHealthPill { anchors.verticalCenter: parent.verticalCenter }

        DButtonGroup {
            anchors.verticalCenter: parent.verticalCenter
            arrowKeysSelect: false
            selectedColor: Theme.primaryContainer
            selectedContentColor: Theme.onPrimaryContainer
            selectionMode: "single"
            checkEnabled: !header.compact
            model: [I18n.tr("Simple", "niri page detail level"), I18n.tr("Expert", "niri page detail level")]
            currentIndex: header.expert ? 1 : 0
            Accessible.name: I18n.tr("Detail level", "niri page Simple / Expert switch")
            onSelectionChanged: (index, selected) => {
                if (!selected)
                    return;
                SettingsData.set("niriPageExpert", index === 1);
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Theme.outlineWidth
        color: Theme.outlineVariant
    }
}
