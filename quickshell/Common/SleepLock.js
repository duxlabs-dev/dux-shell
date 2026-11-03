.pragma library

function shouldWaitForLock(lockBeforeSuspend, alreadySecure) {
    return !!lockBeforeSuspend && !alreadySecure;
}
