import QtQuick
import qs.Common
import qs.Widgets

StyledText {
    property bool halo: false

    style: halo ? Text.Outline : Text.Normal
    styleColor: Theme.surface
}
