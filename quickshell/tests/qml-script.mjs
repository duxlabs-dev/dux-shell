import { readFileSync } from "node:fs";
import vm from "node:vm";

// QML exposes a script's top-level const, let and class declarations through its
// import qualifier just like var and function ones; a vm context only puts the latter
// on the context object, so the lexical ones are copied over after the script ran.
const lexicalDeclaration = /^(?:const|let|class)\s+([A-Za-z_$][\w$]*)/gm;

export function loadScript(url) {
    const context = vm.createContext({ console: { info() {}, warn() {} } });
    const source = readFileSync(url, "utf8").replace(/^\s*\.import "([^"]+)" as (\w+)\s*$/gm, (_, path, name) => {
        context[name] = loadScript(new URL(path, url));
        return "";
    }).replace(/^\.pragma.*$/gm, "");
    vm.runInContext(source, context);
    for (const [, name] of source.matchAll(lexicalDeclaration)) {
        if (!(name in context))
            context[name] = vm.runInContext(name, context);
    }
    return context;
}
