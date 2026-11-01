pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets
import "../../../../../Common/KeybindActions.js" as Actions
import "../../../../../Common/niri/search.js" as Search
import "../../../../../Common/niri/actionwords.js" as ActionWords

// Step 1 of the guided add: what the shortcut does (an app, a niri action or a DMS action)
Column {
    id: root

    // "app", "niri" or "dms"
    property string kind: "app"
    property string query: ""

    readonly property var kinds: ["app", "niri", "dms"]
    readonly property var items: {
        const tokens = Search.tokensOf(query);
        let all = [];
        if (kind === "app") {
            all = AppSearchService.getVisibleApplications().filter(app => app.command?.length > 0).map(app => ({
                        "label": app.name,
                        "action": Actions.buildSpawnAction(app.command[0], app.command.slice(1))
                    }));
        } else if (kind === "niri") {
            for (const cat of KeybindsService.getCompositorCategories())
                all = all.concat(KeybindsService.getCompositorActions(cat).map(a => ({
                                "label": a.label,
                                "action": a.id
                            })));
        } else {
            all = KeybindsService.dmsActions.map(a => ({
                        "label": a.label,
                        "action": a.id
                    }));
        }
        return all.filter(item => {
            if (!Actions.isValidAction(item.action))
                return false;
            if (!tokens.length)
                return true;
            const hay = Search.tokensOf([item.label, item.action, ActionWords.actionSearchWords(item.action).join(" ")].join(" "));
            return Search.matchTokens(tokens, hay);
        }).slice(0, 40);
    }

    // {label, action}
    signal chosen(var item)

    spacing: Theme.spacingM

    DButtonGroup {
        arrowKeysSelect: false
        selectionMode: "single"
        size: "small"
        selectedColor: Theme.primaryContainer
        selectedContentColor: Theme.onPrimaryContainer
        model: [I18n.tr("Open an app", "niri keybinds guided add, kind of action"), I18n.tr("niri action", "niri keybinds guided add, kind of action"), I18n.tr("DMS action", "niri keybinds guided add, kind of action")]
        currentIndex: root.kinds.indexOf(root.kind)
        onSelectionChanged: (index, selected) => {
            if (selected)
                root.kind = root.kinds[index];
        }
    }

    DTextField {
        width: parent.width
        leftIconName: "search"
        placeholderText: I18n.tr("Search")
        onTextChanged: root.query = text
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXXS

        Repeater {
            model: root.visible ? root.items : []

            delegate: Rectangle {
                id: item

                required property var modelData
                readonly property var keys: KeybindsService.keysForAction(modelData.action)

                width: parent.width
                height: Theme.buttonHeightS
                radius: Theme.cornerRadiusM
                color: area.containsMouse || activeFocus ? Theme.surfaceTextHover : SettingsMetrics.controlColor
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Keys.onReturnPressed: root.chosen(modelData)
                Keys.onEnterPressed: root.chosen(modelData)
                Keys.onSpacePressed: root.chosen(modelData)

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: used.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: item.modelData.label
                    elide: Text.ElideRight
                    color: Theme.surfaceText
                }

                DKeycap {
                    id: used
                    visible: item.keys.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: item.keys[0] ?? ""
                }

                FocusRing {}

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chosen(item.modelData)
                }
            }
        }
    }
}
