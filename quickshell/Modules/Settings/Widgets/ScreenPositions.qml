pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    function label(position) {
        switch (position) {
        case SettingsData.Position.Top:
            return I18n.tr("Top Right", "screen position option");
        case SettingsData.Position.Left:
            return I18n.tr("Top Left", "screen position option");
        case SettingsData.Position.TopCenter:
            return I18n.tr("Top Center", "screen position option");
        case SettingsData.Position.Right:
            return I18n.tr("Bottom Right", "screen position option");
        case SettingsData.Position.Bottom:
            return I18n.tr("Bottom Left", "screen position option");
        case SettingsData.Position.LeftCenter:
            return I18n.tr("Left Center", "screen position option");
        case SettingsData.Position.RightCenter:
            return I18n.tr("Right Center", "screen position option");
        default:
            return I18n.tr("Bottom Center", "screen position option");
        }
    }

    function icon(position) {
        switch (position) {
        case SettingsData.Position.Top:
            return "north_east";
        case SettingsData.Position.Left:
            return "north_west";
        case SettingsData.Position.TopCenter:
            return "north";
        case SettingsData.Position.Right:
            return "south_east";
        case SettingsData.Position.Bottom:
            return "south_west";
        case SettingsData.Position.LeftCenter:
            return "west";
        case SettingsData.Position.RightCenter:
            return "east";
        default:
            return "south";
        }
    }
}
