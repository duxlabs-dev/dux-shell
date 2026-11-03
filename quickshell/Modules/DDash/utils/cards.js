function stored() {
    return DashRegistry.placed.slice();
}

function addCard(id, w, h) {
    const cards = stored();
    cards.push({
        "id": id,
        "w": w,
        "h": h
    });
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
