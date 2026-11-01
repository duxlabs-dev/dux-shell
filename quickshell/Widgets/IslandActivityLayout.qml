import QtQuick
import qs.Common

Column {
    property real contentInset: Theme.spacingL
    readonly property real availableWidth: Math.max(0, (parent ? parent.width : 0) - contentInset * 2)

    width: availableWidth
    spacing: Theme.spacingM
}
