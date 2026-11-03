import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const fixture = name => readFileSync(new URL(`fixtures/pam/${name}`, import.meta.url), "utf8");
const probe = name => fixture(`fingerprint/${name}.txt`);

const pam = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/PamStack.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), pam);
const arch = fixture("arch-system-auth");
const debian = fixture("debian-common-auth");
const fedora = fixture("fedora-password-auth");
const greetd = fixture("greetd");
const greetdCommented = fixture("greetd-include-commented");
const commentOnly = fixture("comment-only-module");
const tallyNoDeny = fixture("tally-no-deny");
const faillockDeny4 = fixture("faillock-deny4.conf");
const faillockCommented = fixture("faillock-commented.conf");
const faillockEmpty = fixture("faillock-empty.conf");

test("stripComment drops whole-line and trailing comments and trims", () => {
    assert.equal(pam.stripComment("  auth\tsufficient\t\t\tpam_u2f.so cue  # hardware key"), "auth\tsufficient\t\t\tpam_u2f.so cue", "trailing comment cut, surrounding whitespace trimmed");
    assert.equal(pam.stripComment("# deny = 9"), "", "whole-line comment");
    assert.equal(pam.stripComment(null), "", "null line");
});

test("moduleEnabled finds modules on live lines only", () => {
    assert.equal(pam.moduleEnabled(fedora, "pam_fprintd"), true, "pam_fprintd in the Fedora stack");
    assert.equal(pam.moduleEnabled(commentOnly, "pam_fprintd"), false, "pam_fprintd only on a commented line");
    assert.equal(pam.moduleEnabled(commentOnly, "pam_u2f"), false, "pam_u2f only inside a trailing comment");
    assert.equal(pam.moduleEnabled(commentOnly, "pam_unix"), true, "pam_unix on the live part of a line with a trailing comment");
    assert.equal(pam.moduleEnabled(fedora, ""), false, "empty module name");
});

test("includesFile counts include, substack and @include lines", () => {
    assert.equal(pam.includesFile(arch, "system-login"), true, "include in the Arch stack");
    assert.equal(pam.includesFile(fedora, "system-auth"), true, "substack in the Fedora stack");
    assert.equal(pam.includesFile(debian, "common-auth-pc"), true, "@include in the Debian stack");
    assert.equal(pam.includesFile(greetdCommented, "system-auth"), false, "commented include line");
    assert.equal(pam.includesFile("auth required pam_login_access.so", "login"), false, "filename inside a module name on a non-include line");
});

test("stackHasModule reaches included stacks only through live include lines", () => {
    assert.equal(pam.stackHasModule(greetd, [["system-auth", fedora]], "pam_fprintd"), true, "greetd includes system-auth which carries pam_fprintd");
    assert.equal(pam.stackHasModule(greetd, [["system-auth", ""], ["common-auth", debian]], "pam_u2f"), false, "greetd does not include common-auth");
    assert.equal(pam.stackHasModule(greetdCommented, [["system-auth", fedora]], "pam_fprintd"), false, "include line commented out");
    assert.equal(pam.stackHasModule(fedora, [], "pam_fprintd"), true, "module in the primary stack itself");
});

test("usesLockoutPolicy and pamDenyValue read faillock and tally lines", () => {
    assert.equal(pam.usesLockoutPolicy(arch), true, "Arch stack with pam_faillock");
    assert.equal(pam.usesLockoutPolicy(tallyNoDeny), true, "pam_tally2 line");
    assert.equal(pam.usesLockoutPolicy(debian), false, "Debian stack without a lockout module");
    assert.equal(pam.pamDenyValue(arch), 5, "deny=5 on the Arch preauth line");
    assert.equal(pam.pamDenyValue(tallyNoDeny), -1, "lockout module without deny");
    assert.equal(pam.pamDenyValue("auth required pam_unix.so deny=7"), -1, "deny on a non-lockout line");
});

test("faillockDenyValue reads only a live deny line", () => {
    assert.equal(pam.faillockDenyValue(faillockDeny4), 4, "deny = 4");
    assert.equal(pam.faillockDenyValue(faillockCommented), -1, "commented deny");
    assert.equal(pam.faillockDenyValue("deny=6"), 6, "no spaces around =");
    assert.equal(pam.faillockDenyValue("unlock_time = 600"), -1, "other key only");
});

test("attemptLimitHint prefers faillock.conf, then the smallest pam deny, then the default", () => {
    assert.equal(pam.attemptLimitHint([debian, fedora], faillockDeny4), 0, "no lockout module even with a faillock.conf value");
    assert.equal(pam.attemptLimitHint([greetd, arch], faillockDeny4), 4, "faillock.conf wins over deny=5");
    assert.equal(pam.attemptLimitHint([greetd, arch], faillockCommented), 5, "pam deny=5 when faillock.conf is commented");
    assert.equal(pam.attemptLimitHint([arch, "auth required pam_faillock.so deny=2"], ""), 2, "smallest deny across stacks");
    assert.equal(pam.attemptLimitHint([tallyNoDeny], faillockEmpty), pam.FAILLOCK_DEFAULT_DENY, "lockout module without any deny value");
});

test("isLikelyLockoutMessage matches lockout phrases", () => {
    assert.equal(pam.isLikelyLockoutMessage("Account is locked due to 3 failed logins"), true, "account is locked");
    assert.equal(pam.isLikelyLockoutMessage("too many failed attempts"), true, "too many");
    assert.equal(pam.isLikelyLockoutMessage("Maximum number of tries exceeded"), true, "maximum number of");
    assert.equal(pam.isLikelyLockoutMessage("Authentication failure"), false, "plain failure");
});

test("fingerprint output helpers", () => {
    assert.equal(pam.hasEnrolledFingerprintOutput(probe("enrolled-summary")), true, "has fingers enrolled");
    assert.equal(pam.hasEnrolledFingerprintOutput(probe("enrolled-list")), true, "Finger: line");
    assert.equal(pam.hasEnrolledFingerprintOutput(" - #0: right-index-finger"), true, "dash list line");
    assert.equal(pam.hasEnrolledFingerprintOutput(probe("unrelated")), false, "usage text");
    assert.equal(pam.hasMissingFingerprintEnrollmentOutput(probe("no-devices")), false, "no devices is not an enrollment message");
    assert.equal(pam.hasMissingFingerprintReaderOutput(probe("no-devices")), true, "no devices available");
    assert.equal(pam.hasMissingFingerprintReaderOutput(probe("list-devices-failed")), true, "list_devices failed");
});

test("fingerprintProbeState maps every probe sample", () => {
    const cases = [
        [0, probe("enrolled-summary"), true, "ready", "has fingers enrolled"],
        [1, "User brandon has no fingers enrolled", true, "missing_enrollment", "no fingers enrolled"],
        [1, probe("no-devices"), true, "missing_reader", "No devices available"],
        [1, probe("missing-command"), true, "missing_pam_support", "__missing_command__ marker"],
        [127, "", true, "missing_pam_support", "exit 127"],
        [0, probe("unrelated"), true, "missing_enrollment", "exit 0 with unrelated text"],
        [1, probe("unrelated"), false, "missing_pam_support", "exit 1 with unrelated text, pam_fprintd not detected"],
        [1, probe("unrelated"), true, "probe_failed", "exit 1 with unrelated text, pam_fprintd detected"]
    ];
    for (const [exitCode, output, pamFprintDetected, expected, name] of cases)
        assert.equal(pam.fingerprintProbeState(exitCode, output, pamFprintDetected), expected, name);
});
