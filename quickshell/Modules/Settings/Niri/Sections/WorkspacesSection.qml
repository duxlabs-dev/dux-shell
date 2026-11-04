import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Sections.Workspaces
import qs.Modules.Settings.Niri.Shell

// BoardCard holds Close and Bulk actions too: Bulk needs the board, and its typed property only takes the sibling type.
Column {
    readonly property string sectionId: "workspaces"
    readonly property Component sidePane: Component {
        NiriSideScreens {}
    }

    spacing: Theme.spacingM

    BoardCard {}
    SessionCard {}
}
