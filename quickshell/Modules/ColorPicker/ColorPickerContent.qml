pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets as CommonWidgets

DDialog {
    id: root

    readonly property var log: Log.scoped("ColorPickerContent")
    property string pickerTitle: I18n.tr("Choose color", "color picker title")
    property color initialColor: Theme.primary
    property bool showSaveButton: false
    property bool pickingFromScreen: false
    property int screenPickGeneration: 0
    property color currentColor: Theme.primary
    property real hue: 0
    property real saturation: 1
    property real value: 1
    property real alpha: 1
    readonly property bool compact: contentItem.width < Theme.smallBreakpoint
    readonly property bool validHex: /^#?[0-9a-f]{6}([0-9a-f]{2})?$/i.test(hexInput.text.trim())
    readonly property string rgbText: {
        const channels = [currentColor.r, currentColor.g, currentColor.b].map(channel => Math.round(channel * 255)).join(", ");
        if (alpha < 1)
            return `rgba(${channels}, ${Number(alpha.toFixed(3))})`;
        return `rgb(${channels})`;
    }
    readonly property string hsvText: {
        const channels = [Math.round(hue * 360), Math.round(saturation * 100), Math.round(value * 100)];
        if (alpha < 1)
            channels.push(Math.round(alpha * 100));
        return channels.join(", ");
    }
    readonly property var standardColors: ["#f44336", "#e91e63", "#9c27b0", "#673ab7", "#3f51b5", "#2196f3", "#03a9f4", "#00bcd4", "#009688", "#4caf50", "#8bc34a", "#cddc39", "#ffeb3b", "#ffc107", "#ff9800", "#ff5722", "#d32f2f", "#c2185b", "#7b1fa2", "#512da8", "#303f9f", "#1976d2", "#0288d1", "#0097a7", "#00796b", "#388e3c", "#689f38", "#afb42b", "#fbc02d", "#ffa000", "#f57c00", "#e64a19", "#c62828", "#ad1457", "#6a1b9a", "#4527a0", "#283593", "#1565c0", "#0277bd", "#00838f", "#00695c", "#2e7d32", "#558b2f", "#9e9d24", "#f9a825", "#ff8f00", "#ef6c00", "#d84315", "#ffffff", "#9e9e9e", "#212121"]

    readonly property alias hexInput: hexInput
    signal colorSelected(color selectedColor)
    signal closeRequested
    signal hideRequested
    signal showRequested

    title: pickerTitle
    iconName: "palette"
    popout: windowControls === null
    padding: PopoutMetrics.contentPadding
    contentSpacing: PopoutMetrics.contentGap
    acceptEnabled: false
    onRejected: closeRequested()
    Component.onCompleted: setColor(initialColor)

    function focusInitial() {
        gradientPicker.forceActiveFocus(Qt.OtherFocusReason);
    }

    function setColor(color) {
        const parsed = Qt.color(color);
        hue = Math.max(0, parsed.hsvHue);
        saturation = parsed.hsvSaturation;
        value = parsed.hsvValue;
        alpha = parsed.a;
        currentColor = parsed;
        hexInput.text = currentColor.toString();
    }

    function updateColor() {
        currentColor = Qt.hsva(hue, saturation, value, alpha);
        hexInput.text = currentColor.toString();
    }

    function applyHex() {
        if (!validHex)
            return false;
        const text = hexInput.text.trim();
        setColor(text.startsWith("#") ? text : "#" + text);
        return true;
    }

    function copyColor(text) {
        Quickshell.execDetached([Proc.dmsBin, "cl", "copy", text]);
        ToastService.showInfo(I18n.tr("Color %1 copied", "color picker toast, %1 is the copied color value").arg(text));
        SessionData.addRecentColor(currentColor);
    }

    function saveColor() {
        if (!applyHex())
            return;
        SessionData.addRecentColor(currentColor);
        colorSelected(currentColor);
        closeRequested();
    }

    function finishScreenPick(output, exitCode) {
        pickingFromScreen = false;
        if (exitCode !== 0 || !output.trim()) {
            showRequested();
            return;
        }
        try {
            const result = JSON.parse(output);
            if (/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(result?.hex ?? "")) {
                setColor(result.hex);
                copyColor(result.hex);
            }
        } catch (error) {
            log.warn("Failed to parse dms color pick JSON:", error);
        }
        showRequested();
    }

    function cancelScreenPick() {
        screenPickGeneration++;
        pickingFromScreen = false;
    }

    function pickColorFromScreen() {
        if (pickingFromScreen)
            return;
        pickingFromScreen = true;
        screenPickGeneration++;
        hideRequested();
    }

    function startScreenPick() {
        if (!pickingFromScreen)
            return;
        const generation = screenPickGeneration;
        Proc.runCommand(null, [Proc.dmsBin, "color", "pick", "--json"], (output, exitCode) => {
            if (generation === root.screenPickGeneration)
                root.finishScreenPick(output, exitCode);
        }, 0, Proc.noTimeout, root);
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        CommonWidgets.DSaturationValuePicker {
            id: gradientPicker

            width: parent.width
            height: Theme.fieldDefaultWidth
            hue: root.hue
            saturation: root.saturation
            value: root.value
            onColorChanged: (saturation, value) => {
                root.saturation = saturation;
                root.value = value;
                root.updateColor();
            }
        }

        DSlider {
            id: hueSlider

            width: parent.width
            minimum: 0
            maximum: 360
            unit: "°"
            fillColor: Theme.onSurface
            showValue: false
            wheelEnabled: false
            Accessible.name: I18n.tr("Hue", "Hue angle in the color picker")
            onSliderValueChanged: value => {
                root.hue = value / 360;
                root.updateColor();
            }

            trackGradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: Qt.hsva(0, 1, 1, 1)
                }
                GradientStop {
                    position: 1 / 6
                    color: Qt.hsva(1 / 6, 1, 1, 1)
                }
                GradientStop {
                    position: 2 / 6
                    color: Qt.hsva(2 / 6, 1, 1, 1)
                }
                GradientStop {
                    position: 3 / 6
                    color: Qt.hsva(3 / 6, 1, 1, 1)
                }
                GradientStop {
                    position: 4 / 6
                    color: Qt.hsva(4 / 6, 1, 1, 1)
                }
                GradientStop {
                    position: 5 / 6
                    color: Qt.hsva(5 / 6, 1, 1, 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.hsva(1, 1, 1, 1)
                }
            }

            Binding {
                target: hueSlider
                property: "value"
                value: Math.round(root.hue * 360)
            }
        }
    }

    GridLayout {
        width: parent.width
        columns: root.compact ? 1 : 2
        columnSpacing: PopoutMetrics.contentGap
        rowSpacing: PopoutMetrics.contentGap

        RowLayout {
            Layout.alignment: Qt.AlignBottom
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.fieldDefaultWidth
            spacing: Theme.spacingS

            DColorSwatch {
                Layout.preferredWidth: hexInput.controlHeight
                Layout.preferredHeight: hexInput.controlHeight
                Layout.topMargin: hexInput.containerTop
                swatchColor: root.currentColor
                minPreviewAlpha: 0
            }

            DTextField {
                id: hexInput

                Layout.fillWidth: true
                outlined: true
                controlHeight: Theme.fieldHeightLarge
                labelText: I18n.tr("Hex", "color picker field label for the hexadecimal color code")
                font.family: Theme.monoFontFamily
                placeholderText: "#000000"
                isError: !root.validHex
                onAccepted: root.applyHex()
                onEditingFinished: root.applyHex()
            }

            DActionButton {
                Layout.topMargin: hexInput.containerTop
                iconName: "content_copy"
                Accessible.name: I18n.tr("Copy")
                enabled: root.validHex
                onClicked: {
                    if (root.applyHex())
                        root.copyColor(root.currentColor.toString());
                }
            }

            DActionButton {
                Layout.topMargin: hexInput.containerTop
                iconName: "colorize"
                Accessible.name: I18n.tr("Pick Color")
                enabled: !root.pickingFromScreen
                onClicked: root.pickColorFromScreen()
            }
        }

        Column {
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.fieldDefaultWidth
            spacing: Theme.spacingXS

            RowLayout {
                width: parent.width

                StyledText {
                    Layout.fillWidth: true
                    text: I18n.tr("Opacity")
                    color: Theme.onSurfaceVariant
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignLeft
                }

                NumericText {
                    text: Math.round(root.alpha * 100) + "%"
                    color: Theme.onSurface
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            DSlider {
                id: opacitySlider

                width: parent.width
                minimum: 0
                maximum: 100
                showValue: false
                wheelEnabled: false
                Accessible.name: I18n.tr("Opacity")
                onSliderValueChanged: value => {
                    root.alpha = value / 100;
                    root.updateColor();
                }

                Binding {
                    target: opacitySlider
                    property: "value"
                    value: Math.round(root.alpha * 100)
                }
            }
        }
    }

    SettingsGroup {
        slotColor: Theme.foregroundColor(Theme.cardSurface, root.windowControls !== null)

        SettingsRow {
            title: "RGB"
            subtitle: root.rgbText
            paddingH: Theme.spacingL
            paddingV: Theme.spacingS

            DActionButton {
                iconName: "content_copy"
                Accessible.name: I18n.tr("Copy")
                onClicked: root.copyColor(root.rgbText)
            }
        }

        SettingsRow {
            title: "HSV"
            subtitle: root.hsvText
            paddingH: Theme.spacingL
            paddingV: Theme.spacingS

            DActionButton {
                iconName: "content_copy"
                Accessible.name: I18n.tr("Copy")
                onClicked: root.copyColor(root.hsvText)
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        Grid {
            id: palette

            width: parent.width
            columns: Math.max(1, Math.floor(width / Theme.buttonHeightXS))
            spacing: 0

            Repeater {
                model: root.standardColors

                CommonWidgets.DColorButton {
                    required property string modelData
                    width: palette.width / palette.columns
                    height: Theme.buttonHeightXS
                    swatchColor: modelData
                    selected: Qt.colorEqual(root.currentColor, swatchColor)
                    onClicked: root.setColor(swatchColor)
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS
        visible: SessionData.recentColors.length > 0

        StyledText {
            width: parent.width
            text: I18n.tr("Recent Colors")
            color: Theme.primary
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            horizontalAlignment: Text.AlignLeft
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingXS

            Repeater {
                model: SessionData.recentColors.slice(0, 5)

                Item {
                    id: recentSwatch

                    required property var modelData

                    implicitWidth: recentButton.implicitWidth
                    implicitHeight: recentButton.implicitHeight

                    HoverHandler {
                        id: recentHover
                    }

                    CommonWidgets.DColorButton {
                        id: recentButton
                        anchors.fill: parent
                        swatchColor: recentSwatch.modelData
                        selected: Qt.colorEqual(root.currentColor, swatchColor)
                        onClicked: root.setColor(swatchColor)
                        Keys.onDeletePressed: SessionData.removeRecentColor(recentSwatch.modelData)
                        Keys.onPressed: event => {
                            if (event.key !== Qt.Key_Backspace)
                                return;
                            SessionData.removeRecentColor(recentSwatch.modelData);
                            event.accepted = true;
                        }
                    }

                    CommonWidgets.DActionButton {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: -Theme.spacingXS
                        buttonSize: Theme.iconSizeSmall + Theme.spacingXS
                        iconSize: Theme.iconSizeSmall - Theme.spacingXS
                        iconName: "close"
                        backgroundColor: Theme.surfaceContainerHighest
                        focusPolicy: Qt.NoFocus
                        visible: recentHover.hovered
                        tooltipText: I18n.tr("Remove from recent colors", "button on a recently picked color swatch")
                        onClicked: SessionData.removeRecentColor(recentSwatch.modelData)
                    }
                }
            }
        }
    }

    actions: DButton {
        maximumWidth: root.actionWidth
        wrapText: true
        text: I18n.tr("Save")
        visible: root.showSaveButton
        enabled: root.validHex
        onClicked: root.saveColor()
    }
}
