package distros

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
)

const (
	obsRepoDebian13       = "Debian_13"
	obsRepoDebianTesting  = "Debian_Testing"
	obsRepoDebianUnstable = "Debian_Unstable"

	aptSourcesGlob = "/etc/apt/sources.list.d/*"
	aptSourcesList = "/etc/apt/sources.list"
)

func debianOBSRepoVersion(info *OSInfo, aptSuites []string) string {
	hasSuite := make(map[string]bool, len(aptSuites))
	for _, suite := range aptSuites {
		hasSuite[normalizeDebianSuite(suite)] = true
	}

	// APT suites distinguish testing from sid. os-release cannot: both currently
	// report VERSION_CODENAME=forky and PRETTY_NAME="Debian GNU/Linux forky/sid"
	if hasSuite["sid"] || hasSuite["unstable"] {
		return obsRepoDebianUnstable
	}
	if hasSuite["testing"] || hasSuite["forky"] {
		return obsRepoDebianTesting
	}
	if hasSuite["trixie"] || hasSuite["stable"] {
		return obsRepoDebian13
	}

	if info == nil {
		return obsRepoDebian13
	}

	id := strings.ToLower(strings.TrimSpace(info.VersionID))
	code := strings.ToLower(strings.TrimSpace(info.VersionCodename))

	if code == "sid" || id == "sid" {
		return obsRepoDebianUnstable
	}
	if id == "13" || code == "trixie" {
		return obsRepoDebian13
	}
	if id != "" && id != "testing" {
		return obsRepoDebian13
	}
	// Prefer Testing when os-release is the shared forky/sid string. Unstable
	// OBS packages can require a newer glibc than Testing ships.
	return obsRepoDebianTesting
}

type aptSource struct {
	path, uri, signedBy string
	// Enabled binary entry; deb-src and disabled entries still own their file and keyring.
	active bool
}

// Docs and older installers named the files differently, so sources match on the URI.
func readAPTSources() []aptSource {
	var sources []aptSource
	if content, err := repoReadFile(aptSourcesList); err == nil {
		sources = parseAPTSources(aptSourcesList, string(content))
	}
	for _, path := range repoGlob(aptSourcesGlob) {
		if !strings.HasSuffix(path, ".list") && !strings.HasSuffix(path, ".sources") {
			continue
		}
		content, err := repoReadFile(path)
		if err != nil {
			continue
		}
		sources = append(sources, parseAPTSources(path, string(content))...)
	}
	return sources
}

func parseAPTSources(path, content string) []aptSource {
	if strings.HasSuffix(path, ".sources") {
		return parseDeb822Sources(path, content)
	}
	var sources []aptSource
	for line := range strings.Lines(content) {
		kind, rest, _ := strings.Cut(strings.TrimSpace(line), " ")
		if kind != "deb" && kind != "deb-src" {
			continue
		}
		source := aptSource{path: path, active: kind == "deb"}
		if options, ok := strings.CutPrefix(strings.TrimSpace(rest), "["); ok {
			options, rest, ok = strings.Cut(options, "]")
			if !ok {
				continue
			}
			for _, option := range strings.Fields(options) {
				if value, ok := strings.CutPrefix(option, "signed-by="); ok {
					source.signedBy = value
				}
			}
		}
		if fields := strings.Fields(rest); len(fields) > 0 {
			source.uri = fields[0]
			sources = append(sources, source)
		}
	}
	return sources
}

func parseDeb822Sources(path, content string) []aptSource {
	var sources []aptSource
	fields := map[string]string{}
	var last string
	flush := func() {
		types := strings.Fields(fields["types"])
		if slices.Contains(types, "deb") || slices.Contains(types, "deb-src") {
			// Signed-By may also hold an inline key block, which no file removal can follow.
			signedBy, _, _ := strings.Cut(fields["signed-by"], " ")
			if !strings.HasPrefix(signedBy, "/") {
				signedBy = ""
			}
			active := slices.Contains(types, "deb") && !strings.EqualFold(fields["enabled"], "no")
			for _, uri := range strings.Fields(fields["uris"]) {
				sources = append(sources, aptSource{path, uri, signedBy, active})
			}
		}
		clear(fields)
		last = ""
	}
	for line := range strings.Lines(content) {
		trimmed := strings.TrimSpace(line)
		switch {
		case trimmed == "":
			flush()
		case strings.HasPrefix(trimmed, "#"):
		case line[0] == ' ' || line[0] == '\t':
			if last != "" {
				fields[last] += " " + trimmed
			}
		default:
			if key, value, ok := strings.Cut(trimmed, ":"); ok {
				last = strings.ToLower(strings.TrimSpace(key))
				fields[last] = strings.TrimSpace(value)
			}
		}
	}
	flush()
	return sources
}

func isLegacyOBSURI(uri string) bool {
	return slices.ContainsFunc(dmsProjects, func(project string) bool {
		return obsURLMatches(uri, legacyObsRepo(legacyProject(project)))
	})
}

// Removal deletes whole files, so a file that also carries other sources never counts as legacy.
func legacyAPTFiles(sources []aptSource) map[string]bool {
	files := map[string]bool{}
	for _, source := range sources {
		legacy, seen := files[source.path]
		files[source.path] = (legacy || !seen) && isLegacyOBSURI(source.uri) && source.path != aptSourcesList
	}
	return files
}

func debianOBSMoves(sources []aptSource) []RepoMove {
	legacyFiles := legacyAPTFiles(sources)
	var moves []RepoMove
	for _, project := range dmsProjects {
		move := RepoMove{Kind: RepoTypeOBS, Old: legacyObsRepo(legacyProject(project)), New: newObsRepo(project)}
		move.OldPath, move.NewPath = obsAptListFile(move.Old), obsAptListFile(move.New)
		for _, source := range sources {
			switch {
			case !source.active:
			case !move.OldPresent && legacyFiles[source.path] && obsURLMatches(source.uri, move.Old):
				move.OldPath, move.OldPresent = source.path, true
			case !move.NewPresent && obsURLMatches(source.uri, move.New):
				move.NewPath, move.NewPresent = source.path, true
			}
		}
		moves = append(moves, move)
	}
	return moves
}

func debianRemovals(moves []RepoMove, sources []aptSource) [][]string {
	legacyFiles := legacyAPTFiles(sources)
	removes := repoMoveRemoves(moves)
	// Every legacy file goes, not just the one a move reports: docs and installers each wrote their own.
	var files []string
	for _, source := range sources {
		if !source.active || !legacyFiles[source.path] || slices.Contains(files, source.path) {
			continue
		}
		if slices.ContainsFunc(removes, func(move RepoMove) bool { return obsURLMatches(source.uri, move.Old) }) {
			files = append(files, source.path)
		}
	}
	var removals [][]string
	for _, file := range files {
		paths := []string{file}
		for _, source := range sources {
			if source.path != file || source.signedBy == "" || slices.Contains(paths, source.signedBy) {
				continue
			}
			kept := slices.ContainsFunc(sources, func(other aptSource) bool {
				return other.signedBy == source.signedBy && !slices.Contains(files, other.path)
			})
			if !kept {
				paths = append(paths, source.signedBy)
			}
		}
		removals = append(removals, paths)
	}
	return removals
}

func aptSourcesPointAt(sources []aptSource, repo, dist string) bool {
	return slices.ContainsFunc(sources, func(source aptSource) bool {
		return source.active && obsURLMatches(source.uri, repo) && strings.HasSuffix(strings.TrimSuffix(source.uri, "/"), "/"+dist)
	})
}

func readDebianAPTSuites() []string {
	var chunks []string
	if data, err := os.ReadFile("/etc/apt/sources.list"); err == nil {
		chunks = append(chunks, string(data))
	}
	matches, _ := filepath.Glob("/etc/apt/sources.list.d/*")
	for _, path := range matches {
		if !strings.HasSuffix(path, ".list") && !strings.HasSuffix(path, ".sources") {
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		chunks = append(chunks, string(data))
	}
	return debianAPTSuites(strings.Join(chunks, "\n"))
}

func debianAPTSuites(sources string) []string {
	seen := make(map[string]bool)
	var suites []string
	add := func(raw string) {
		suite := normalizeDebianSuite(raw)
		if suite == "" || seen[suite] {
			return
		}
		seen[suite] = true
		suites = append(suites, suite)
	}

	var stanza []string
	flushStanza := func() {
		if len(stanza) == 0 {
			return
		}
		enabled := true
		var stanzaSuites []string
		for _, line := range stanza {
			key, val, ok := strings.Cut(line, ":")
			if !ok {
				continue
			}
			switch strings.ToLower(strings.TrimSpace(key)) {
			case "enabled":
				switch strings.ToLower(strings.TrimSpace(val)) {
				case "no", "false", "0":
					enabled = false
				}
			case "suites":
				stanzaSuites = strings.Fields(val)
			}
		}
		if enabled {
			for _, suite := range stanzaSuites {
				add(suite)
			}
		}
		stanza = nil
	}

	for raw := range strings.SplitSeq(sources, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" {
			flushStanza()
			continue
		}
		if strings.HasPrefix(line, "#") {
			continue
		}
		lower := strings.ToLower(line)
		if strings.HasPrefix(lower, "deb ") || strings.HasPrefix(lower, "deb-src ") {
			flushStanza()
			if suite := suiteFromDebLine(line); suite != "" {
				add(suite)
			}
			continue
		}
		stanza = append(stanza, line)
	}
	flushStanza()
	return suites
}

func suiteFromDebLine(line string) string {
	if i := strings.Index(line, "["); i != -1 {
		if j := strings.Index(line, "]"); j > i {
			line = strings.TrimSpace(line[:i] + " " + line[j+1:])
		}
	}
	fields := strings.Fields(line)
	if len(fields) < 3 {
		return ""
	}
	return fields[2]
}

func normalizeDebianSuite(suite string) string {
	suite = strings.ToLower(strings.TrimSpace(suite))
	suite = strings.Trim(suite, "/")
	for _, suffix := range []string{"-security", "-updates", "-backports", "-proposed-updates"} {
		if before, ok := strings.CutSuffix(suite, suffix); ok {
			return before
		}
	}
	return suite
}
