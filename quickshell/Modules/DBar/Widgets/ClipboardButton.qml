import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

BasePill {
    id: root

    property bool isActive: false
    property bool dropConfirmed: false

    signal clipboardClicked
    signal showSavedItemsRequested
    signal clearAllRequested

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function handleDrop(drop) {
        if (!ClipboardService.clipboardAvailable)
            return;

        if (drop.hasUrls && drop.urls.length > 0) {
            const fileUrls = drop.urls.map(url => url.toString()).filter(url => url.startsWith("file://"));
            if (fileUrls.length > 0) {
                DMSService.sendRequest("clipboard.store", {
                    "data": fileUrls.join("\r\n"),
                    "mimeType": "text/uri-list"
                }, response => {
                    if (response.error) {
                        ToastService.showError(I18n.tr("Failed to save dropped file"));
                        return;
                    }
                    root.showDropConfirmation();
                });
                return;
            }
        }

        if (drop.hasText && drop.text.length > 0) {
            DMSService.sendRequest("clipboard.store", {
                "data": drop.text,
                "mimeType": "text/plain;charset=utf-8"
            }, response => {
                if (response.error) {
                    ToastService.showError(I18n.tr("Failed to save dropped text"));
                    return;
                }
                root.showDropConfirmation();
            });
        }
    }

    function showDropConfirmation() {
        dropConfirmed = true;
        dropConfirmationTimer.restart();
    }

    Timer {
        id: dropConfirmationTimer
        interval: 1200
        onTriggered: root.dropConfirmed = false
    }

    function openContextMenu() {
        const anchor = root.contextMenuAnchor();
        contextMenu.openFromBar(anchor);
    }

    MouseArea {
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function (mouse) {
            root.triggerRipple(this, mouse.x, mouse.y);
            switch (mouse.button) {
            case Qt.RightButton:
                openContextMenu();
                break;
            case Qt.LeftButton:
                clipboardClicked();
                break;
            }
        }
    }

    content: Component {
        Item {
            implicitWidth: icon.width
            implicitHeight: root.contentThickness

            property bool draggingOver: false

            DropArea {
                anchors.fill: parent
                anchors.margins: -root.horizontalPadding
                onEntered: draggingOver = true
                onExited: draggingOver = false
                onDropped: drop => {
                    draggingOver = false;
                    drop.accept(Qt.CopyAction);
                    root.handleDrop(drop);
                }
            }

            DIcon {
                id: icon
                anchors.centerIn: parent
                name: root.dropConfirmed ? "check" : "content_paste"
                size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.dropConfirmed || draggingOver ? Theme.primary : Theme.widgetIconColor
                scale: draggingOver ? 1.2 : 1.0

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutBack
                    }
                }
            }
        }
    }

    DContextMenu {
        id: contextMenu
        layerNamespace: "dms:clipboard-context-menu"
        menuItems: [
            {
                type: "item",
                icon: "delete_sweep",
                text: I18n.tr("Clear All"),
                action: () => root.clearAllRequested()
            },
            {
                type: "item",
                icon: "push_pin",
                text: I18n.tr("Show Saved Items"),
                action: () => root.showSavedItemsRequested()
            }
        ]
    }
}
