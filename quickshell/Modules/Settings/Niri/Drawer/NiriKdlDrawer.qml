pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../../../../Common/niri/diff.js" as Diff
import "../../../../Common/niri/assemble.js" as Assemble
import "../../../../Common/niri/kdlspawn.js" as KdlSpawn

Column {
    id: root

    property string sectionId
    property string title: sectionId
    property bool open: false

    readonly property string generated: NiriPageService.sectionKdl(sectionId)
    readonly property string saved: SettingsData.niriPage["custom." + sectionId] ?? ""
    readonly property string draft: customEdit.text
    readonly property bool dirty: draft !== base
    readonly property var diffOps: Diff.lineDiff(base, draft, 2)
    readonly property var spawnAt: KdlSpawn.spawnLines(draft)
    readonly property string spawnText: {
        const lines = draft.split("\n");
        return spawnAt.map(n => n + "  " + lines[n - 1].trim()).join("\n");
    }

    property string base
    property bool saving: false
    property bool justSaved: false
    // A text that runs programs is saved only on a second, explicit click (owner decision).
    property bool confirming: false
    property string error

    // The wide right column clips instead of scrolling: there the drawer scrolls inside itself, sized
    // to what is left of the window. A page that scrolls (narrow layouts) scrolls the drawer whole.
    readonly property real windowHeight: root.Window.window?.height ?? 0
    property real heightCap: Infinity

    // The parent chain is walked through a var parameter: contentY exists on no static type
    // shared by every scrolling ancestor.
    function scrolls(item) {
        return typeof item?.contentY === "number";
    }

    function inScrollingPage() {
        for (let p = root.parent; p; p = p.parent)
            if (scrolls(p))
                return true;
        return false;
    }

    function refit() {
        const w = root.Window.window;
        heightCap = !w || inScrollingPage() ? Infinity : Math.max(0, w.height - root.mapToItem(null, 0, 0).y - Theme.spacingL);
    }

    function reload() {
        base = saved;
        customEdit.text = saved;
        error = "";
        justSaved = false;
        confirming = false;
    }

    function trySave() {
        if (spawnAt.length > 0 && !confirming) {
            confirming = true;
            return;
        }
        confirming = false;
        save();
    }

    function save() {
        saving = true;
        error = "";
        justSaved = false;
        NiriPageService.setCustom(sectionId, draft);
    }

    onSectionIdChanged: reload()
    onOpenChanged: {
        if (open) {
            reload();
            // Final geometry exists only after the column lays the drawer out
            Qt.callLater(refit);
        }
    }
    // Follow an outside change (undo, restore) only while the user has nothing pending.
    onSavedChanged: {
        if (saving || customEdit.text !== base)
            return;
        base = saved;
        customEdit.text = saved;
    }
    onDraftChanged: {
        justSaved = false;
        confirming = false;
    }
    onYChanged: refit()
    onParentChanged: refit()
    onWindowHeightChanged: refit()
    Component.onCompleted: {
        reload();
        Qt.callLater(refit);
    }

    visible: open && NiriPageService.expert
    spacing: Theme.spacingM
    padding: Theme.spacingL

    Connections {
        target: NiriPageService
        enabled: root.saving

        function onApplied() {
            root.saving = false;
            root.reload();
            root.justSaved = true;
        }

        function onRefused(message) {
            root.saving = false;
            root.error = message;
        }
    }

    DFlickable {
        id: flick
        width: root.width - root.leftPadding - root.rightPadding
        height: Math.min(contentCol.height, Math.max(0, root.heightCap - root.topPadding - root.bottomPadding))
        contentWidth: width
        contentHeight: contentCol.height
        clip: true

        Column {
            id: contentCol
            width: flick.width
            spacing: root.spacing

            Row {
                width: parent.width
                spacing: Theme.spacingM

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "code"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.iconSize - closeButton.width - parent.spacing * 2

                    StyledText {
                        width: parent.width
                        text: "KDL · " + root.title
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: "dms/" + Assemble.customFragment
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                DIconButton {
                    id: closeButton
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "close"
                    Accessible.name: I18n.tr("Close")
                    onClicked: root.open = false
                }
            }

            NiriKdlNote {
                width: parent.width
                iconName: root.dirty ? "edit_note" : "info"
                tone: root.dirty ? Theme.warning : Theme.surfaceVariantText
                text: root.dirty ? I18n.tr("Draft, not saved") : I18n.tr("Generated text is read only. niri checks the whole config before saving yours.")
            }

            DTextEdit {
                width: parent.width
                height: Theme.fontSizeMedium * 10
                readOnly: true
                text: root.generated
                placeholderText: I18n.tr("Nothing generated for this section yet.")
                font.family: Theme.monoFontFamily
                wrapMode: TextEdit.NoWrap
                backgroundColor: Theme.surfaceContainerHigh
                Accessible.name: I18n.tr("Generated KDL, read only")
            }

            DTextEdit {
                id: customEdit
                width: parent.width
                height: Theme.fontSizeMedium * 10
                placeholderText: I18n.tr("Your KDL, added after the generated text")
                font.family: Theme.monoFontFamily
                wrapMode: TextEdit.NoWrap
                backgroundColor: Theme.surfaceContainer
                Accessible.name: I18n.tr("Your KDL")
                keyForwardTargets: [tabOut]

                // Tab leaves the editor instead of typing a tab, so the keyboard is never stuck here; KDL needs no tab character
                Item {
                    id: tabOut
                    Keys.onTabPressed: event => {
                        customEdit.Window.activeFocusItem?.nextItemInFocusChain(true)?.forceActiveFocus(Qt.TabFocusReason);
                        event.accepted = true;
                    }
                }
            }

            NiriKdlNote {
                width: parent.width
                visible: root.spawnAt.length > 0
                iconName: "warning"
                tone: root.confirming ? Theme.error : Theme.warning
                text: root.confirming ? I18n.tr("Save again to confirm: niri will run these programs with your rights.") : I18n.tr("This text runs programs (spawn). Check every line below before saving.")
                detail: root.spawnText
            }

            Row {
                spacing: Theme.spacingS

                DButton {
                    text: root.confirming ? I18n.tr("Save and run programs") : I18n.tr("Save")
                    iconName: root.confirming ? "warning" : "save"
                    busy: root.saving
                    enabled: root.dirty && !root.saving && !NiriPageService.busy
                    backgroundColor: root.confirming ? Theme.error : Theme.primary
                    textColor: root.confirming ? Theme.onError : Theme.onPrimary
                    onClicked: root.trySave()
                }

                DButton {
                    visible: root.confirming
                    text: I18n.tr("Cancel")
                    onClicked: root.confirming = false
                }

                DButton {
                    text: I18n.tr("Discard")
                    enabled: root.dirty && !root.saving
                    onClicked: root.reload()
                }
            }

            NiriKdlNote {
                width: parent.width
                visible: root.error !== ""
                iconName: "error"
                tone: Theme.error
                text: I18n.tr("niri refused it, nothing saved:")
                detail: root.error
            }

            NiriKdlNote {
                width: parent.width
                visible: root.justSaved
                iconName: "check_circle"
                tone: Theme.success
                text: I18n.tr("Saved. niri reloaded.")
            }

            NiriKdlDiff {
                width: parent.width
                visible: root.dirty
                ops: root.diffOps
            }
        }
    }
}
