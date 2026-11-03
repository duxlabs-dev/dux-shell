import QtQuick
import QtTest
import "../../Modules/DBar/Widgets/KeyboardLayoutLabels.js" as KeyboardLayoutLabels

TestCase {
    name: "KeyboardLayoutLabels"

    readonly property var validVariants: KeyboardLayoutLabels.VALID_VARIANTS

    function test_overrideReplacesRawHyprlandCompactLabel() {
        compare(KeyboardLayoutLabels.displayLabel("am-phonetic-alt", true, true, validVariants, {
            "am-phonetic-alt": "am"
        }), "am");
    }

    function test_overrideKeyIsTheComputedLabelNotTheRawInput() {
        const label = KeyboardLayoutLabels.displayLabel("English (US)", true, false, validVariants, {});
        compare(KeyboardLayoutLabels.displayLabel("English (US)", true, false, validVariants, {
            [label]: "en"
        }), "en");
    }

    function test_verticalLabelOverrideIsKeyedIndependentlyFromHorizontal() {
        const label = KeyboardLayoutLabels.verticalLabel("am-phonetic-alt", {});
        compare(KeyboardLayoutLabels.verticalLabel("am-phonetic-alt", {
            [label]: "hy"
        }), "hy");
    }
}
