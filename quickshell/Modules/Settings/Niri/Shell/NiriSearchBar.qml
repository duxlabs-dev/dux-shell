pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import "../../../../Common/KeyUtils.js" as KeyUtils
import "../../../../Common/niri/chord.js" as Chord
import "../../../../Common/niri/registry.js" as Registry
import "../../../../Common/niri/search.js" as Search

Item {
    id: root

    property bool capturing: false
    property bool hasFocus: false
    property bool dismissed: false
    readonly property alias text: field.text
    readonly property bool expert: SettingsData.niriPageExpert
    readonly property var results: field.text.trim() === "" ? [] : Search.find(field.text, Registry.sections, {
        "sections": expert ? null : sectionCatalog.all.filter(section => !section.expertOnly).map(section => section.id),
        "binds": KeybindsService.getFlatBinds(),
        "modKey": KeybindsService.modKey,
        "modSymbol": KeybindsService.modSymbol,
        "translate": title => I18n.tr(title, "niri page search entry")
    })
    readonly property bool resultsShown: hasFocus && !capturing && !dismissed && field.text.trim() !== ""
    readonly property int flashHoldMs: Theme.scrollbarHideDelay
    // Reduce motion keeps the highlight for the same time, then drops it without a fade
    readonly property int flashFadeMs: SettingsData.reduceMotion ? 0 : Theme.shortDuration

    signal searchRequested(string text)
    signal comboCaptured(string combo)

    onResultsShownChanged: {
        if (!resultsShown || !KeybindsService.available || KeybindsService.getFlatBinds().length > 0)
            return;
        KeybindsService.loadBinds(false);
    }

    function focusSearch() {
        field.forceActiveFocus();
        field.selectAll();
    }

    function pick(result) {
        dismissed = true;
        if (result.kind === "bind") {
            const group = result.binds[0];
            SettingsUiState.niriSection = "keybinds";
            // The key pick takes a real bind key or a parsed chord, never the query text: an unbound
            // combination typed as text would otherwise light up a chord no bind carries
            const want = KeyUtils.normalizeKeyCombo(result.combo, KeybindsService.modKey, KeybindsService.modSymbol);
            const hit = (group?.keys ?? []).find(entry => KeyUtils.normalizeKeyCombo(entry?.key ?? "", KeybindsService.modKey, KeybindsService.modSymbol) === want);
            const key = hit?.key ?? Chord.parseChord(result.combo, KeybindsService.modKey);
            if (key)
                SettingsUiState.niriKeyPick = {
                    "key": key,
                    "category": group?.category ?? ""
                };
            return;
        }
        SettingsUiState.niriSection = result.section;
        Qt.callLater(reveal, result.key);
    }

    // hidden: also search through what Simple mode hides
    function findRow(item, key, hidden) {
        if (!item || (!hidden && !item.visible))
            return null;
        if (item.settingKey === key)
            return item;
        for (const child of item.children) {
            const hit = findRow(child, key, hidden);
            if (hit)
                return hit;
        }
        return null;
    }

    // Rows live in sections owned by other lots: find one by its settingKey instead of asking each section for a hook.
    function reveal(key) {
        const row = findRow(root.Window.contentItem, key, false);
        if (!row) {
            // A row hidden in Simple is only worth the Expert switch when Expert shows it: a row folded
            // by dependsOn, or absent from the page, leaves the mode alone
            if (expert || !findRow(root.Window.contentItem, key, true))
                return;
            SettingsData.set("niriPageExpert", true);
            if (!findRow(root.Window.contentItem, key, false)) {
                SettingsData.set("niriPageExpert", false);
                return;
            }
            Qt.callLater(reveal, key);
            return;
        }
        for (let flick = row.parent; flick; flick = flick.parent) {
            if (flick.contentY === undefined || !flick.contentItem)
                continue;
            const y = row.mapToItem(flick.contentItem, 0, 0).y - (flick.height - row.height) / 2;
            flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height));
            break;
        }
        flashComponent.createObject(row);
    }

    function setCapture(on) {
        capturing = on;
        if (on)
            field.forceActiveFocus();
    }

    implicitHeight: field.height

    // niri grabs its own binds (Super+B...) before the page sees them
    ShortcutInhibitor {
        window: root.QsWindow.window
        enabled: root.capturing
    }

    Item {
        id: keySink

        Keys.onPressed: event => {
            if (event.key === Qt.Key_K && event.modifiers === Qt.ControlModifier) {
                field.selectAll();
                event.accepted = true;
                return;
            }
            if (resultsLoader.panel && resultsLoader.panel.visible && !root.capturing) {
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    resultsLoader.panel.move(event.key === Qt.Key_Down ? 1 : -1);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    resultsLoader.panel.chooseHighlighted();
                    event.accepted = true;
                    return;
                }
            }
            if (event.key === Qt.Key_Escape) {
                if (!root.capturing && field.text === "")
                    return;
                event.accepted = true;
                if (root.capturing) {
                    root.capturing = false;
                    return;
                }
                field.clear();
                return;
            }
            if (!root.capturing || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                return;
            event.accepted = true;
            const combo = KeyUtils.chordToken(event.key, event.modifiers, KeyUtils.modsFromEvent(event.modifiers), event.nativeScanCode, "", "");
            if (!combo || [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_AltGr].includes(event.key))
                return;
            root.capturing = false;
            field.text = combo;
            root.comboCaptured(combo);
        }
    }

    DSearchField {
        id: field

        width: parent.width
        backgroundColor: root.capturing ? Theme.primaryContainer : Theme.surfaceContainerHigh
        normalBorderColor: root.capturing ? Theme.primary : "transparent"
        textColor: root.capturing ? Theme.onPrimaryContainer : Theme.surfaceText
        leftIconColor: root.capturing ? Theme.onPrimaryContainer : Theme.surfaceVariantText
        placeholderColor: root.capturing ? Theme.onPrimaryContainer : Theme.surfaceVariantText
        placeholderText: root.capturing ? I18n.tr("Press a combination…", "niri page search bar while it records a key combination") : I18n.tr("Search or press keys (Ctrl+K)", "niri page search bar placeholder")
        keyForwardTargets: [keySink]
        Accessible.name: I18n.tr("Search niri settings, in plain words or by pressing keys", "niri page search bar accessible name")
        onTextChanged: {
            root.dismissed = false;
            root.searchRequested(text);
        }
        onFocusStateChanged: hasFocus => {
            root.hasFocus = hasFocus;
            if (!hasFocus)
                root.capturing = false;
        }

        trailingContent: Component {
            DActionButton {
                focusPolicy: Qt.TabFocus
                buttonSize: Theme.iconButtonSize
                iconName: "keyboard"
                iconSize: Theme.iconSize
                iconColor: root.capturing ? Theme.onPrimary : Theme.surfaceText
                backgroundColor: root.capturing ? Theme.primary : "transparent"
                tooltipText: I18n.tr("Find a shortcut by pressing it", "niri page search bar button that records a key combination")
                Accessible.name: tooltipText
                Accessible.checked: root.capturing
                onClicked: root.setCapture(!root.capturing)
            }
        }
    }

    // A source URL, not the type: the results list is not compiled before the first query.
    // A URL item cannot take required properties: they land through Binding after creation.
    Loader {
        id: resultsLoader
        active: root.resultsShown
        // a source URL has no type to infer: the cast only documents what loads here
        readonly property NiriSearchResults panel: item as NiriSearchResults
        source: "NiriSearchResults.qml"
        Binding { target: resultsLoader.item; property: "visible"; value: root.resultsShown }
        Binding { target: resultsLoader.item; property: "anchorItem"; value: field }
        Binding { target: resultsLoader.item; property: "results"; value: root.results }
        Binding { target: resultsLoader.item; property: "query"; value: field.text.trim() }
        Binding { target: resultsLoader.item; property: "expert"; value: root.expert }
        Binding { target: resultsLoader.item; property: "modKey"; value: KeybindsService.modKey }
        Binding { target: resultsLoader.item; property: "modSymbol"; value: KeybindsService.modSymbol }
        Binding {
            target: resultsLoader.item
            property: "sectionNames"
            value: sectionCatalog.all.reduce((names, section) => Object.assign(names, {
                    [section.id]: section.text
                }), {})
        }
        Connections {
            target: resultsLoader.item
            function onChosen(result) {
                root.pick(result)
            }
        }
    }

    NiriSections {
        id: sectionCatalog
    }

    Ref {
        service: KeybindsService
        active: root.resultsShown
    }

    Component {
        id: flashComponent

        Rectangle {
            id: flash

            anchors.fill: parent
            anchors.leftMargin: -Theme.spacingS
            anchors.rightMargin: -Theme.spacingS
            z: -1
            radius: Theme.cornerRadiusM
            color: Theme.primaryContainer
            border.width: Theme.outlineWidthFocused
            border.color: Theme.primary

            SequentialAnimation on opacity {
                PauseAnimation {
                    duration: root.flashHoldMs
                }
                NumberAnimation {
                    to: 0
                    duration: root.flashFadeMs
                }
                ScriptAction {
                    script: flash.destroy()
                }
            }
        }
    }
}
