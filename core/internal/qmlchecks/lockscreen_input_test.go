package qmlchecks

import (
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

func TestLockScreenPasswordFieldBypassesTextInputIME(t *testing.T) {
	data, err := os.ReadFile("../../../quickshell/Modules/Lock/Widgets/LockAuthWidget.qml")
	if err != nil {
		t.Fatalf("read lock screen QML: %v", err)
	}

	content := string(data)
	textInputPasswordField := regexp.MustCompile(`(?s)TextInput\s*\{[^{}]*id:\s*passwordField`)
	if textInputPasswordField.MatchString(content) {
		t.Fatalf("passwordField must not be a TextInput because TextInput can route physical keyboard input through IME")
	}

	if !strings.Contains(content, "Keys.onPressed") || !strings.Contains(content, "event.text") {
		t.Fatalf("passwordField should handle physical key text manually instead of relying on a text input control")
	}

	// Wayland IMEs commit unconsumed printable keys as text-input text rather
	// than forwarding raw keys, so the lock screen needs an IME commit sink
	// alongside raw key handling.
	if !strings.Contains(content, "id: imeCommitSink") {
		t.Fatalf("passwordField must keep the imeCommitSink TextInput so IME-routed keyboards can type (#2950)")
	}
	if !strings.Contains(content, "Qt.ImhSensitiveData") {
		t.Fatalf("imeCommitSink must advertise hidden-text hints so IMEs treat it as a password field")
	}

	// fcitx5-qt parents its candidate xdg_popup to the focus window, and an
	// ext-session-lock surface cannot parent popups (#3669).
	sinkGate := regexp.MustCompile(`(?s)Loader\s*\{[^{}]*active:\s*KeyUtils\.compositorTextInputSelected\([^{}]*sourceComponent:\s*TextInput\s*\{\s*id:\s*imeCommitSink`)
	if !sinkGate.MatchString(content) {
		t.Fatalf("imeCommitSink must only load when Qt uses its wayland text-input context (#3669)")
	}
}

func TestLockScreenFprintProfileMatchesPamQml(t *testing.T) {
	profile, err := os.ReadFile("../../../quickshell/assets/pam/fprint")
	if err != nil {
		t.Fatalf("read fprint PAM profile: %v", err)
	}

	qml, err := os.ReadFile("../../../quickshell/Modules/Lock/Pam.qml")
	if err != nil {
		t.Fatalf("read lock screen PAM QML: %v", err)
	}

	// Pam.qml tells a pam_fprintd timeout expiry apart from a device fault by
	// how long the session ran, so a profile change that is not mirrored in
	// sessionTimeoutMs makes real faults look like planned renewals.
	profileTimeout := regexp.MustCompile(`pam_fprintd\.so[^\n]*\btimeout=(\d+)`).FindSubmatch(profile)
	if profileTimeout == nil {
		t.Fatalf("fprint profile must set an explicit pam_fprintd timeout")
	}
	qmlTimeout := regexp.MustCompile(`sessionTimeoutMs:\s*(\d+)`).FindSubmatch(qml)
	if qmlTimeout == nil {
		t.Fatalf("Pam.qml must declare sessionTimeoutMs")
	}

	seconds, err := strconv.Atoi(string(profileTimeout[1]))
	if err != nil {
		t.Fatalf("parse profile timeout: %v", err)
	}
	millis, err := strconv.Atoi(string(qmlTimeout[1]))
	if err != nil {
		t.Fatalf("parse sessionTimeoutMs: %v", err)
	}
	if seconds*1000 != millis {
		t.Fatalf("sessionTimeoutMs is %dms but the fprint profile sets timeout=%d", millis, seconds)
	}

	// fprintd 1.94.0 and older ignore this option when it is longer than two
	// digits and silently fall back to 30 seconds.
	if len(profileTimeout[1]) > 2 {
		t.Fatalf("pam_fprintd timeout=%s is too long for fprintd <= 1.94.0, which would ignore it", profileTimeout[1])
	}

	// One finished session must equal one wrong finger, otherwise
	// SettingsData.maxFprintTries silently means a multiple of the scans it names.
	if !regexp.MustCompile(`pam_fprintd\.so[^\n]*\bmax-tries=1\b`).Match(profile) {
		t.Fatalf("fprint profile must use max-tries=1 so the shell counts wrong scans one for one")
	}
}
