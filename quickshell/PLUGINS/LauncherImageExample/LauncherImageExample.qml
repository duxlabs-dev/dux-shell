import QtQuick
import Quickshell
import qs.Services
import qs.Common

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "img"

    signal itemsChanged

    readonly property var images: [
        {
            name: "DankDash",
            imageUrl: Site.web + "/img/dankdash.png",
            comment: "Dux Shell Dashboard"
        },
        {
            name: "Control Center",
            imageUrl: Site.web + "/img/cc.png",
            comment: "System Control Center"
        },
        {
            name: "Desktop",
            imageUrl: Site.web + "/img/desktop.png",
            comment: "Desktop Environment"
        },
        {
            name: "Search",
            imageUrl: Site.web + "/img/dsearch.png",
            comment: "Application Search"
        },
        {
            name: "Theme Registry",
            imageUrl: Site.web + "/img/blog/v1.2/themeregistry.png",
            comment: "Theme Registry Browser"
        },
        {
            name: "Monitor Settings",
            imageUrl: Site.web + "/img/blog/v1.2/monitordark.png",
            comment: "Display Configuration"
        }
    ]

    function getItems(query) {
        const lowerQuery = query ? query.toLowerCase().trim() : "";

        if (lowerQuery.length === 0) {
            return images.map(img => ({
                        name: img.name,
                        icon: "material:image",
                        comment: img.comment,
                        action: "view:" + img.imageUrl,
                        categories: ["Image Gallery"],
                        imageUrl: img.imageUrl
                    }));
        }

        return images.filter(img => img.name.toLowerCase().includes(lowerQuery) || img.comment.toLowerCase().includes(lowerQuery)).map(img => ({
                    name: img.name,
                    icon: "material:image",
                    comment: img.comment,
                    action: "view:" + img.imageUrl,
                    categories: ["Image Gallery"],
                    imageUrl: img.imageUrl
                }));
    }

    function executeItem(item) {
        if (!item?.action)
            return;
        const actionParts = item.action.split(":");
        const actionType = actionParts[0];
        const actionData = actionParts.slice(1).join(":");

        if (actionType === "view") {
            if (typeof ToastService !== "undefined") {
                ToastService.showInfo("Image Gallery", "Viewing: " + item.name);
            }
        }
    }

    function getContextMenuActions(item) {
        if (!item)
            return [];
        return [
            {
                icon: "open_in_new",
                text: "Open in Browser",
                action: () => {
                    const url = item.imageUrl || "";
                    if (url) {
                        Qt.openUrlExternally(url);
                    }
                }
            },
            {
                icon: "content_copy",
                text: "Copy URL",
                action: () => {
                    const url = item.imageUrl || "";
                    if (url) {
                        Quickshell.execDetached(["dms", "cl", "copy", url]);
                        if (typeof ToastService !== "undefined") {
                            ToastService.showInfo("Copied", url);
                        }
                    }
                }
            }
        ];
    }
}
