import QtQuick
import qs.Common

// Search titles that only live in Common/niri/sections/*.js: listed here so the
// translation extractor, which reads QML only, catalogs them. Never instantiated.
QtObject {
    readonly property var titles: [
        I18n.tr("Fine tune", "niri page search entry"),
        I18n.tr("Never ask before closing", "niri page search entry"),
        I18n.tr("Show Alt-Tab after", "niri page search entry"),
        I18n.tr("Alt-Tab preview size", "niri page search entry"),
        I18n.tr("Side edges scroll while dragging", "niri page search entry"),
        I18n.tr("Top and bottom edges switch workspace while dragging", "niri page search entry"),
        I18n.tr("Touchpad pointer speed", "niri page search entry"),
        I18n.tr("Touchpad scroll speed", "niri page search entry"),
        I18n.tr("Touchpad acceleration profile", "niri page search entry"),
        I18n.tr("Touchpad scroll method", "niri page search entry"),
        I18n.tr("Touchpad middle click emulation", "niri page search entry"),
        I18n.tr("Hide cursor while typing", "niri page search entry"),
        I18n.tr("Hide cursor when idle", "niri page search entry"),
        I18n.tr("Open DMS windows floating", "niri page search entry")
    ]
}
