import QtQuick
import "../utils/widgets.js" as WidgetUtils

Loader {
    id: root

    required property var grid
    property var widgetData: ({})
    property int savedIndex: -1
    property real columns: 1
    property real rows: 1
    property bool compact: false
    property bool small: false
    property bool bare: false

    sourceComponent: grid.model ? grid.model.componentForWidget(widgetData) : null

    Binding {
        target: root.item
        property: "widgetData"
        value: root.widgetData
        when: root.item !== null
    }

    Binding {
        target: root.item
        property: "widgetDef"
        value: root.grid.model?.getWidgetForId(root.widgetData.id || "") ?? null
        when: root.item !== null
    }

    Binding {
        target: root.item
        property: "host"
        value: root.grid
        when: root.item !== null
    }

    Binding {
        target: root.item
        property: "live"
        value: root.grid.live
        when: root.item !== null
    }

    Binding {
        target: root.item
        property: "interactive"
        value: !root.grid.editMode || root.widgetData.id === WidgetUtils.EDIT_ID
        when: root.item !== null
    }

    Binding {
        target: root.item
        property: "columns"
        value: root.columns
        when: root.item !== null
    }

    Binding {
        target: root.item
        property: "rows"
        value: root.rows
        when: root.item !== null
    }

    Binding {
        target: root.item
        property: "compact"
        value: root.compact
        when: root.item !== null
    }

    Binding {
        target: root.item
        property: "small"
        value: root.small
        when: root.item !== null && "small" in root.item
    }

    Binding {
        target: root.item
        property: "bare"
        value: root.bare
        when: root.item !== null && "bare" in root.item
    }

    Connections {
        target: root.item
        ignoreUnknownSignals: true

        function onExpandClicked() {
            if (root.grid.editMode)
                return;
            root.grid.expandClicked(root.widgetData);
        }

        function onOptionChanged(key, value) {
            root.grid.model?.setOption(root.savedIndex, key, value);
        }
    }
}
