import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import qs.Services
import "../../../../../Common/niri/colwidth.js" as ColWidth
import "../../../../../Common/niri/keymaps.js" as Keymaps
import "../../../../../Common/niri/sections/columns.js" as Columns

// The Columns card and the Alt-Tab card of the windows section.
Column {
    id: root

    function preview(row) {
        const current = SettingsUiState.niriPreviewState;
        if (row.hovered && row.canTry) {
            SettingsUiState.niriPreviewState = {
                [row.settingKey]: row.tryValue
            };
            return;
        }
        if (current && row.settingKey in current)
            SettingsUiState.niriPreviewState = null;
    }

    readonly property var widths: [
        {
            "value": 0.25,
            "text": "1/4"
        },
        {
            "value": 0.33333,
            "text": "1/3"
        },
        {
            "value": 0.5,
            "text": "1/2"
        },
        {
            "value": 0.66667,
            "text": "2/3"
        },
        {
            "value": 0.75,
            "text": "3/4"
        },
        {
            "value": 1,
            "text": I18n.tr("Full", "column width")
        }
    ]

    // The Alt-Tab card arrived whole with niri 25.11, so its New pill sits on the card title
    // and shows while any key of the card is new.
    readonly property var altTabKeys: ["columns.altTab", "columns.altTabDelay", "columns.altTabPreviewScale"]
    readonly property bool altTabNew: altTabKeys.some(key => NiriPageService.isNew(key))

    // Super+R and Super+Shift+R follow the cycle option, unless the user bound them elsewhere
    readonly property var cycleBinds: {
        const map = Keymaps.bindMap(KeybindsService._dataVersion >= 0 ? KeybindsService.getFlatBinds() : [], KeybindsService.modKey);
        const current = {};
        for (const key of ["Mod+R", "Mod+Shift+R"]) {
            const bind = map[Keymaps.chordId(key, KeybindsService.modKey)]?.[0];
            if (bind)
                current[key] = bind;
        }
        return ColWidth.rebinds(NiriPageService.get("columns.cycleWidth") === true, current);
    }
    property var bindQueue: []

    function syncCycleBinds() {
        // Before the first load every key reads as unbound
        if (KeybindsService._dataVersion === 0 || KeybindsService.readOnly)
            return;
        bindQueue = cycleBinds.writes;
        writeNextBind();
    }

    function writeNextBind() {
        if (bindQueue.length === 0)
            return;
        const bind = bindQueue[0];
        bindQueue = bindQueue.slice(1);
        KeybindsService.saveBind("", bind);
    }

    // saveBind runs one process at a time, so the two keys go one after the other
    Connections {
        target: KeybindsService
        enabled: root.bindQueue.length > 0
        function onBindSaveCompleted(success) {
            if (success)
                root.writeNextBind();
            else
                root.bindQueue = [];
        }
    }

    Component.onCompleted: {
        KeybindsService.addRef();
        if (KeybindsService.available && (KeybindsService._dataVersion === 0 || KeybindsService.keybinds?.provider !== KeybindsService.currentProvider))
            KeybindsService.loadBinds();
    }
    Component.onDestruction: KeybindsService.removeRef()

    width: parent?.width ?? 0
    spacing: Theme.spacingM

    NiriCard {
        icon: "view_column"
        title: I18n.tr("Columns", "niri page card")

        NiriSeg {
            id: centerSeg

            readonly property var texts: ({
                    "never": I18n.tr("Never"),
                    "on-overflow": I18n.tr("Overflow"),
                    "always": I18n.tr("Always")
                })

            settingKey: "columns.centerFocused"
            icon: "format_align_center"
            title: I18n.tr("Center the focused column")
            tip: I18n.tr("When the view scrolls to it")
            kdlKey: "layout.center-focused-column"
            tryValue: value === "always" ? "never" : "always"
            options: Columns.limits["columns.centerFocused"].map(v => ({
                        "value": v,
                        "text": centerSeg.texts[v]
                    }))
            onHoveredChanged: root.preview(this)
        }

        NiriRow {
            settingKey: "columns.centerSingle"
            icon: "view_column"
            title: I18n.tr("Center a lone column")
            kdlKey: "layout.always-center-single-column"
            onHoveredChanged: root.preview(this)
        }

        NiriSeg {
            settingKey: "columns.defaultWidth"
            icon: "width"
            title: I18n.tr("New column width")
            tip: I18n.tr("Drag the edge of a window on the desktop")
            kdlKey: "layout.default-column-width"
            options: [root.widths[1], root.widths[2], root.widths[3], root.widths[5]]
            onHoveredChanged: root.preview(this)
        }

        NiriRow {
            settingKey: "columns.cycleWidth"
            icon: "keyboard"
            title: I18n.tr("Super+R fills the remaining space")
            tip: root.cycleBinds.kept.length > 0 ? I18n.tr("%1 keeps your own shortcut", "niri columns Super+R option, %1 lists key combinations").arg(root.cycleBinds.kept.map(key => key.replace("Mod", KeybindsService.modKey)).join(", ")) : I18n.tr("Press again to get the width back, then the next preset. Off: Super+R only steps through the presets, as niri does")
            onValueChanged: root.syncCycleBinds()
        }

        ColumnsPresets {
            choices: root.widths
        }

        NiriSeg {
            settingKey: "columns.display"
            icon: "tab"
            title: I18n.tr("New columns")
            kdlKey: "layout.default-column-display"
            options: [
                {
                    "value": "normal",
                    "text": I18n.tr("Normal")
                },
                {
                    "value": "tabbed",
                    "text": I18n.tr("Tabbed")
                }
            ]
            onHoveredChanged: root.preview(this)
        }

        NiriSlider {
            settingKey: "columns.overviewZoom"
            icon: "zoom_out_map"
            title: I18n.tr("Overview zoom")
            kdlKey: "overview.zoom"
            from: 0.1
            to: 0.75
            stepSize: 0.05
            decimals: 2
            onHoveredChanged: root.preview(this)
        }

        NiriRow {
            settingKey: "columns.overviewCloseFocus"
            icon: "select_window"
            title: I18n.tr("Close on window focus")
            tip: I18n.tr("Leaves the overview when DMS launches an app or focuses a window", "niri overview close on window focus toggle description")
            onHoveredChanged: root.preview(this)
        }

        NiriRow {
            settingKey: "columns.noCsd"
            icon: "web_asset_off"
            title: I18n.tr("No app title bars")
            tip: I18n.tr("Some apps ignore it")
            kdlKey: "prefer-no-csd"
            onHoveredChanged: root.preview(this)
        }
    }

    NiriCard {
        // NiriCard's own header cannot host a pill, so the card draws its header here
        // and keeps the pill layout of NiriRow/NiriTile.
        title: ""

        Item {
            width: parent.width
            height: header.height + Theme.spacingS

            Row {
                id: header
                spacing: Theme.spacingS

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "tab_recent"
                    size: Theme.iconSizeMedium
                    color: Theme.surfaceText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Alt-Tab", "niri page card")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightBold
                    color: Theme.surfaceText
                }

                Rectangle {
                    id: newPill

                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.altTabNew
                    width: newText.implicitWidth + Theme.spacingS * 2
                    height: Theme.iconSizeSmall + Theme.spacingXXS
                    radius: height / 2
                    color: Theme.primaryContainer
                    Accessible.role: Accessible.StaticText
                    Accessible.name: I18n.tr("New", "niri page pill, an option that came with a niri update")

                    StyledText {
                        id: newText
                        anchors.centerIn: parent
                        text: I18n.tr("New", "niri page pill, an option that came with a niri update")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightBold
                        color: Theme.onPrimaryContainer
                    }

                    // Once the pill is on screen the version is seen, and it stops showing next session.
                    onVisibleChanged: {
                        if (visible)
                            NiriPageService.noteSeenVersion();
                    }
                }
            }
        }

        NiriRow {
            settingKey: "columns.altTab"
            icon: "tab_recent"
            title: I18n.tr("Alt-Tab switcher")
            tip: I18n.tr("niri 25.11 recent windows")
            kdlKey: "recent-windows"
            onHoveredChanged: root.preview(this)
        }

        NiriSlider {
            settingKey: "columns.altTabPreviewScale"
            dependsOn: "columns.altTab"
            icon: "preview"
            title: I18n.tr("Window previews")
            kdlKey: "recent-windows.previews.max-scale"
            cost: "some"
            costTip: I18n.tr("Draws a live picture of every window while Alt-Tab is open.")
            from: 0.1
            to: 1
            stepSize: 0.05
            decimals: 2
            onHoveredChanged: root.preview(this)
        }

        NiriSlider {
            settingKey: "columns.altTabDelay"
            dependsOn: "columns.altTab"
            icon: "timer"
            title: I18n.tr("Show after")
            kdlKey: "recent-windows.open-delay-ms"
            from: 0
            to: 500
            stepSize: 25
            unit: " ms"
            onHoveredChanged: root.preview(this)
        }
    }
}
