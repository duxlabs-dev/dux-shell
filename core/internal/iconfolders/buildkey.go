package iconfolders

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// buildKeyVersion changes whenever ownKey's inputs change, so no earlier key can match.
const buildKeyVersion = 1

var (
	fingerprintHex = regexp.MustCompile(`^[0-9a-f]{64}$`)
	// The last line of a build's summary, from a pack that fingerprints.
	builtFingerprint = regexp.MustCompile(`(?m)^ *fingerprint: ([0-9a-f]{64})$`)
)

// executableState covers DMS itself: its tile, seed and cut-out code decides content as much as the pack does.
var executableState = sync.OnceValue(func() string {
	path, err := os.Executable()
	if err != nil {
		return ""
	}
	return path + "\x00" + fileState(path)
})

func fileState(path string) string {
	info, err := os.Stat(path)
	if err != nil {
		return "-"
	}
	return strconv.FormatInt(info.Size(), 10) + ":" + strconv.FormatInt(info.ModTime().UnixNano(), 10)
}

// ownKey digests what DMS decides of the self-built pack: the options, the colors, DMS and the generator file.
// The pack's State.Key is ownKey, "-" and its fingerprint of the code, apps and icons it reads; a pack that
// reports none leaves the key empty, so it is always built.
func (o *Options) ownKey(generator string) string {
	colors, err := os.ReadFile(filepath.Join(o.StateDir, "dms-colors.json"))
	if err != nil {
		return ""
	}
	// Every exported field, so a field added later is covered without a change here.
	opts, err := json.Marshal(o)
	if err != nil {
		return ""
	}
	sum := sha256.New()
	for _, part := range []string{strconv.Itoa(buildKeyVersion), executableState(), generator, fileState(generator), string(opts), string(colors)} {
		fmt.Fprintf(sum, "%d\x00%s", len(part), part)
	}
	return hex.EncodeToString(sum.Sum(nil)[:16])
}

// builtKey is the key of a build that took own and reported fingerprint, or "" when either is missing.
func builtKey(own, fingerprint string) string {
	if own == "" || !fingerprintHex.MatchString(fingerprint) {
		return ""
	}
	return own + "-" + fingerprint
}

// unchangedSince reports whether prev was built from today's inputs and is still in place. Only a pack
// that reports a fingerprint is asked for one, so an older pack never is.
func (o *Options) unchangedSince(prev State, own, generator string) bool {
	if own == "" || !strings.HasPrefix(prev.Key, own+"-") || !o.unchanged(prev) {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), probeTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, generator, "--fingerprint")
	cmd.WaitDelay = time.Second
	output, err := cmd.Output()
	return err == nil && prev.Key == builtKey(own, string(bytes.TrimSpace(output)))
}

// unchanged reports whether prev is the self-built pack in this icons dir, still there as it was committed.
func (o *Options) unchanged(prev State) bool {
	return prev.Base == SelfBuilt && prev.Applied != "" && prev.Dir == filepath.Join(o.IconsDir, prev.Applied) &&
		isGenerated(prev.Dir) && hasBare(prev.Dir) == prev.Bare
}

// reportedFingerprint is the fingerprint a build printed, or "".
func reportedFingerprint(output []byte) string {
	if m := builtFingerprint.FindSubmatch(output); m != nil {
		return string(m[1])
	}
	return ""
}
