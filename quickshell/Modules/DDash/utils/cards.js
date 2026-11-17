function stored() {
    return DashRegistry.placed.slice();
}

function addCard(id, w, h) {
    const cards = stored();
    const card = {
        "id": id,
        "w": w,
        "h": h
    };
    if (DashRegistry.entry(id)?.card?.allowMultiple && cards.some(c => c.id === id))
        card.instanceId = Date.now().toString(36) + Math.random().toString(36).substring(2);
    cards.push(card);
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
