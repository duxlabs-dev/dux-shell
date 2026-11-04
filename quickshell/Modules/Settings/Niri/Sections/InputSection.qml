import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Sections.Input

Column {
    readonly property string sectionId: "input"

    spacing: Theme.spacingM

    InputKeyboardCard {}
    InputTouchpadCard {}
    InputCursorCard {}
}
