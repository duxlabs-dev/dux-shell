import QtQuick
import qs.Common
import qs.Modules.Settings

ColorDropdownRow {
    id: root

    readonly property var surfaceColorOptions: [({
                "value": "default",
                "label": I18n.tr("Default", "surface color option")
            }), ({
                "value": "s",
                "label": I18n.tr("Surface", "surface color option")
            }), ({
                "value": "sc",
                "label": I18n.tr("Surface Container", "surface color option")
            }), ({
                "value": "sch",
                "label": I18n.tr("Surface High", "surface color option")
            }), ({
                "value": "schh",
                "label": I18n.tr("Surface Highest", "surface color option")
            }), ({
                "value": "inverseSurface",
                "label": I18n.tr("Inverse Surface", "surface color option")
            }), ({
                "value": "primaryContainer",
                "label": I18n.tr("Primary Container", "surface color option")
            }), ({
                "value": "secondaryContainer",
                "label": I18n.tr("Secondary Container", "surface color option")
            }), ({
                "value": "tertiaryContainer",
                "label": I18n.tr("Tertiary Container", "surface color option")
            }), ({
                "value": "custom",
                "label": I18n.tr("Custom", "surface color option")
            })]

    dropdownWidth: 220
    options: root.surfaceColorOptions
}
