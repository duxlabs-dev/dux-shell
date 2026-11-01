import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Sections.Windows

Column {
    readonly property string sectionId: "windows"

    spacing: Theme.spacingM

    LookCard {}
    ColumnsCard {}
    RulesCard {}
}
