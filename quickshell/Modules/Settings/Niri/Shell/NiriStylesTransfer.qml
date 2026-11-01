pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.FileBrowser
import qs.Services
import qs.Widgets
import "../../../../Common/niri/presets.js" as Presets

// Import and export of a style file; the imported style waits for Apply.
Column {
    id: root

    readonly property var log: Log.scoped("NiriStyles")

    property var pending: null
    property string importError: ""

    signal applyRequested(var values)

    function reset() {
        pending = null;
        importError = "";
    }

    function refuse(message) {
        pending = null;
        importError = message;
    }

    // The size comes first: FileView reads the whole file into memory.
    function readImport(path) {
        sizeCheck.path = path;
        sizeCheck.running = true;
    }

    function readChecked(size) {
        if (!(size >= 0)) {
            log.warn("import: unreadable file");
            refuse(I18n.tr("Not a valid style file", "niri styles import error"));
            return;
        }
        if (size > Presets.TEXT_MAX) {
            log.warn("import: file too large");
            refuse(I18n.tr("Style file too large", "niri styles import error"));
            return;
        }
        importFile.path = sizeCheck.path;
        const r = Presets.parseStyle(importFile.text());
        if (r.error) {
            log.warn("import:", r.error);
            refuse(I18n.tr("Not a valid style file", "niri styles import error"));
            return;
        }
        importError = "";
        pending = r;
    }

    function writeExport(path) {
        exportFile.path = path;
        exportFile.setText(Presets.exportStyle("", Presets.snapshot(NiriPageService.get)));
    }

    spacing: Theme.spacingS

    Row {
        spacing: Theme.spacingS

        DButton {
            text: I18n.tr("Import", "niri styles, load a style file")
            iconName: "upload"
            backgroundColor: "transparent"
            textColor: Theme.surfaceText
            onClicked: {
                openLoader.active = true;
                (openLoader.item as FileBrowserModal).open();
            }
        }

        DButton {
            text: I18n.tr("Export", "niri styles, save the current style to a file")
            iconName: "download"
            backgroundColor: "transparent"
            textColor: Theme.surfaceText
            onClicked: {
                saveLoader.active = true;
                (saveLoader.item as FileBrowserModal).open();
            }
        }
    }

    StyledText {
        visible: root.importError !== ""
        width: parent.width
        text: root.importError
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.error
    }

    Rectangle {
        visible: root.pending !== null
        width: parent.width
        height: importRow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadiusM
        color: Theme.surfaceContainerHighest

        Row {
            id: importRow

            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "upload_file"
                size: Theme.iconSize
                color: Theme.surfaceText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Theme.iconSize - applyButton.width - dropButton.width - Theme.spacingS * 3
                text: I18n.tr("%1 · %2 changes", "niri styles import summary, name and number of settings").arg(root.pending?.name || I18n.tr("Imported style", "niri styles import without a name")).arg(Object.keys(root.pending?.values ?? {}).length)
                elide: Text.ElideRight
                color: Theme.surfaceText
            }

            DButton {
                id: applyButton
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Apply")
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: {
                    root.applyRequested(root.pending.values);
                    root.pending = null;
                }
            }

            DButton {
                id: dropButton
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Cancel")
                backgroundColor: "transparent"
                textColor: Theme.surfaceText
                onClicked: root.pending = null
            }
        }
    }

    Loader {
        id: openLoader
        active: false

        sourceComponent: FileBrowserModal {
            browserTitle: I18n.tr("Import a style", "niri styles import file browser title")
            bucket: "niri-style"
            filters: ["*.json"]
            onAccepted: paths => root.readImport(paths[0])
        }
    }

    Loader {
        id: saveLoader
        active: false

        sourceComponent: FileBrowserModal {
            browserTitle: I18n.tr("Export the style", "niri styles export file browser title")
            bucket: "niri-style"
            filters: ["*.json"]
            saveMode: true
            defaultFileName: "niri-style.json"
            onAccepted: paths => root.writeExport(paths[0])
        }
    }

    // -L: a link to a style file is fine, its target's size is what gets read.
    Process {
        id: sizeCheck

        property string path: ""

        command: ["stat", "-L", "-c", "%s", "--", path]
        stdout: StdioCollector {
            onStreamFinished: root.readChecked(text.trim() === "" ? NaN : Number(text))
        }
    }

    FileView {
        id: importFile
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: exportFile
        blockWrites: true
        atomicWrites: true
        onSaved: ToastService.showInfo(I18n.tr("Style exported to %1", "niri styles export success").arg(Paths.strip(exportFile.path)))
        onSaveFailed: error => {
            ToastService.showError(I18n.tr("Could not export the style", "niri styles export error"));
            root.log.warn("export failed:", error);
        }
    }
}
