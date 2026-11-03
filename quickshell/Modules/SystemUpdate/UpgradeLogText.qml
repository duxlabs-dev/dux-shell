import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../../Common/UpgradeLog.js" as UpgradeLog

StyledText {
    property var lines: []
    property string placeholder: ""

    readonly property var kindColors: ({
            header: Theme.primary.toString(),
            section: Theme.secondary.toString(),
            counter: Theme.tertiary.toString(),
            name: Theme.primary.toString(),
            dim: Theme.surfaceVariantText.toString(),
            error: Theme.error.toString(),
            warning: Theme.warning.toString(),
            success: Theme.success.toString()
        })

    text: placeholder ? UpgradeLog.escape(placeholder) : UpgradeLog.markup(lines, kindColors)
    textFormat: Text.StyledText
    font.family: Theme.monoFontFamily
    font.pixelSize: Theme.fontSizeSmall
    color: Theme.onSurface
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
}
