.pragma library

var customFragment = "niri-custom.kdl";

// niri refuses a block repeated in one file but merges it across includes, so
// the custom text gets its own fragment, included last by the generated one.
function fragments(sections, state, custom) {
    let text = "";
    const seen = new Set();
    for (const section of sections) {
        if (seen.has(section.id))
            continue;
        seen.add(section.id);
        const part = (custom || {})[section.id];
        if (!part || !part.trim())
            continue;
        text += part.endsWith("\n") ? part : part + "\n";
    }
    return {
        "main": assemble(sections, state) + "include optional=true \"" + customFragment + "\"\n",
        "custom": text
    };
}

// niri replaces some blocks whole when an include repeats them, so every
// section writing into the same block must land in one block of the output.
function assemble(sections, state) {
    const root = node();
    for (const section of sections) {
        for (const entry of section.toKdl(state)) {
            let target = root;
            for (const name of entry.block ? entry.block.split(".") : []) {
                if (!target.children.has(name))
                    target.children.set(name, node());
                target = target.children.get(name);
            }
            target.lines.push(...entry.lines);
        }
    }
    return render(root, "");
}

function node() {
    return {
        lines: [],
        children: new Map()
    };
}

function render(n, indent) {
    let out = "";
    for (const line of n.lines)
        out += line.split("\n").map(part => indent + part + "\n").join("");
    for (const [name, child] of n.children) {
        const body = render(child, indent + "    ");
        if (body)
            out += indent + name + " {\n" + body + indent + "}\n";
    }
    return out;
}
