import QtQuick
import Quickshell.Hyprland
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

BasePill {
    id: root

    readonly property string focusedScreenName: (CompositorService.isHyprland && typeof Hyprland !== "undefined" && Hyprland.focusedMonitor ? (Hyprland.focusedMonitor.name || "") : CompositorService.isNiri && typeof NiriService !== "undefined" && NiriService.currentOutput ? NiriService.currentOutput : "")
    readonly property string targetScreenName: parentScreen?.name || focusedScreenName

    function resolveNotepadInstance() {
        const slideouts = PopoutService.notepadSlideouts;
        if (!slideouts || slideouts.length === 0) {
            return null;
        }

        const targetScreen = targetScreenName;
        if (targetScreen) {
            for (var i = 0; i < slideouts.length; i++) {
                var slideout = slideouts[i];
                if (slideout.modelData && slideout.modelData.name === targetScreen) {
                    return slideout;
                }
            }
        }

        return slideouts[0];
    }

    readonly property var notepadInstance: resolveNotepadInstance()
    readonly property bool popoutDefault: SettingsData.notepadDefaultMode === "popout"
    readonly property bool isActive: popoutDefault ? (PopoutService.notepadPopout?.visible ?? false) : (notepadInstance?.isVisible ?? false)

    function showActiveSurface() {
        if (root.popoutDefault) {
            PopoutService.openNotepadPopout();
            return;
        }
        const instance = prepareNotepadInstance(root.notepadInstance);
        if (instance && typeof instance.show === "function")
            instance.show();
    }

    function prepareNotepadInstance(instance) {
        if (instance)
            instance.triggerUsesOverlayLayer = root.barUsesOverlayLayer;
        return instance;
    }

    readonly property var savedTabEntries: {
        const result = [];
        const tabs = NotepadStorageService.tabs || [];
        for (let i = 0; i < tabs.length; i++) {
            const tab = tabs[i];
            if (tab && !tab.isTemporary) {
                result.push({
                    index: i,
                    tab: tab
                });
            }
        }
        return result.slice(0, 5);
    }

    function openTabByIndex(tabIndex) {
        if (tabIndex < 0)
            return;
        showActiveSurface();
        Qt.callLater(() => {
            NotepadStorageService.switchToTab(tabIndex);
        });
    }

    function openNewNote() {
        showActiveSurface();
        Qt.callLater(() => {
            NotepadStorageService.createNewTab();
        });
    }

    function openContextMenu() {
        const anchor = root.contextMenuAnchor();
        contextMenu.openFromBar(anchor);
    }

    content: Component {
        Item {
            implicitWidth: notepadIcon.width
            implicitHeight: root.contentThickness

            DIcon {
                id: notepadIcon

                anchors.centerIn: parent
                name: "assignment"
                size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.isActive ? Theme.primary : Theme.surfaceText
            }
        }
    }

    MouseArea {
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            root.triggerRipple(this, mouse.x, mouse.y);
        }
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                openContextMenu();
                return;
            }
            if (root.popoutDefault) {
                PopoutService.toggleNotepadPopout();
                return;
            }
            const inst = prepareNotepadInstance(root.notepadInstance);
            if (inst) {
                inst.toggle();
            }
        }
    }

    DContextMenu {
        id: contextMenu
        layerNamespace: "dms:notepad-context-menu"
        menuItems: root.savedTabEntries.map(entry => ({
                    type: "item",
                    icon: "description",
                    text: entry.tab?.title || I18n.tr("Saved Note"),
                    action: () => root.openTabByIndex(entry.index)
                })).concat([
            {
                type: "item",
                icon: "add",
                text: I18n.tr("Open a new note"),
                action: () => root.openNewNote()
            }
        ])
    }
}
