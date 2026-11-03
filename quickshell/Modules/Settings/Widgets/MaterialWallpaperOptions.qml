pragma Singleton

import QtQuick
import qs.Common

QtObject {
    readonly property var builtinLabels: ({
            "dank": I18n.tr("Dank", "Material wallpaper preset"),
            "bloom": I18n.tr("Bloom", "Material wallpaper preset"),
            "orbit": I18n.tr("Orbit", "Material wallpaper preset"),
            "garden": I18n.tr("Garden", "Material wallpaper preset"),
            "petal": I18n.tr("Petal", "Material wallpaper preset"),
            "dune": I18n.tr("Dune", "Material wallpaper preset")
        })
    readonly property var seedHues: [
        {
            value: "red",
            label: I18n.tr("Red", "seed color hue")
        },
        {
            value: "orange",
            label: I18n.tr("Orange", "seed color hue")
        },
        {
            value: "yellow",
            label: I18n.tr("Yellow", "seed color hue")
        },
        {
            value: "green",
            label: I18n.tr("Green", "seed color hue")
        },
        {
            value: "teal",
            label: I18n.tr("Teal", "seed color hue")
        },
        {
            value: "blue",
            label: I18n.tr("Blue", "seed color hue")
        },
        {
            value: "purple",
            label: I18n.tr("Purple", "seed color hue")
        },
        {
            value: "pink",
            label: I18n.tr("Pink", "seed color hue")
        }
    ]
    function profileLabel(profile) {
        return profile.builtin ? builtinLabels[profile.id] ?? profile.id : profile.name;
    }
    function label(options, value) {
        return options.find(option => option.value === value)?.label ?? "";
    }
}
