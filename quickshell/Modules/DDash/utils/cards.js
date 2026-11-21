function stored() {
    return DashRegistry.placed.slice();
}

function newCard(id, w, h) {
    const card = {
        "id": id,
        "w": w,
        "h": h
    };
    const spec = DashRegistry.entry(id)?.card;
    if (spec?.settingsPage || (spec?.allowMultiple && DashRegistry.placed.some(c => c.id === id)))
        card.instanceId = DashRegistry.newInstanceId();
    return card;
}

function addCard(id, w, h) {
    const cards = stored();
    cards.push(newCard(id, w, h));
    SettingsData.set("dashCards", cards);
}

function removeCard(index) {
    const cards = stored();
    if (index < 0 || index >= cards.length)
        return;
    cards.splice(index, 1);
    SettingsData.set("dashCards", cards);
}

function setLayout(cards) {
    SettingsData.set("dashCards", cards);
}

function clearAll() {
    SettingsData.set("dashCards", []);
}

function resetToDefault() {
    SettingsData.resetDashCards();
}
