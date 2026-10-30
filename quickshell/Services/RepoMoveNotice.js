.pragma library

// Full version on purpose: every release re-arms the notice once.
function repoNoticeDue(legacy, seenVersion, currentVersion) {
    return (legacy?.length ?? 0) > 0 && currentVersion !== "" && seenVersion !== currentVersion;
}
