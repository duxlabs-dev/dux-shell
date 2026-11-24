pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Modules.ProfilePicker

DModal {
    id: root

    property string view: "carousel"
    readonly property real carouselShadeAlpha: 0.75

    function openOn(screen, pickerView) {
        // The dash view has no modal layout.
        root.view = pickerView === "dash" ? "carousel" : pickerView;
        root.targetScreen = screen;
        root.open();
    }

    layerNamespace: "dms:profile-picker"
    showSurface: root.view !== "carousel"
    backgroundOpacity: showSurface ? Theme.scrimAlpha : carouselShadeAlpha
    modalWidth: Math.min(root.contentLoader.item?.implicitWidth ?? 0, root.screenWidth - 2 * Theme.spacingXL)
    modalHeight: Math.min(root.contentLoader.item?.implicitHeight ?? 0, root.screenHeight - 2 * Theme.spacingXL)

    onBackgroundClicked: close()
    onShouldBeVisibleChanged: {
        if (shouldBeVisible)
            root.contentLoader.item?.reset();
    }
    onShouldHaveFocusChanged: {
        if (shouldHaveFocus)
            Qt.callLater(() => root.contentLoader.item?.focusContent());
    }

    content: Component {
        ProfilePickerContent {
            anchors.fill: parent
            focus: true
            view: root.view
            targetScreen: root.targetScreen
            availableWidth: root.screenWidth - 2 * Theme.spacingXL
            onCloseRequested: root.close()
        }
    }
}
