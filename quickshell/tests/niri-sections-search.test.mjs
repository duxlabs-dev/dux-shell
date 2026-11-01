import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const sectionsDir = new URL("../Common/niri/sections/", import.meta.url);
const sections = readdirSync(sectionsDir).filter(name => name.endsWith(".js")).map(name => ({ name, module: loadScript(new URL(name, sectionsDir)) }));
const entries = sections.flatMap(({ name, module }) => Array.from(module.search || [], entry => ({ name, entry })));

// Localized matching goes through the translated title, so keywords stay English.
const nonEnglish = new Set(["clavier", "azerty", "souris", "gaucher", "curseur", "masquer", "espace", "espaces", "alimentation", "bouton", "marche", "supprimer", "fermer", "raccourci", "vitesse", "taille", "colonne", "centrer", "milieu", "lanceur", "coin", "ombre", "flou", "verre", "anneau", "bordure", "couleur", "largeur", "glisser", "bord", "jamais", "demander", "confirmer", "tout", "rapide", "rebond", "ralenti", "lent", "ressort", "courbe", "amorti", "touche", "anciennes", "langue", "disposition", "changer", "variante", "fichier", "num\u00e9rique", "pav\u00e9", "clic", "taper", "verrou", "frappe", "externe", "molette", "inactif", "partage", "liste", "choisir", "flottante", "environnement", "restaurer", "connexion", "programmes", "renommer", "ordre", "regrouper", "appli", "onglets", "barre", "titre", "vue", "ensemble", "quitter", "reste", "remplir", "afficher", "vignettes", "seule"]);

test("section search words are English only", () => {
    for (const { name, entry } of entries) {
        for (const word of entry.words || []) {
            assert.ok(/^[\x20-\x7e]+$/.test(word), `${name} ${entry.key}: ${word}`);
            for (const part of word.toLowerCase().split(/[^a-z]+/))
                assert.ok(!nonEnglish.has(part), `${name} ${entry.key}: ${word}`);
        }
    }
});

function qmlFiles(dir) {
    return readdirSync(dir, { recursive: true }).filter(path => path.endsWith(".qml")).map(path => new URL(path, dir));
}

test("every section search title is an extractable I18n.tr literal", () => {
    const literals = new Set();
    for (const file of qmlFiles(new URL("../", import.meta.url))) {
        for (const match of readFileSync(file, "utf8").matchAll(/I18n\.tr\(\s*"((?:\\.|[^"\\])*)"/g))
            literals.add(match[1].replace(/\\(.)/g, "$1"));
    }
    for (const { name, entry } of entries)
        assert.ok(literals.has(entry.title), `${name} ${entry.key}: ${entry.title}`);
});
