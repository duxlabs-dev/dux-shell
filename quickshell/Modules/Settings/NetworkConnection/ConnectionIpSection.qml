pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor
    property int family: 4

    readonly property string sectionKey: family === 6 ? "ipv6" : "ipv4"
    // A fresh copy per revision, so bindings re-evaluate when the host mutates the draft in place
    readonly property var section: {
        root.editor.revision;
        return Object.assign({}, root.editor.draft?.[root.sectionKey]);
    }
    // The host assigns a new draft object on discard and reload; text fields re-prefill then
    readonly property var draftObject: editor.draft
    readonly property string method: section.method ?? "auto"
    readonly property bool isManual: method === "manual"
    readonly property bool isOff: method === "disabled" || method === "ignore"
    readonly property bool isAuto: method === "auto" || method === "dhcp"
    readonly property bool hasAddress: (section["address-data"] ?? []).length > 0
    readonly property bool dnsAllowed: CE.disallowedIpKeys(family, method).indexOf("dns-data") < 0

    property var routes: []
    property bool routesOk: true

    readonly property bool valid: isOff || ((!isManual || (hasAddress && addressRow.ok && gatewayRow.ok)) && (!dnsAllowed || dnsRow.ok) && metricRow.ok && routesOk)

    title: family === 6 ? I18n.tr("IPv6", "network IP version") : I18n.tr("IPv4", "network IP version")
    enabled: !editor.readOnly

    function original(key) {
        return editor.original?.[sectionKey]?.[key];
    }

    // A value equal to NM's default is removed rather than written, unless the profile stored it that way.
    function write(key, value, defaultValue) {
        const drop = CE.deepEqual(value, defaultValue) && !CE.deepEqual(original(key), value);
        editor.setValue(sectionKey, key, drop ? undefined : value);
    }

    function methodLabel(m) {
        switch (m) {
        case "auto":
            return I18n.tr("Auto");
        case "dhcp":
            return "DHCP";
        case "manual":
            return I18n.tr("Manual");
        case "link-local":
            return I18n.tr("Link-local", "network IP method option");
        case "shared":
            return I18n.tr("Shared", "IP method: share this connection with other computers");
        case "ignore":
            return I18n.tr("Ignore", "leave as the driver or system configured it");
        case "disabled":
            return I18n.tr("Disabled");
        }
        return String(m);
    }

    function privacyLabel(v) {
        switch (v) {
        case -1:
            return I18n.tr("Default");
        case 0:
            return I18n.tr("Disabled");
        case 2:
            return I18n.tr("Enabled");
        }
        return String(v);
    }

    function addrGenLabel(v) {
        switch (v) {
        case 3:
            return I18n.tr("Default");
        case 0:
            return "EUI-64";
        case 1:
            return I18n.tr("Stable privacy", "IPv6 address generation mode");
        case 2:
            return "default-or-eui64";
        }
        return String(v);
    }

    function loadRoutes() {
        routes = CE.routeRows(section["route-data"]);
        routesOk = true;
    }

    function writeRoutes() {
        const data = CE.routeDataFromRows(routes, family);
        routesOk = data !== null;
        if (data !== null)
            write("route-data", data, []);
    }

    function addRoute() {
        routes = routes.concat([
            {
                "dest": "",
                "nextHop": "",
                "metric": "",
                "extra": {}
            }
        ]);
        writeRoutes();
    }

    function removeRoute(index) {
        routes = routes.filter((_, i) => i !== index);
        writeRoutes();
    }

    // Edits mutate the row in place so the Repeater keeps its delegates (and focus) while typing.
    function editRoute(index, key, text) {
        routes[index][key] = text;
        writeRoutes();
    }

    function setMethod(value) {
        editor.setSection(sectionKey, CE.applyIpMethod(section, family, value, editor.original?.[sectionKey]));
        addressRow.sync();
        gatewayRow.sync();
        dnsRow.sync();
        searchRow.sync();
    }

    function resync() {
        addressRow.sync();
        gatewayRow.sync();
        dnsRow.sync();
        searchRow.sync();
        metricRow.sync();
        loadRoutes();
    }

    onDraftObjectChanged: resync()
    Component.onCompleted: loadRoutes()

    component TextRow: SettingsTextFieldRow {
        id: textRow

        property string source: ""
        property var commit: text => true
        property bool ok: true

        function sync() {
            value = source;
            ok = true;
        }

        isError: !ok
        Component.onCompleted: sync()
        onValueEdited: text => textRow.ok = textRow.commit(text)
    }

    // Shows a stored value it can't name as an extra literal option; picking it again writes nothing.
    component EnumRow: SettingsDropdownRow {
        id: enumRow

        property var values: []
        property var labelFor: v => String(v)
        property var stored
        readonly property var allValues: values.indexOf(stored) >= 0 ? values : values.concat([stored])

        signal picked(var value)

        options: allValues.map(v => labelFor(v))
        currentValue: labelFor(stored)
        onValueChanged: label => {
            const i = enumRow.options.indexOf(label);
            if (i < 0 || enumRow.allValues[i] === enumRow.stored)
                return;
            enumRow.picked(enumRow.allValues[i]);
        }
    }

    component RouteField: DTextField {
        property int share: 2
        property Row fields

        width: fields ? Math.round((fields.width - fields.spacing * 3 - Theme.iconButtonSize) * share / 5) : 0
        outlined: true
    }

    EnumRow {
        text: I18n.tr("Method", "IP configuration method")
        values: CE.ipMethods(root.family)
        labelFor: m => root.methodLabel(m)
        stored: root.method
        onPicked: value => root.setMethod(value)
    }

    TextRow {
        id: addressRow
        visible: root.isManual
        text: I18n.tr("IP address")
        source: CE.addressText(root.section["address-data"])
        commit: text => {
            const list = CE.addressDataFromText(text, root.family, root.original("address-data"));
            if (list === null)
                return false;
            root.write("address-data", list, []);
            return true;
        }
    }

    TextRow {
        id: gatewayRow
        visible: root.isManual
        text: I18n.tr("Gateway", "network IP setting label")
        source: root.section.gateway ?? ""
        commit: text => {
            const t = text.trim();
            if (t !== "" && !CE.isValidIp(t, root.family))
                return false;
            root.write("gateway", t, "");
            return true;
        }
    }

    TextRow {
        id: dnsRow
        visible: root.dnsAllowed
        text: I18n.tr("DNS", "network IP setting label")
        source: CE.listText(root.section["dns-data"])
        commit: text => {
            const list = CE.serverListFromText(text, root.family);
            if (list === null)
                return false;
            root.write("dns-data", list, []);
            return true;
        }
    }

    TextRow {
        id: searchRow
        visible: root.dnsAllowed
        text: I18n.tr("Search domains", "network DNS setting")
        source: CE.listText(root.section["dns-search"])
        commit: text => {
            root.write("dns-search", CE.domainListFromText(text), []);
            return true;
        }
    }

    SettingsToggleRow {
        visible: root.isAuto
        text: I18n.tr("Automatic DNS", "network IP setting: use DNS servers from DHCP")
        checked: root.section["ignore-auto-dns"] !== true
        onToggled: checked => root.write("ignore-auto-dns", !checked, false)
    }

    SettingsToggleRow {
        visible: root.isAuto
        text: I18n.tr("Automatic routes", "network IP setting: use routes from DHCP")
        checked: root.section["ignore-auto-routes"] !== true
        onToggled: checked => root.write("ignore-auto-routes", !checked, false)
    }

    TextRow {
        id: metricRow
        visible: !root.isOff
        text: I18n.tr("Metric", "route metric")
        source: {
            const m = root.section["route-metric"];
            return m === undefined || m === null || m === -1 ? "" : String(m);
        }
        commit: text => {
            const t = text.trim();
            if (t !== "" && !/^-?\d{1,10}$/.test(t))
                return false;
            const n = t === "" ? -1 : Number(t);
            if (n < -1 || n > 4294967295)
                return false;
            root.write("route-metric", n, -1);
            return true;
        }
    }

    SettingsToggleRow {
        visible: !root.isOff
        text: I18n.tr("Required", "connection fails if this IP version can't be configured")
        checked: root.section["may-fail"] === false
        onToggled: checked => root.write("may-fail", !checked, true)
    }

    SettingsToggleRow {
        visible: !root.isOff
        text: I18n.tr("Use only for resources on its network", "network IP setting: never use this connection as the default route")
        checked: root.section["never-default"] === true
        onToggled: checked => root.write("never-default", checked, false)
    }

    EnumRow {
        visible: root.family === 6 && !root.isOff
        text: I18n.tr("Privacy")
        values: [-1, 0, 2]
        labelFor: v => root.privacyLabel(v)
        // NM's 1 (prefer public address) displays as Enabled and stays 1 until changed
        stored: {
            const p = root.section["ip6-privacy"] ?? -1;
            return p === 1 ? 2 : p;
        }
        onPicked: value => root.write("ip6-privacy", value, -1)
    }

    EnumRow {
        visible: root.family === 6 && !root.isOff
        text: I18n.tr("Address generation", "IPv6 interface identifier mode")
        values: [3, 0, 1]
        labelFor: v => root.addrGenLabel(v)
        stored: root.section["addr-gen-mode"] ?? 3
        onPicked: value => root.write("addr-gen-mode", value, 3)
    }

    SettingsRow {
        visible: !root.isOff
        title: I18n.tr("Routes", "network IP setting label")

        DButton {
            text: I18n.tr("Add entry")
            iconName: "add"
            buttonHeight: Theme.buttonHeightXS
            variant: "text"
            onClicked: root.addRoute()
        }
    }

    Repeater {
        model: root.isOff ? [] : root.routes

        delegate: SettingsRow {
            id: routeRow

            required property var modelData
            required property int index

            body: Row {
                id: routeFields

                width: parent.width
                spacing: Theme.spacingS

                RouteField {
                    fields: routeFields
                    labelText: I18n.tr("Network", "route destination network")
                    text: routeRow.modelData.dest
                    isError: CE.routeDataFromRows([
                        {
                            "dest": text
                        }
                    ], root.family) === null
                    onTextEdited: root.editRoute(routeRow.index, "dest", text)
                }

                RouteField {
                    fields: routeFields
                    labelText: I18n.tr("Gateway", "network IP setting label")
                    text: routeRow.modelData.nextHop
                    isError: text.trim() !== "" && !CE.isValidIp(text, root.family)
                    onTextEdited: root.editRoute(routeRow.index, "nextHop", text)
                }

                RouteField {
                    fields: routeFields
                    share: 1
                    labelText: I18n.tr("Metric", "route metric")
                    text: routeRow.modelData.metric
                    isError: CE.routeDataFromRows([
                        {
                            "dest": root.family === 6 ? "::/0" : "0.0.0.0/0",
                            "metric": text
                        }
                    ], root.family) === null
                    onTextEdited: root.editRoute(routeRow.index, "metric", text)
                }

                DActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: Theme.iconButtonSize
                    iconName: "close"
                    tooltipText: I18n.tr("Remove", "verb, button that removes an item from a list")
                    onClicked: root.removeRoute(routeRow.index)
                }
            }
        }
    }
}
