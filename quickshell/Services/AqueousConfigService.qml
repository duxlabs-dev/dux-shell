pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import qs.Services
import qs.Common
import "../Common/BlurStrength.js" as BlurStrength

Singleton {
    id: root
    readonly property var log: Log.scoped("AqueousConfigService")
    property bool busy: false

    function requireCapabilities(result, required) {
        if (result?.protocol !== 1 || !Array.isArray(result.capabilities))
            throw new Error("unsupported aqueous-config protocol or discovery");
        for (const capability of required) {
            if (!result.capabilities.includes(capability))
                throw new Error("unsupported aqueous-config capability: " + capability);
        }
    }

    function helper(operation, input, callback) {
        const args = ["aqueous-config", operation, "--shell", "dms"];
        if (input !== null)
            args.push("--request", "-");
        AqueousService.runJson(args, input, (result, error) => {
            if (!error && result?.ok !== true)
                error = result?.code ? result.code + ": " + (result.message || "") : "aqueous-config rejected the request";
            callback(result, error);
        });
    }

    function request(operation, draft, callback) {
        if (!CompositorService.isAqueous || busy) {
            callback(null, busy ? "busy" : "unavailable");
            return;
        }
        busy = true;
        const complete = (result, error) => {
            busy = false;
            if (error)
                log.warn("helper operation failed:", operation, error);
            callback(error ? null : result, error);
        };
        if (operation === "snapshot") {
            helper("snapshot", null, (result, error) => {
                try {
                    if (error)
                        throw new Error(error);
                    requireCapabilities(result, ["schema_fields", "shell_dms"]);
                    if (typeof result.generation !== "string" || !result.generation)
                        throw new Error("missing configuration generation");
                    complete(result, "");
                } catch (e) {
                    complete(null, String(e));
                }
            });
            return;
        }
        if (!["apply", "validate"].includes(operation) || typeof draft?.expected_generation !== "string" || !draft.expected_generation) {
            complete(null, "invalid operation or missing expected_generation; reload configuration");
            return;
        }
        const request = Object.assign({}, draft, {
            protocol: 1
        });
        request.backup_dir = request.backup_dir || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/dms/aqueous-backups";
        const input = JSON.stringify(request);
        const required = ["validate", "stdin_requests", "generation_check", "atomic_file_replace", "shell_dms"];
        for (const [key, capability] of Object.entries({
            monitor_changes: "monitor_modes",
            custom_keybind_changes: "keybinds",
            sync_cursor: "cursor_sync",
            sync_typography: "typography_sync"
        })) {
            if (Object.prototype.hasOwnProperty.call(request, key))
                required.push(capability);
        }
        helper("version", null, (version, error) => {
            try {
                if (error)
                    throw new Error(error);
                requireCapabilities(version, required);
            } catch (e) {
                complete(null, String(e));
                return;
            }
            helper("validate", input, (validated, error) => {
                if (error || operation === "validate") {
                    complete(validated, error);
                    return;
                }
                helper("apply", input, complete);
            });
        });
    }

    function buildOutputsConfig(snapshot, outputs, original) {
        if (!snapshot.capabilities?.includes("monitor_modes"))
            throw new Error("unsupported: monitor_modes");
        const raw = (snapshot.raw_files?.outputs || "") + "\n" + (snapshot.raw_files?.wm || "");
        if (/^\s*edid\s*=/m.test(raw))
            throw new Error("unsupported: this aqueous-config version does not expose EDID monitor edits");
        const transforms = ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"];
        const changes = [];
        if ((snapshot.monitors || []).some(m => /[*?\[]/.test(m.name)))
            throw new Error("unsupported: reconcile wildcard monitor configuration before persisting displays");
        for (const output of outputs) {
            const before = original.find(o => o.name === output.name);
            if (!before)
                throw new Error("conflict: output changed during preview");
            if (output.enabled !== before.enabled)
                throw new Error("unsupported: this aqueous-config version cannot persist output enablement");
            if (output.adaptiveSync !== before.adaptiveSync)
                throw new Error("unsupported: this aqueous-config version cannot persist adaptive sync");
            if (!output.enabled)
                continue;
            const configured = (snapshot.monitors || []).filter(m => m.name === output.name);
            if (configured.length > 1)
                throw new Error("conflict: multiple configured monitor entries");
            const monitor = configured[0];
            if (Math.abs(output.scale - (monitor?.scale ?? 1)) > 0.0001)
                throw new Error("unsupported: this aqueous-config version cannot persist output scale");
            const mode = output.currentMode;
            if (!mode)
                throw new Error("unavailable: output mode");
            changes.push({
                id: monitor?.id || "live:" + output.name,
                name: output.name,
                x: output.x,
                y: output.y,
                transform: transforms[output.transform],
                mode: mode.width + "x" + mode.height + "@" + (mode.refresh / 1000)
            });
        }
        return {
            expected_generation: snapshot.generation,
            monitor_changes: changes,
            create_user_override: true
        };
    }

    function load(callback) {
        request("snapshot", null, callback);
    }

    function apply(draft, callback) {
        request("apply", draft, callback);
    }

    // 0 restores the schema default so a reset does not pin the last slider value in the user override
    function applyBlurStrength() {
        load((snapshot, error) => {
            if (!snapshot)
                return;
            const field = snapshot.fields?.find(f => f.id === "blur.radius");
            if (!field)
                return;
            const strength = SettingsData.blurStrength;
            const radius = strength > 0 ? BlurStrength.aqueousRadius(strength) : field.default;
            if (!Number.isFinite(radius) || radius === field.value)
                return;
            apply({
                expected_generation: snapshot.generation,
                create_user_override: true,
                changes: [{ id: "blur.radius", value: radius }]
            }, () => {});
        });
    }
}
