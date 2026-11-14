import QtQuick
import qs.Common

QtObject {
    readonly property var defs: [
        {
            "id": "user",
            "title": I18n.tr("User"),
            "icon": "account_circle"
        },
        {
            "id": "network",
            "title": I18n.tr("Network"),
            "icon": "hub"
        },
        {
            "id": "audio",
            "title": I18n.tr("Audio"),
            "icon": "tune"
        },
        {
            "id": "display",
            "title": I18n.tr("Display"),
            "icon": "display_settings"
        },
        {
            "id": "system",
            "title": I18n.tr("System"),
            "icon": "dns"
        },
        {
            "id": "plugins",
            "title": I18n.tr("Plugins"),
            "icon": "extension"
        }
    ]
}
