import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.DCommon.FileBrowser
import qs.Modals.Common

DModal {
    id: fileBrowserSurfaceModal

    property string mode: folderMode ? "openFolder" : saveMode ? "save" : "open"
    property var filters: fileExtensions
    property bool multiple: false
    property string defaultName: defaultFileName
    property string startPath: revealPath
    property string bucket: browserType
    property string defaultViewMode: ["wallpaper", "profile"].includes(bucket) ? "grid" : "list"

    property string browserTitle: I18n.tr("Select File", "default file browser window title")
    property string browserIcon: "folder_open" // !TODO: plugin compat, the window header no longer draws an icon
    property string browserType: "generic"
    property var fileExtensions: []
    property alias filterExtensions: fileBrowserSurfaceModal.fileExtensions
    property bool showHiddenFiles: false
    property bool saveMode: false
    property bool folderMode: false
    property string defaultFileName: ""
    property string revealPath: ""
    property var parentPopout: null
    property bool _settled: false

    signal accepted(var paths)
    signal rejected
    signal fileSelected(string path)

    layerNamespace: "dms:filebrowser"
    modalWidth: 860
    modalHeight: 620
    backgroundColor: Theme.floatingWindowSurface
    closeOnEscapeKey: false
    closeOnBackgroundClick: true
    allowStacking: true
    useOverlayLayer: true
    keepPopoutsOpen: true

    onBackgroundClicked: close()

    onOpened: {
        _settled = false;
        if (parentPopout)
            parentPopout.customKeyboardFocus = WlrKeyboardFocus.None;
        Qt.callLater(() => {
            const picker = contentLoader?.item;
            if (!picker)
                return;
            picker.reset();
            picker.forceActiveFocus();
        });
    }

    onDialogClosed: {
        if (parentPopout)
            parentPopout.customKeyboardFocus = null;
        if (_settled)
            return;
        _settled = true;
        rejected();
    }

    content: FilePicker {
        focus: true
        autoReset: false
        mode: fileBrowserSurfaceModal.mode
        filters: fileBrowserSurfaceModal.filters
        multiple: fileBrowserSurfaceModal.multiple
        defaultName: fileBrowserSurfaceModal.defaultName
        startPath: fileBrowserSurfaceModal.startPath
        bucket: fileBrowserSurfaceModal.bucket
        title: fileBrowserSurfaceModal.browserTitle
        defaultShowHidden: fileBrowserSurfaceModal.showHiddenFiles
        defaultViewMode: fileBrowserSurfaceModal.defaultViewMode
        onAccepted: paths => {
            fileBrowserSurfaceModal._settled = true;
            fileBrowserSurfaceModal.accepted(paths);
            if (paths.length > 0)
                fileBrowserSurfaceModal.fileSelected(paths[0]);
            fileBrowserSurfaceModal.close();
        }
        onRejected: fileBrowserSurfaceModal.close()
    }
}
