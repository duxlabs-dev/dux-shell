pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Scope {
    id: root

    Variants {
        model: ShellLayout.realScreens

        delegate: Scope {
            required property var modelData

            ScreenCornerWindow {
                targetScreen: modelData
                corner: "topLeft"
            }
            ScreenCornerWindow {
                targetScreen: modelData
                corner: "topRight"
            }
            ScreenCornerWindow {
                targetScreen: modelData
                corner: "bottomLeft"
            }
            ScreenCornerWindow {
                targetScreen: modelData
                corner: "bottomRight"
            }
        }
    }
}
