.pragma library

// Extra pick-search words per action id, beyond its label words. niri has no native
// close-workspace action: the DMS workspace closeAll IPC closes the active workspace
// with its windows, so it carries the delete words.
var ACTION_WORDS = {
    "spawn dms ipc call workspace closeAll": ["delete", "del", "suppr", "supprimer", "effacer", "fermer", "fermeture", "espace", "espaces"]
};

function actionSearchWords(actionId) {
    return Array.from(ACTION_WORDS[String(actionId || "")] || []);
}
