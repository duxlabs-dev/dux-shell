import QtQuick
import qs.Common
import qs.Modules.Frame

// Cutout edges sit 1px off-screen: on the screen edge itself the SDF antialiasing draws a faint line.
FrameBorder {
    cutoutTopInset: -1
    cutoutBottomInset: -1
    cutoutLeftInset: -1
    cutoutRightInset: -1
    cutoutRadius: Math.min(SettingsData.screenCornerRadius, ShellLayout.screenCornerLimit) + 1
    borderColor: Theme.screenOffColor
}
