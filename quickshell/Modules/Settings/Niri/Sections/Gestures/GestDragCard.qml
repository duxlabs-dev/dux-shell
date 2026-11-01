import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Components

// The two drag-edge settings niri exposes.
NiriCard {
    icon: "drag_pan"
    title: I18n.tr("While dragging", "niri page card")

    NiriSlider {
        settingKey: "gestures.dndViewWidth"
        icon: "swap_horiz"
        title: I18n.tr("Side edges scroll", "niri gesture setting")
        tip: I18n.tr("Edge size that scrolls the view while you drag something. 0 turns it off.", "niri gesture setting")
        kdlKey: "gestures.dnd-edge-view-scroll.trigger-width"
        to: 100
        stepSize: 5
        unit: " px"
    }

    NiriSlider {
        settingKey: "gestures.dndWorkspaceHeight"
        icon: "swap_vert"
        title: I18n.tr("Top and bottom switch workspace", "niri gesture setting")
        tip: I18n.tr("Edge size that switches workspace while you drag something in the overview. 0 turns it off.", "niri gesture setting")
        kdlKey: "gestures.dnd-edge-workspace-switch.trigger-height"
        to: 100
        stepSize: 5
        unit: " px"
    }
}
