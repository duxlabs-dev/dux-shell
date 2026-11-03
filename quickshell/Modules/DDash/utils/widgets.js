.import "../../../Common/GridLayout.js" as GridLayout
.import "options.js" as Options

var LAYOUT_KEYS = ["id", "w", "h", "col", "row"];

function optionSpecs(spec) {
    return (Array.isArray(spec?.options) ? spec.options : []).filter(option => option && typeof option.key === "string" && !LAYOUT_KEYS.includes(option.key));
}

function resolve(definitions, saved) {
    const source = Array.isArray(saved) ? saved : definitions.filter(d => d.enabled !== false);
    const seen = Object.create(null);
    return source.filter(item => {
        if (!item || typeof item.id !== "string" || seen[item.id])
            return false;
        seen[item.id] = true;
        return true;
    }).map(item => {
        const spec = definitions.find(d => d.id === item.id);
        if (!spec)
            return item;
        const widget = {
            id: item.id,
            w: GridLayout.dimension(item.w, spec.minW, spec.maxW, spec.w),
            h: GridLayout.dimension(item.h, spec.minH, spec.maxH, spec.h)
        };
        for (const option of optionSpecs(spec))
            widget[option.key] = Options.value(option, item[option.key]);
        if (Number.isFinite(item.col) && Number.isFinite(item.row)) {
            widget.col = item.col;
            widget.row = item.row;
        }
        return widget;
    });
}
