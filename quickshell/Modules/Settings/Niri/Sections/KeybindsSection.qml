import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Sections.Keybinds

// The shortcut list lives in the side pane (Shell/NiriDeskStack), so the section is only the keyboard;
// the stack keeps the mini desk under the pane, where a shortcut's ▶ Test plays.
Column {
    readonly property string sectionId: "keybinds"
    readonly property Component sidePane: Component {
        BindsPane {
            width: parent.width
            height: parent.height
        }
    }

    spacing: Theme.spacingM

    KeyboardCard {}
}
