import QtQml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../Common/KeyUtils.js" as KeyUtils
import "../Common/KeybindActions.js" as Actions

FocusScope {
    id: content
    focus: true

    function getBindLabel(bind) {
        if (!bind)
            return "";
        var label = bind.desc || "";
        if (!label && bind.action) {
            label = Actions.getActionLabel(bind.action, KeybindsService.currentProvider) || bind.action;
        }
        if (!label)
            return "";
        if (label.includes("(by index)") && bind.action) {
            var parts = bind.action.trim().split(/\s+/);
            if (parts.length > 1) {
                var arg = parts[parts.length - 1];
                label = label.replace("(by index)", arg).trim();
            }
        }
        if ((bind.action === "next-window" || bind.action === "previous-window") && (bind.key || "").toLowerCase().includes("grave")) {
            if (label === "Next Window")
                label = "Next Window (Same Application)";
            else if (label === "Previous Window")
                label = "Previous Window (Same Application)";
        }
        if (label.startsWith("Media: "))
            label = label.slice(7).trim();
        if (bind.trigger === "both" && bind.releaseAction && !bind.desc)
            label += " • " + releaseLabel(Actions.getActionLabel(bind.releaseAction, KeybindsService.currentProvider) || bind.releaseAction);
        return label;
    }

    function releaseLabel(text) {
        return I18n.tr("Release", "noun, hyprland bind flag toggle, trigger on key release") + ": " + text;
    }

    Component {
        id: keybindItemDelegate

        DListItem {
            id: keybindRow
            required property var modelData
            readonly property bool canExecute: !keybindRow.modelData.isRange && keybindRow.modelData.trigger !== "both" && KeybindsService.canExecuteAction(keybindRow.modelData.action, keybindRow.modelData.luaAction)

            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            implicitHeight: Math.max(Theme.menuItemHeight, keycapsCol.implicitHeight + Theme.spacingS * 2)
            firstInGroup: true
            lastInGroup: true
            radius: Theme.groupedListOuterRadius
            Accessible.name: keybindRow.modelData.label || content.getBindLabel(keybindRow.modelData)
            Accessible.description: (keybindRow.modelData.allKeys ? keybindRow.modelData.allKeys.join(", ") : (keybindRow.modelData.key || "")) + " • " + (keybindRow.modelData.action || "")
            onClicked: {
                if (keybindRow.canExecute && KeybindsService.executeAction(keybindRow.modelData.action, keybindRow.modelData.luaAction))
                    content.closeRequested();
            }

            RowLayout {
                id: rowLayout
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingS
                anchors.topMargin: Theme.spacingXS
                anchors.bottomMargin: Theme.spacingXS
                spacing: Theme.spacingS

                // Description / Action (Leading)
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: keybindRow.modelData.label || content.getBindLabel(keybindRow.modelData)
                    font.pixelSize: Theme.fontSizeSmall
                    color: keybindRow.contentColor
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    active: keybindRow.modelData.trigger === "release"
                    visible: active
                    sourceComponent: DBadge {
                        text: I18n.tr("Release", "noun, hyprland bind flag toggle, trigger on key release")
                        color: Theme.primaryHover
                        textColor: Theme.primary
                    }
                }

                // DKeycap items (Trailing - stacked vertically if multiple combos)
                Column {
                    id: keycapsCol
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    spacing: Theme.spacingXS

                    Repeater {
                        id: combosRepeater
                        model: keybindRow.modelData.keyCombos || (keybindRow.modelData.key ? [KeyUtils.formatKeyTokens(keybindRow.modelData.key, KeybindsService.modKey, KeybindsService.modSymbol, content.modifierStyle)] : [])

                        Row {
                            anchors.right: parent ? parent.right : undefined
                            spacing: Theme.spacingXXS

                            Repeater {
                                model: modelData

                                DKeycap {
                                    text: modelData
                                    textColor: Theme.primary
                                }
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: rowHoverArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: keybindRow.canExecute ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            DTooltipHost {
                text: keybindRow.canExecute ? ((keybindRow.modelData.action || keybindRow.modelData.desc || "") + " • " + I18n.tr("Click to run", "cheatsheet action tooltip suffix")) : keybindRow.modelData.releaseAction ? (keybindRow.modelData.action + " • " + content.releaseLabel(keybindRow.modelData.releaseAction)) : (keybindRow.modelData.label || keybindRow.modelData.action || keybindRow.modelData.desc || "")
                target: keybindRow
                hoverArea: rowHoverArea
            }
        }
    }

    property real scrollStep: 60
    property var activeFlickable: rightFlickable
    property bool showFloatingToggle: true
    property bool floating: false
    property alias searchField: searchField
    property string selectedCategory: "All"
    property bool searchFocused: false

    signal closeRequested
    signal floatingToggleRequested

    function scrollDown() {
        if (!activeFlickable)
            return;
        let newY = activeFlickable.contentY + scrollStep;
        newY = Math.min(newY, Math.max(0, activeFlickable.contentHeight - activeFlickable.height));
        activeFlickable.contentY = newY;
    }

    function scrollUp() {
        if (!activeFlickable)
            return;
        let newY = activeFlickable.contentY - scrollStep;
        newY = Math.max(0, newY);
        activeFlickable.contentY = newY;
    }

    function focusSearch() {
        if (searchField) {
            searchField.forceActiveFocus();
            searchField.selectAll();
        }
    }

    function captureShortcut(event) {
        if (!searchFocused)
            return false;
        const chord = KeyUtils.shortcutFromSearchKey(event, KeybindsService.modKey, KeybindsService.modSymbol);
        if (!chord)
            return false;
        if (ownToggleCombos().includes(KeyUtils.normalizeKeyCombo(chord, KeybindsService.modKey, KeybindsService.modSymbol))) {
            closeRequested();
            return true;
        }
        searchField.text = chord;
        return true;
    }

    // the bind that opened the cheatsheet keeps closing it instead of becoming a search
    function ownToggleCombos() {
        const combos = [];
        for (const cat in rawBinds) {
            const binds = rawBinds[cat];
            if (!Array.isArray(binds))
                continue;
            for (let i = 0; i < binds.length; i++) {
                if (/\bkeybinds (toggle|close)\b/.test(binds[i].action || ""))
                    combos.push(KeyUtils.normalizeKeyCombo(binds[i].key, KeybindsService.modKey, KeybindsService.modSymbol));
            }
        }
        return combos;
    }

    ShortcutInhibitor {
        id: searchInhibitor
        window: content.QsWindow.window
        enabled: content.searchFocused
    }

    Shortcut {
        sequence: "Ctrl+F"
        onActivated: content.focusSearch()
    }

    Keys.onPressed: event => {
        if (captureShortcut(event)) {
            event.accepted = true;
            return;
        }
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            focusSearch();
            event.accepted = true;
            return;
        }
        switch (event.key) {
        case Qt.Key_J:
            if (event.modifiers & Qt.ControlModifier) {
                scrollDown();
                event.accepted = true;
            }
            return;
        case Qt.Key_K:
            if (event.modifiers & Qt.ControlModifier) {
                scrollUp();
                event.accepted = true;
            }
            return;
        case Qt.Key_Down:
            scrollDown();
            event.accepted = true;
            return;
        case Qt.Key_Up:
            scrollUp();
            event.accepted = true;
            return;
        }
    }

    readonly property var categoryPriority: ({
            "window": 1,
            "windows": 1,
            "window management": 1,
            "workspace": 2,
            "workspaces": 2,
            "applications": 3,
            "apps": 3,
            "audio": 4,
            "sound": 4,
            "media": 5,
            "brightness": 6,
            "dms": 7,
            "compositor": 8,
            "custom": 9,
            "system": 10
        })

    function getCategoryIcon(catName) {
        if (!catName)
            return "keyboard";
        const lower = catName.toLowerCase();
        if (lower === "all")
            return "apps";
        if (lower.includes("window"))
            return "desktop_windows";
        if (lower.includes("workspace"))
            return "grid_view";
        if (lower.includes("alt-tab") || lower.includes("alt_tab") || lower.includes("switcher"))
            return "swap_horiz";
        if (lower.includes("screenshot") || lower.includes("capture"))
            return "screenshot_region";
        if (lower.includes("overview"))
            return "overview";
        if (lower.includes("monitor") || lower.includes("display"))
            return "monitor";
        if (lower.includes("exec") || lower.includes("terminal") || lower.includes("spawn") || lower.includes("command"))
            return "terminal";
        if (lower.includes("scratchpad"))
            return "sticky_note_2";
        if (lower.includes("layout"))
            return "view_quilt";
        if (lower.includes("gap"))
            return "border_inner";
        if (lower.includes("tag"))
            return "tag";
        if (lower.includes("app"))
            return "open_in_new";
        if (lower.includes("audio") || lower.includes("sound") || lower.includes("media"))
            return "volume_up";
        if (lower.includes("bright"))
            return "brightness_6";
        if (lower.includes("dms"))
            return "widgets";
        if (lower.includes("system") || lower.includes("power"))
            return "power_settings_new";
        if (lower.includes("compositor"))
            return "tune";
        if (lower.includes("custom"))
            return "edit";
        if (lower.includes("other"))
            return "more_horiz";
        return "keyboard";
    }

    property var rawBinds: KeybindsService.cheatsheet.binds || ({})

    function collapseSequentialBinds(list) {
        if (!list || list.length < 3)
            return list || [];
        const numberPattern = /^(.*?)(\s+)(\d+)$/;
        const clusters = {};

        for (let i = 0; i < list.length; i++) {
            const item = list[i];
            const match = (item.label || "").match(numberPattern);
            const combo = item.keyCombos && item.keyCombos[0];
            if (match && combo && combo.length > 0) {
                const lastToken = combo[combo.length - 1];
                const num = parseInt(match[3], 10);
                if (!isNaN(num) && lastToken === String(num)) {
                    const baseLabel = match[1];
                    const mods = combo.slice(0, -1);
                    const modSig = mods.join("+");
                    const clusterKey = (baseLabel + "||" + modSig).toLowerCase();
                    if (!clusters[clusterKey])
                        clusters[clusterKey] = [];
                    clusters[clusterKey].push({
                        item: item,
                        num: num,
                        baseLabel: baseLabel,
                        mods: mods,
                        index: i
                    });
                }
            }
        }

        const collapsedMap = {};
        const skipIndices = {};

        for (const cKey in clusters) {
            const cluster = clusters[cKey];
            if (cluster.length >= 3) {
                cluster.sort((a, b) => a.num - b.num);
                let isSeq = true;
                for (let k = 1; k < cluster.length; k++) {
                    if (cluster[k].num !== cluster[k - 1].num + 1) {
                        isSeq = false;
                        break;
                    }
                }
                if (isSeq) {
                    const first = cluster[0];
                    const last = cluster[cluster.length - 1];
                    const rangeStr = first.num + "–" + last.num;
                    const combinedLabel = first.baseLabel + " " + rangeStr;
                    const allKeys = [];
                    for (let k = 0; k < cluster.length; k++) {
                        if (cluster[k].item.allKeys) {
                            for (let ak = 0; ak < cluster[k].item.allKeys.length; ak++) {
                                allKeys.push(cluster[k].item.allKeys[ak]);
                            }
                        } else if (cluster[k].item.key) {
                            allKeys.push(cluster[k].item.key);
                        }
                        if (k > 0) {
                            skipIndices[cluster[k].index] = true;
                        }
                    }
                    collapsedMap[first.index] = {
                        action: "",
                        desc: combinedLabel,
                        label: combinedLabel,
                        key: first.item.key,
                        allKeys: allKeys,
                        tokenSigs: {},
                        keyCombos: [[...first.mods, rangeStr]],
                        isRange: true
                    };
                }
            }
        }

        const result = [];
        for (let i = 0; i < list.length; i++) {
            if (collapsedMap[i]) {
                result.push(collapsedMap[i]);
            } else if (!skipIndices[i]) {
                result.push(list[i]);
            }
        }
        return result;
    }

    function generateCategories(query) {
        const lowerQuery = query ? query.toLowerCase().trim() : "";
        const lowerQueryWords = lowerQuery ? lowerQuery.split(/\s+/) : [];
        const processed = {};
        let totalCount = 0;

        for (const cat in rawBinds) {
            const binds = rawBinds[cat];
            if (!Array.isArray(binds))
                continue;
            const catLower = cat.toLowerCase();
            const subcatMap = {};
            let hasBinds = false;

            for (let i = 0; i < binds.length; i++) {
                const bind = binds[i];
                if (bind.hideOnOverlay)
                    continue;

                const label = content.getBindLabel(bind);
                const labelLower = label.toLowerCase();
                const keyTokens = KeyUtils.formatKeyTokens(bind.key, KeybindsService.modKey, KeybindsService.modSymbol, content.modifierStyle);
                const tokenSig = keyTokens.join("+");
                const keyLower = (bind.key || "").toLowerCase();
                const keyCombo = KeyUtils.normalizeKeyCombo(bind.key, KeybindsService.modKey, KeybindsService.modSymbol);
                const descLower = (bind.desc || "").toLowerCase();
                const actionLower = ((bind.action || "") + " " + (bind.releaseAction || "")).toLowerCase();

                let matched = true;
                for (let j = 0; j < lowerQueryWords.length; j++) {
                    const word = lowerQueryWords[j];
                    if (!word)
                        continue;
                    if (!keyLower.includes(word) && !keyCombo.includes(KeyUtils.normalizeKeyCombo(word, KeybindsService.modKey, KeybindsService.modSymbol)) && !labelLower.includes(word) && !descLower.includes(word) && !catLower.includes(word) && !actionLower.includes(word) && !tokenSig.toLowerCase().includes(word)) {
                        matched = false;
                        break;
                    }
                }
                if (!matched)
                    continue;

                const subcatName = bind.subcat || "_root";
                if (!subcatMap[subcatName])
                    subcatMap[subcatName] = {};

                const isGraveAltTab = (bind.action === "next-window" || bind.action === "previous-window") && (bind.key || "").toLowerCase().includes("grave") && !bind.action.includes("filter=");
                const bindAction = isGraveAltTab ? (bind.action + ' filter="app-id"') : (bind.action || "");
                const trigger = bind.trigger === "press" ? "" : (bind.trigger || "");
                const releaseAction = trigger === "both" ? (bind.releaseAction || "") : "";
                const groupKey = (label + "||" + bindAction + "||" + trigger + "||" + releaseAction).toLowerCase();
                if (subcatMap[subcatName][groupKey]) {
                    const existing = subcatMap[subcatName][groupKey];
                    if (tokenSig && !existing.tokenSigs[tokenSig] && keyTokens.length > 0) {
                        existing.tokenSigs[tokenSig] = true;
                        existing.keyCombos.push(keyTokens);
                        existing.allKeys.push(bind.key);
                    }
                } else {
                    const sigs = {};
                    if (tokenSig && keyTokens.length > 0)
                        sigs[tokenSig] = true;
                    subcatMap[subcatName][groupKey] = {
                        action: bindAction,
                        luaAction: bind.luaAction || "",
                        trigger: trigger,
                        releaseAction: releaseAction,
                        desc: bind.desc,
                        label: label,
                        key: bind.key,
                        allKeys: [bind.key],
                        tokenSigs: sigs,
                        keyCombos: keyTokens.length > 0 ? [keyTokens] : []
                    };
                    hasBinds = true;
                }
            }

            if (hasBinds) {
                const subcats = {};
                let catBindCount = 0;
                for (const subcatName in subcatMap) {
                    const groups = subcatMap[subcatName];
                    const rawList = [];
                    for (const gKey in groups) {
                        rawList.push(groups[gKey]);
                    }
                    const collapsedList = content.collapseSequentialBinds(rawList);
                    subcats[subcatName] = collapsedList;
                    catBindCount += collapsedList.length;
                }
                if (catBindCount > 0) {
                    processed[cat] = {
                        name: cat,
                        count: catBindCount,
                        subcats: subcats,
                        subcatKeys: Object.keys(subcats)
                    };
                    totalCount += catBindCount;
                }
            }
        }

        const keys = Object.keys(processed).sort((a, b) => {
            const pA = categoryPriority[a.toLowerCase()] || 99;
            const pB = categoryPriority[b.toLowerCase()] || 99;
            if (pA !== pB)
                return pA - pB;
            return a.localeCompare(b);
        });

        return {
            byCategory: processed,
            sortedKeys: keys,
            totalCount: totalCount
        };
    }

    property string activeSearchQuery: ""
    readonly property string modifierStyle: SettingsData.keybindsModifierStyle || "windows"
    property var dataModel: generateCategories("")

    onModifierStyleChanged: {
        content.dataModel = content.generateCategories(content.activeSearchQuery);
    }

    Connections {
        target: KeybindsService
        function onCheatsheetLoaded() {
            content.dataModel = content.generateCategories(content.activeSearchQuery);
        }
    }

    Timer {
        id: searchDebounce
        interval: 120
        repeat: false
        onTriggered: {
            content.activeSearchQuery = searchField.text;
            content.dataModel = content.generateCategories(searchField.text);
            if (searchField.text.trim() !== "" && content.selectedCategory !== "All") {
                if (!content.dataModel.byCategory[content.selectedCategory])
                    content.selectedCategory = "All";
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: Theme.windowInset
        anchors.topMargin: content.floating ? 0 : Theme.windowInset

        // Sidebar
        Item {
            id: sidebar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 260

            // Search Bar + Float Window Toggle at top of sidebar
            RowLayout {
                id: searchRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Theme.spacingS

                DSearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: I18n.tr("Search")
                    keyForwardTargets: [content]
                    onFocusStateChanged: hasFocus => content.searchFocused = hasFocus
                    onTextChanged: {
                        if (text.trim() === "") {
                            searchDebounce.stop();
                            content.activeSearchQuery = "";
                            content.dataModel = content.generateCategories("");
                        } else {
                            searchDebounce.restart();
                        }
                    }
                    Keys.onEscapePressed: event => {
                        content.closeRequested();
                        event.accepted = true;
                    }
                }

                DActionButton {
                    visible: content.showFloatingToggle
                    buttonSize: Theme.iconButtonSize
                    iconName: content.floating ? "close_fullscreen" : "open_in_new"
                    tooltipText: content.floating ? I18n.tr("Dock window") : I18n.tr("Open as window")
                    onClicked: content.floatingToggleRequested()
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            DFlickable {
                id: sidebarFlickable
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: searchRow.bottom
                anchors.bottom: sidebarFooter.top
                anchors.topMargin: Theme.spacingM
                anchors.bottomMargin: Theme.spacingS
                contentWidth: width
                contentHeight: sidebarCol.implicitHeight
                clip: true

                Column {
                    id: sidebarCol
                    width: parent.width
                    spacing: Theme.spacingXXS

                    // "All" Category Tab
                    DListItem {
                        id: allTab
                        width: sidebarCol.width
                        implicitHeight: Theme.menuItemHeight
                        isSelected: content.selectedCategory === "All"
                        isHovered: hovered || allBadgeHover.containsMouse
                        surfaceColor: "transparent"
                        border.width: 0
                        radius: Theme.cornerRadiusFull
                        topLeftRadius: Theme.cornerRadiusFull
                        topRightRadius: Theme.cornerRadiusFull
                        bottomLeftRadius: Theme.cornerRadiusFull
                        bottomRightRadius: Theme.cornerRadiusFull
                        Accessible.name: I18n.tr("All")
                        onClicked: content.selectedCategory = "All"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingL
                            anchors.rightMargin: Theme.spacingL
                            spacing: Theme.spacingS

                            DIcon {
                                name: "apps"
                                size: Theme.iconSizeSmall
                                color: allTab.contentColor
                            }

                            StyledText {
                                text: I18n.tr("All")
                                color: allTab.contentColor
                                font.weight: allTab.isSelected ? Theme.fontWeightMedium : Theme.fontWeight
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            DBadge {
                                text: content.dataModel.totalCount.toString()
                                color: allTab.isSelected ? Theme.primary : Theme.surfaceVariant
                                textColor: allTab.isSelected ? Theme.onPrimary : Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter

                                MouseArea {
                                    id: allBadgeHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }
                        }
                    }

                    // Category Tabs
                    Repeater {
                        model: content.dataModel.sortedKeys

                        DListItem {
                            id: catTab
                            required property var modelData

                            readonly property string catName: modelData
                            readonly property var catInfo: content.dataModel.byCategory[catName]

                            width: sidebarCol.width
                            implicitHeight: Theme.menuItemHeight
                            isSelected: content.selectedCategory === catTab.catName
                            isHovered: hovered || catBadgeHover.containsMouse
                            surfaceColor: "transparent"
                            border.width: 0
                            radius: Theme.cornerRadiusFull
                            topLeftRadius: Theme.cornerRadiusFull
                            topRightRadius: Theme.cornerRadiusFull
                            bottomLeftRadius: Theme.cornerRadiusFull
                            bottomRightRadius: Theme.cornerRadiusFull
                            Accessible.name: I18n.tr(catTab.catName)
                            onClicked: content.selectedCategory = catTab.catName

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingL
                                anchors.rightMargin: Theme.spacingL
                                spacing: Theme.spacingS

                                DIcon {
                                    name: content.getCategoryIcon(catTab.catName)
                                    size: Theme.iconSizeSmall
                                    color: catTab.contentColor
                                }

                                StyledText {
                                    text: I18n.tr(catTab.catName)
                                    color: catTab.contentColor
                                    font.weight: catTab.isSelected ? Theme.fontWeightMedium : Theme.fontWeight
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                DBadge {
                                    text: (catTab.catInfo?.count || 0).toString()
                                    color: catTab.isSelected ? Theme.primary : Theme.surfaceVariant
                                    textColor: catTab.isSelected ? Theme.onPrimary : Theme.surfaceVariantText
                                    Layout.alignment: Qt.AlignVCenter

                                    MouseArea {
                                        id: catBadgeHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Bottom Settings Row for Keycap Modifier Style (Windows vs Mac)
            Column {
                id: sidebarFooter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: Theme.spacingS

                Rectangle {
                    width: parent.width - Theme.spacingS * 2
                    height: Theme.dividerWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.outlineVariant
                    opacity: 0.3
                }

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: I18n.tr("Key style", "modifier icon style toggle label")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: Theme.spacingS
                    }

                    DButtonGroup {
                        id: modifierStyleGroup
                        size: "small"
                        model: [I18n.tr("Linux", "keyboard keycap style name"), I18n.tr("Mac", "keyboard keycap style name")]
                        currentIndex: content.modifierStyle === "mac" ? 1 : 0
                        onSelectionChanged: (index, selected) => {
                            if (selected)
                                SettingsData.set("keybindsModifierStyle", index === 1 ? "mac" : "windows");
                        }
                    }
                }
            }
        }

        // Main Content Area
        Item {
            id: mainArea
            anchors.left: sidebar.right
            anchors.leftMargin: Theme.spacingL
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            DFlickable {
                id: rightFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: contentCol.implicitHeight
                clip: true

                Column {
                    id: contentCol
                    width: rightFlickable.width - Theme.spacingS
                    spacing: Theme.spacingL

                    // Categories Renderer
                    Repeater {
                        model: content.selectedCategory === "All" ? content.dataModel.sortedKeys : (content.dataModel.byCategory[content.selectedCategory] ? [content.selectedCategory] : [])

                        Column {
                            id: sectionCol
                            width: contentCol.width
                            spacing: Theme.spacingM

                            readonly property string sectionCatName: modelData
                            readonly property var sectionCatInfo: content.dataModel.byCategory[sectionCatName]

                            // Section Header
                            Row {
                                id: categoryHeader
                                width: parent.width
                                spacing: Theme.spacingS
                                height: Math.max(categoryIcon.implicitHeight, categoryTitle.implicitHeight)

                                DIcon {
                                    id: categoryIcon
                                    name: content.getCategoryIcon(sectionCol.sectionCatName)
                                    size: Theme.iconSizeMedium
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    id: categoryTitle
                                    text: I18n.tr(sectionCol.sectionCatName)
                                    width: Math.min(implicitWidth, Math.max(0, categoryHeader.width - categoryIcon.width - categoryHeader.spacing))
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.primary
                                    horizontalAlignment: Text.AlignLeft
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Subcategories Repeater
                            Repeater {
                                model: sectionCol.sectionCatInfo?.subcatKeys || []

                                Column {
                                    id: subcatCol
                                    width: sectionCol.width
                                    spacing: Theme.spacingXS

                                    readonly property string subcatName: modelData
                                    readonly property var subcatBinds: sectionCol.sectionCatInfo?.subcats?.[subcatName] || []

                                    // Subcategory Title (if not _root)
                                    StyledText {
                                        visible: subcatCol.subcatName !== "_root"
                                        text: I18n.tr(subcatCol.subcatName)
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Theme.fontWeightMedium
                                        color: Theme.surfaceVariantText
                                    }

                                    readonly property bool isTwoColumn: rightFlickable.width > 550

                                    // 2-Column Responsive Masonry Layout
                                    RowLayout {
                                        id: keybindsMasonry
                                        width: parent.width
                                        spacing: Theme.spacingM

                                        // Left Column
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            spacing: Theme.spacingXS

                                            Repeater {
                                                model: subcatCol.subcatBinds ? subcatCol.subcatBinds.filter((_, idx) => !subcatCol.isTwoColumn || idx % 2 === 0) : []
                                                delegate: keybindItemDelegate
                                            }
                                        }

                                        // Right Column
                                        ColumnLayout {
                                            visible: subcatCol.isTwoColumn
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            spacing: Theme.spacingXS

                                            Repeater {
                                                model: subcatCol.isTwoColumn && subcatCol.subcatBinds ? subcatCol.subcatBinds.filter((_, idx) => idx % 2 === 1) : []
                                                delegate: keybindItemDelegate
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty State
            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingM
                visible: content.dataModel.totalCount === 0

                DIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: content.activeSearchQuery.trim() !== "" ? "search_off" : "keyboard"
                    size: Theme.iconSizeLarge + Theme.spacingL
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: content.activeSearchQuery.trim() !== "" ? I18n.tr("No results found") : I18n.tr("No keybinds found")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Try a different search")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    visible: content.activeSearchQuery.trim() !== ""
                }
            }
        }
    }
}
