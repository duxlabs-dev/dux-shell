function categoryOf(widget) {
    return widget?.category ?? "plugins";
}

function filterWidgets(widgets, query, categoryId) {
    const needle = (query ?? "").trim().toLowerCase();
    const scoped = !categoryId || categoryId === "all" ? widgets : widgets.filter(widget => categoryOf(widget) === categoryId);
    if (!needle)
        return scoped;
    return scoped.filter(widget => [widget.text, widget.description, widget.id].some(value => (value || "").toLowerCase().includes(needle)));
}

function shownCategories(categoryDefs, widgets) {
    return categoryDefs.filter(category => widgets.some(widget => categoryOf(widget) === category.id));
}
