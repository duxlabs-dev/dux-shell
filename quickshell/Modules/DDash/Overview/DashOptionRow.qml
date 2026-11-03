import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.DDash

SettingsRow {
    id: root

    required property var spec
    property var value

    readonly property var choices: spec.choices ?? []
    readonly property int choiceIndex: choices.findIndex(c => c.value === value)

    signal committed(var next)

    function commit(next) {
        committed(next);
    }

    title: spec.text ?? spec.key
    subtitle: spec.description ?? ""
    clickable: spec.type === "toggle"
    onClicked: commit(value !== true)

    Loader {
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: {
            switch (root.spec.type) {
            case "toggle":
                return toggleControl;
            case "choice":
                return choiceControl;
            case "number":
                return numberControl;
            case "slider":
                return sliderLabel;
            }
            return null;
        }
    }

    body: Loader {
        width: parent?.width ?? 0
        active: root.spec.type === "slider"
        sourceComponent: sliderControl
    }

    Component {
        id: toggleControl

        DToggle {
            hideText: true
            checked: root.value === true
            onToggled: checked => root.commit(checked)
        }
    }

    Component {
        id: choiceControl

        DDropdown {
            options: root.choices.map(c => c.text)
            currentValue: root.choices[root.choiceIndex]?.text ?? ""
            onValueChanged: value => {
                const choice = root.choices.find(c => c.text === value);
                if (!choice)
                    return;
                root.commit(choice.value);
            }
        }
    }

    Component {
        id: numberControl

        DNumberStepper {
            readonly property real step: root.spec.step ?? 1
            readonly property real current: Number(root.value) || 0

            text: current + (root.spec.unit ?? "")
            incrementEnabled: root.spec.max === undefined || current + step <= root.spec.max
            decrementEnabled: root.spec.min === undefined || current - step >= root.spec.min
            onIncrement: () => root.commit(current + step)
            onDecrement: () => root.commit(current - step)
        }
    }

    Component {
        id: sliderLabel

        StyledText {
            visible: root.value === root.spec.min
            text: root.spec.minimumLabel ?? ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    Component {
        id: sliderControl

        SettingsSliderControl {
            value: Number(root.value) || 0
            minimum: root.spec.min
            maximum: root.spec.max
            step: root.spec.step
            showValue: root.value !== root.spec.min
            accessibleName: root.title
            onSliderValueChanged: newValue => root.commit(newValue)
        }
    }
}
