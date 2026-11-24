import { readFileSync } from "node:fs";
import vm from "node:vm";

export function loadScript(url) {
    const context = vm.createContext({ console: { info() {}, warn() {} } });
    const source = readFileSync(url, "utf8").replace(/^\s*\.import "([^"]+)" as (\w+)\s*$/gm, (_, path, name) => {
        context[name] = loadScript(new URL(path, url));
        return "";
    }).replace(/^\.pragma.*$/gm, "");
    const bindings = Array.from(source.matchAll(/^(?:const|let|class)\s+(\w+)/gm), match => match[1]);
    vm.runInContext(source + "\nObject.assign(globalThis, {" + bindings.join(",") + "});", context);
    return context;
}
