import QtQuick
import qs.Common
import qs.Widgets

StyledText {
    property bool halo: false

    wrapMode: Text.NoWrap
    style: halo ? Text.Outline : Text.Normal
    styleColor: Theme.surface
}
