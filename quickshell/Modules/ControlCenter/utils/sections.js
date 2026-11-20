const instancePrefixes = ["diskUsage_", "brightnessSlider_"]

function parse(section) {
    for (const prefix of instancePrefixes) {
        if (section.startsWith(prefix))
            return { base: prefix.slice(0, -1), instanceId: section.slice(prefix.length) }
    }
    return { base: section, instanceId: "" }
}

function sectionFor(widgetData) {
    const id = widgetData.id || ""
    if (id !== "diskUsage" && id !== "brightnessSlider")
        return id
    return id + "_" + (widgetData.instanceId || "default")
}

function widgetForSection(section, widgets = SettingsData.controlCenterWidgets || []) {
    const parsed = parse(section)
    if (!parsed.instanceId)
        return widgets.find(w => w.id === parsed.base) || null
    return widgets.find(w => w.id === parsed.base && (w.instanceId || "default") === parsed.instanceId) || null
}

function updateWidgetForSection(section, patch) {
    const parsed = parse(section)
    const widgets = (SettingsData.controlCenterWidgets || []).map(w => {
        if (w.id !== parsed.base)
            return w
        if (parsed.instanceId && (w.instanceId || "default") !== parsed.instanceId)
            return w
        return Object.assign({}, w, patch)
    })
    SettingsData.set("controlCenterWidgets", widgets)
}
