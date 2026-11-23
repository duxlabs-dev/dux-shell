.pragma library

function findLockWorkspaceTarget(savedState, workspaces, isOccupied) {
    const savedRecord = savedState.workspaceRecord;
    for (const record of workspaces) {
        if (compareWorkspaceRecords(savedRecord, record) === false && isOccupied(record) === false) {
            return record;
        }
    }
    return null;
}

function compareWorkspaceRecords(a, b) {
    if (a === null || b === null) {
        return false;
    }
    const stableFields = ["id", "idx", "name", "num", "special"];
    for (const field of stableFields) {
        if (a[field] !== b[field]) {
            return false;
        }
    }
    return true;
}

function isReservedWorkspaceTarget(record, reservedTargets) {
    for (const target of reservedTargets || []) {
        if (compareWorkspaceRecords(record, target))
            return true;
    }
    return false;
}

function nextHyprlandLockWorkspaceId(workspaces, savedId, reservedIds) {
    const used = new Set();
    for (const workspace of workspaces || []) {
        if (!workspace)
            continue;
        if (_positiveInteger(workspace.id))
            used.add(workspace.id);
        if (_positiveInteger(workspace.idx))
            used.add(workspace.idx);
    }
    if (_positiveInteger(savedId))
        used.add(savedId);
    for (const id of reservedIds || []) {
        if (_positiveInteger(id))
            used.add(id);
    }
    let candidate = 1;
    while (used.has(candidate))
        candidate += 1;
    return candidate;
}

function nextI3LockWorkspaceName(reservedNames) {
    const names = new Set(reservedNames || []);
    let candidate = "dms-lock-temp";
    let suffix = 2;
    while (names.has(candidate)) {
        candidate = `dms-lock-temp-${suffix}`;
        suffix += 1;
    }
    return candidate;
}

function _positiveInteger(value) {
    return typeof value === "number" && value > 0 && value === Math.floor(value);
}
