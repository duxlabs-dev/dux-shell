pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets
import "../../../../Common/KeyUtils.js" as KeyUtils

Popup {
    id: root

    property Item anchorItem: null
    property var results: []
    property var sectionNames: ({})
    property string query: ""
    property bool expert: false
    property string modKey: ""
    property string modSymbol: ""
    property int highlightIndex: 0
    readonly property real rowHeight: Theme.fieldHeight
    readonly property int maxRows: 8

    signal chosen(var result)

    function move(delta) {
        if (results.length === 0)
            return;
        highlightIndex = (highlightIndex + delta + results.length) % results.length;
    }

    function chooseHighlighted() {
        if (highlightIndex < 0 || highlightIndex >= results.length)
            return;
        chosen(results[highlightIndex]);
    }

    function subtitle(result) {
        if (result.kind === "setting")
            return "";
        if (result.binds.length > 1)
            return I18n.tr("Conflict: %1 actions", "niri page search result, a key combination bound to several actions; %1 is the count").arg(result.binds.length);
        if (result.binds.length === 0)
            return I18n.tr("Free", "niri page search result, a key combination bound to nothing");
        return result.binds[0].desc || result.binds[0].action;
    }

    // A bind row titles with the real bind key, not the typed spelling; a free combination keeps it
    function titleOf(result) {
        if (result.kind !== "bind")
            return I18n.tr(result.title, "niri page search entry");
        const group = result.binds[0];
        if (!group)
            return result.combo;
        const want = KeyUtils.normalizeKeyCombo(result.combo, root.modKey, root.modSymbol);
        const hit = (group.keys ?? []).find(entry => KeyUtils.normalizeKeyCombo(entry?.key ?? "", root.modKey, root.modSymbol) === want);
        return hit?.key ?? group.keys[0].key;
    }

    parent: anchorItem
    y: (anchorItem?.height ?? 0) + Theme.spacingXS
    width: anchorItem?.width ?? 0
    padding: Theme.spacingXS
    modal: false
    dim: false
    focus: false
    closePolicy: Popup.NoAutoClose
    onResultsChanged: highlightIndex = 0
    onHighlightIndexChanged: list.positionViewAtIndex(highlightIndex, ListView.Contain)

    background: Rectangle {
        radius: Theme.cornerRadiusL
        color: Theme.surfaceContainerHigh
        border.width: Theme.outlineWidth
        border.color: Theme.outlineVariant
    }

    contentItem: Item {
        implicitHeight: root.results.length > 0 ? list.height : noneText.implicitHeight + Theme.spacingM * 2

        StyledText {
            id: noneText
            visible: root.results.length === 0
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: root.expert ? I18n.tr("Nothing for \"%1\".", "niri page search finds nothing; %1 is the query").arg(root.query) : I18n.tr("Nothing for \"%1\". More settings in Expert.", "niri page search finds nothing in Simple mode; %1 is the query").arg(root.query)
        }

        DListView {
            id: list

            width: parent.width
            height: Math.min(root.results.length, root.maxRows) * root.rowHeight
            visible: root.results.length > 0
            clip: true
            model: root.results
            Accessible.role: Accessible.List
            Accessible.name: I18n.tr("Search results", "niri page search results list")

            delegate: StyledButton {
                id: entry

                required property var modelData
                required property int index
                readonly property bool lit: index === root.highlightIndex
                readonly property color contentColor: lit ? Theme.onPrimaryContainer : Theme.surfaceText
                readonly property color dimColor: lit ? Theme.onPrimaryContainer : Theme.surfaceVariantText
                readonly property string sub: root.subtitle(modelData)

                width: ListView.view.width
                implicitHeight: root.rowHeight
                radius: Theme.cornerRadiusM
                color: lit ? Theme.primaryContainer : "transparent"
                focusPolicy: Qt.NoFocus
                Accessible.role: Accessible.ListItem
                Accessible.name: titleText.text + (sub ? ", " + sub : "")
                Accessible.selected: lit
                onClicked: root.chosen(modelData)
                onHoveredChanged: {
                    if (hovered)
                        root.highlightIndex = index;
                }

                DIcon {
                    id: entryIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    name: entry.modelData.kind === "bind" ? "keyboard" : "tune"
                    size: Theme.iconSize
                    color: entry.contentColor
                }

                StyledText {
                    id: whereText
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sectionNames[entry.modelData.kind === "bind" ? "keybinds" : entry.modelData.section] ?? ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: entry.dimColor
                }

                Column {
                    anchors.left: entryIcon.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: whereText.left
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        id: titleText
                        width: parent.width
                        text: root.titleOf(entry.modelData)
                        font.family: entry.modelData.kind === "bind" ? Theme.monoFontFamily : Theme.fontFamily
                        font.weight: Theme.fontWeightBold
                        color: entry.contentColor
                        elide: Text.ElideRight
                    }

                    StyledText {
                        visible: entry.sub !== ""
                        width: parent.width
                        text: entry.sub
                        // StyledText wraps by default: a long action name would spill under the fixed row height
                        wrapMode: Text.NoWrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: entry.dimColor
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
