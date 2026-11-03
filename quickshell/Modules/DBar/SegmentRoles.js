.pragma library

function breaksRun(entry, state) {
    if (state === false)
        return true;
    const id = entry?.widgetId ?? "";
    return id === "spacer" || id === "separator";
}

function resolve(entries, participating) {
    const count = entries?.length ?? 0;
    const roles = new Array(count).fill("solo");
    let run = [];
    const close = () => {
        if (run.length > 1) {
            roles[run[0]] = "first";
            roles[run[run.length - 1]] = "last";
            for (let i = 1; i < run.length - 1; i++)
                roles[run[i]] = "middle";
        }
        run = [];
    };
    for (let i = 0; i < count; i++) {
        const state = participating?.[i];
        if (state === null || state === undefined)
            continue;
        if (breaksRun(entries[i], state)) {
            close();
            continue;
        }
        run.push(i);
    }
    close();
    return roles;
}
