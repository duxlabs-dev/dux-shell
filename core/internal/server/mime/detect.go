package mime

import (
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-go/paths"
)

const noGlobs = "__NOGLOBS__"

type globRule struct {
	weight        int
	mimeType      string
	pattern       string
	caseSensitive bool
}

func (r globRule) literal() bool {
	return !strings.ContainsAny(r.pattern, "*?[")
}

func (r globRule) matches(name string) bool {
	pattern, candidate := r.pattern, name
	if !r.caseSensitive {
		pattern, candidate = strings.ToLower(pattern), strings.ToLower(name)
	}
	if r.literal() {
		return pattern == candidate
	}
	ok, err := path.Match(pattern, candidate)
	return err == nil && ok
}

func (r globRule) outranks(other globRule) bool {
	if r.literal() != other.literal() {
		return r.literal()
	}
	if r.weight != other.weight {
		return r.weight > other.weight
	}
	return len(r.pattern) > len(other.pattern)
}

func mimeDataDirs() []string {
	dirs := []string{filepath.Join(paths.XDGDataHome(), "mime")}
	env := os.Getenv("XDG_DATA_DIRS")
	if env == "" {
		env = "/usr/local/share:/usr/share"
	}
	for d := range strings.SplitSeq(env, ":") {
		d = strings.TrimSpace(d)
		if d == "" {
			continue
		}
		dirs = append(dirs, filepath.Join(d, "mime"))
	}
	return dirs
}

func parseGlobLine(line string) (globRule, bool) {
	line = strings.TrimSpace(line)
	if line == "" || line[0] == '#' {
		return globRule{}, false
	}
	fields := strings.SplitN(line, ":", 4)
	if len(fields) < 3 || fields[1] == "" || fields[2] == "" {
		return globRule{}, false
	}
	weight, err := strconv.Atoi(fields[0])
	if err != nil {
		return globRule{}, false
	}
	return globRule{
		weight:        weight,
		mimeType:      fields[1],
		pattern:       fields[2],
		caseSensitive: len(fields) == 4 && fields[3] == "cs",
	}, true
}

func loadGlobRules() []globRule {
	var rules []globRule
	cleared := map[string]bool{}
	for _, dir := range mimeDataDirs() {
		data, err := os.ReadFile(filepath.Join(dir, "globs2"))
		if err != nil {
			continue
		}
		clearedHere := map[string]bool{}
		for line := range strings.Lines(string(data)) {
			rule, ok := parseGlobLine(line)
			if !ok || cleared[rule.mimeType] {
				continue
			}
			if rule.pattern == noGlobs {
				clearedHere[rule.mimeType] = true
				continue
			}
			rules = append(rules, rule)
		}
		for mimeType := range clearedHere {
			cleared[mimeType] = true
		}
	}
	return rules
}

func mimeTypeForName(name string, rules []globRule) string {
	var best *globRule
	for i := range rules {
		rule := &rules[i]
		if !rule.matches(name) {
			continue
		}
		if best == nil || rule.outranks(*best) {
			best = rule
		}
	}
	if best == nil {
		return ""
	}
	return best.mimeType
}

func MimeTypeForPath(filePath string) string {
	if info, err := os.Stat(filePath); err == nil && info.IsDir() {
		return "inode/directory"
	}
	return mimeTypeForName(filepath.Base(filePath), loadGlobRules())
}
