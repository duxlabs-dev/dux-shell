package niriconf

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

// withInclude returns config.kdl with an include of dms/name, or nil when it has one.
// Only config.kdl is scanned: an include placed in another file still counts as
// missing, which errs on the safe side.
func withInclude(configDir, name string) ([]byte, error) {
	if !validName(name) {
		return nil, ErrBadName
	}
	data, err := os.ReadFile(filepath.Join(configDir, "config.kdl"))
	if err != nil {
		return nil, err
	}

	want := filepath.Join(configDir, "dms", name)
	for line := range strings.SplitSeq(string(data), "\n") {
		path, ok := includePath(line)
		if !ok {
			continue
		}
		resolved, err := resolveInclude(configDir, path)
		if err == nil && resolved == want {
			return nil, nil
		}
	}

	if len(data) > 0 && data[len(data)-1] != '\n' {
		data = append(data, '\n')
	}
	return append(data, "include optional=true \"dms/"+name+"\"\n"...), nil
}

func includePath(line string) (string, bool) {
	rest, ok := strings.CutPrefix(strings.TrimSpace(line), "include")
	if !ok || rest == "" || (rest[0] != ' ' && rest[0] != '\t') {
		return "", false
	}
	_, quoted, ok := strings.Cut(rest, `"`)
	if !ok {
		return "", false
	}
	path, _, ok := strings.Cut(quoted, `"`)
	return path, ok
}

// resolveInclude turns an include source into a path: ~ expands, a relative path hangs off baseDir.
func resolveInclude(baseDir, source string) (string, error) {
	expanded, err := utils.ExpandPath(source)
	if err != nil {
		return "", err
	}
	if filepath.IsAbs(expanded) {
		return expanded, nil
	}
	return filepath.Join(baseDir, expanded), nil
}
