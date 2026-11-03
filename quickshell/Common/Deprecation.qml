pragma Singleton

import QtQuick
import Quickshell
import qs.Services

Singleton {
    readonly property var log: Log.scoped("Deprecation")
    readonly property var _warned: ({})

    function type(instance, oldName, newName, module) {
        _emit(instance, oldName, `${oldName} is deprecated and will be removed in a future release.`, `Replace it with ${newName} from ${module}.`);
    }

    function module(instance, name, oldModule, newModule) {
        _emit(instance, oldModule, `${oldModule} is deprecated and will be removed in a future release.`, `Import ${name} from ${newModule} instead.`);
    }

    function _emit(instance, subject, headline, advice) {
        const plugin = _owningPlugin(instance);
        const key = subject + "@" + (plugin ? plugin.id : "");
        if (_warned[key])
            return;
        _warned[key] = true;
        const lines = [headline, advice];
        if (plugin)
            lines.push(`Used by the "${plugin.name}" plugin (${plugin.id}, by ${plugin.author}). Contact the plugin author to update it.`);
        log.error(lines.join("\n    "));
    }

    function _owningPlugin(instance) {
        for (let o = instance; o; o = o.parent ?? null) {
            if (typeof o.pluginId !== "string" || !o.pluginId)
                continue;
            const info = PluginService.availablePlugins[o.pluginId];
            return {
                id: o.pluginId,
                name: info?.name ?? o.pluginId,
                author: info?.author ?? "unknown"
            };
        }
        return null;
    }
}
