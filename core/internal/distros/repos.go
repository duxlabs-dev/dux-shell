package distros

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
	"github.com/duxlabs-dev/dux-shell/core/internal/site"
)

const (
	coprOwner = "duxlabs"
	obsHome   = "home:duxlabs"
	ppaOwner  = "duxlabs"

	legacyCoprOwner = "avengemedia"
	legacyObsHome   = "home:AvengeMedia"
	legacyPpaOwner  = "avengemedia"

	projectDMS        = "dms"
	projectDMSGit     = "dms-git"
	projectDeps       = "dux-repo"
	legacyProjectDeps = "danklinux"
	// The 2.0 docs told users to enable duxlabs/dux before the deps slug became dux-repo.
	retiredProjectDeps = "dux"

	voidHost       = site.VoidRepo
	legacyVoidHost = "https://void.danklinux.com"
	voidConfGlob   = "/etc/xbps.d/*.conf"
)

// The duxlabs OBS projects are not published yet, so Debian and openSUSE stay on the legacy ones.
const obsMigrationReady = false

var dmsProjects = []string{projectDMS, projectDMSGit, projectDeps}

func legacyProject(project string) string {
	if project == projectDeps {
		return legacyProjectDeps
	}
	return project
}

func coprRepo(project string) string       { return coprOwner + "/" + project }
func legacyCoprRepo(project string) string { return legacyCoprOwner + "/" + project }
func ppaRepo(project string) string        { return "ppa:" + ppaOwner + "/" + project }
func legacyPpaRepo(project string) string  { return "ppa:" + legacyPpaOwner + "/" + project }
func legacyObsRepo(project string) string  { return legacyObsHome + ":" + project }
func newObsRepo(project string) string     { return obsHome + ":" + project }

// obsRepo is what the mappings install from; the move tables use newObsRepo regardless of the gate.
func obsRepo(project string) string {
	if !obsMigrationReady {
		return legacyObsRepo(legacyProject(project))
	}
	return newObsRepo(project)
}

var (
	coprDMS, coprDMSGit, coprDeps = coprRepo(projectDMS), coprRepo(projectDMSGit), coprRepo(projectDeps)
	obsDMS, obsDMSGit, obsDeps    = obsRepo(projectDMS), obsRepo(projectDMSGit), obsRepo(projectDeps)
	ppaDMS, ppaDMSGit, ppaDeps    = ppaRepo(projectDMS), ppaRepo(projectDMSGit), ppaRepo(projectDeps)
)

// Each must match what the package manager itself derives from the RepoURL.
func coprRepoID(repo string) string {
	return "copr:copr.fedorainfracloud.org:" + strings.ReplaceAll(repo, "/", ":")
}
func coprRepoFile(repo string) string { return "/etc/yum.repos.d/_" + coprRepoID(repo) + ".repo" }
func obsAptName(repo string) string   { return strings.ReplaceAll(repo, ":", "-") }
func obsAptListFile(repo string) string {
	return "/etc/apt/sources.list.d/" + obsAptName(repo) + ".list"
}
func obsAptKeyring(repo string) string  { return "/etc/apt/keyrings/" + obsAptName(repo) + ".gpg" }
func obsZypperAlias(repo string) string { return strings.ReplaceAll(repo, ":", "_") }
func obsZypperRepoFile(repo string) string {
	return "/etc/zypp/repos.d/" + obsZypperAlias(repo) + ".repo"
}
func obsBaseURL(repo, dist string) string {
	return "https://download.opensuse.org/repositories/" + strings.ReplaceAll(repo, ":", ":/") + "/" + dist
}

// add-apt-repository names the file <owner>-ubuntu-<project>-<series>.sources (24.04+) or .list.
func ppaSourcesGlobs(repo string) []string {
	owner, project, _ := strings.Cut(strings.TrimPrefix(repo, "ppa:"), "/")
	stem := "/etc/apt/sources.list.d/" + owner + "-ubuntu-" + project + "-*"
	return []string{stem + ".sources", stem + ".list"}
}

// A current COPR mapping may still be installed from its legacy owner.
func coprAliases(repo string) []string {
	owner, project, _ := strings.Cut(repo, "/")
	if owner != coprOwner {
		return []string{repo}
	}
	return []string{repo, legacyCoprRepo(legacyProject(project))}
}

func coprRepoIDs(repo string) []string {
	var ids []string
	for _, alias := range coprAliases(repo) {
		ids = append(ids, coprRepoID(alias))
	}
	return ids
}

func coprFromRepoMatches(fromRepo, repo string) bool {
	return slices.Contains(coprRepoIDs(repo), strings.TrimSpace(fromRepo))
}

// Test seams.
var (
	repoGlob = func(pattern string) []string {
		matches, _ := filepath.Glob(pattern)
		return matches
	}
	repoPathExists = func(pattern string) bool { return len(repoGlob(pattern)) > 0 }
	repoReadFile   = os.ReadFile
	privescExec    = privesc.ExecCommand
)

// The series is one word, so the retired dux-* glob must not count the dux-repo-* sibling.
func ppaSourcesExists(pattern string) bool {
	return slices.ContainsFunc(repoGlob(pattern), func(path string) bool { return ppaSeriesMatch(pattern, path) })
}

func ppaSeriesMatch(pattern, path string) bool {
	stem, ext, _ := strings.Cut(pattern, "*")
	series := strings.TrimSuffix(strings.TrimPrefix(path, stem), ext)
	return series != "" && !strings.Contains(series, "-")
}

type RepoMove struct {
	Kind                   RepositoryType
	Old, New               string // RepoURL form, e.g. "avengemedia/danklinux" → "duxlabs/dux-repo"
	OldPath, NewPath       string // file (or glob) whose presence means the repo is enabled
	OldPresent, NewPresent bool
}

type RepoMover interface {
	RepoMoves() []RepoMove
	ApplyRepoMoves(ctx context.Context, moves []RepoMove, sudoPassword string, progressChan chan<- InstallProgressMsg) error
	RepoMoveCommands(moves []RepoMove) []string
}

// For image-based hosts, where the package manager cannot run the moves.
type ImageRepoMover interface {
	ImageRepoMoveCommands(moves []RepoMove) []string
}

func PlanRepoMoves(d Distribution) ([]RepoMove, bool) {
	mover, ok := d.(RepoMover)
	if !ok {
		return nil, false
	}
	moves := mover.RepoMoves()
	return moves, len(moves) > 0
}

type repoChannel struct {
	kind             RepositoryType
	repo, legacyRepo func(project string) string
	paths            func(repo string) []string
	retiredDeps      bool // the channel also published the deps project under retiredProjectDeps
}

func (c repoChannel) legacyRepos(project string) []string {
	repos := []string{c.legacyRepo(legacyProject(project))}
	if project == projectDeps && c.retiredDeps {
		repos = append(repos, c.repo(retiredProjectDeps))
	}
	return repos
}

func (c repoChannel) moves(exists func(string) bool) []RepoMove {
	var moves []RepoMove
	for _, project := range dmsProjects {
		for _, old := range c.legacyRepos(project) {
			move := RepoMove{Kind: c.kind, Old: old, New: c.repo(project)}
			move.OldPath, move.OldPresent = firstExisting(exists, c.paths(move.Old))
			move.NewPath, move.NewPresent = firstExisting(exists, c.paths(move.New))
			moves = append(moves, move)
		}
	}
	return moves
}

func firstExisting(exists func(string) bool, paths []string) (string, bool) {
	for _, path := range paths {
		if exists(path) {
			return path, true
		}
	}
	return paths[0], false
}

var (
	coprChannel      = repoChannel{RepoTypeCOPR, coprRepo, legacyCoprRepo, func(r string) []string { return []string{coprRepoFile(r)} }, true}
	obsAptChannel    = repoChannel{RepoTypeOBS, newObsRepo, legacyObsRepo, func(r string) []string { return []string{obsAptListFile(r)} }, false}
	obsZypperChannel = repoChannel{RepoTypeOBS, newObsRepo, legacyObsRepo, func(r string) []string { return []string{obsZypperRepoFile(r)} }, false}
	ppaChannel       = repoChannel{RepoTypePPA, ppaRepo, legacyPpaRepo, ppaSourcesGlobs, true}
)

func (m RepoMove) needsAdd() bool    { return m.OldPresent && !m.NewPresent }
func (m RepoMove) needsRemove() bool { return m.OldPresent }

// The enable*Repos helpers only read RepoURL; two legacy rows can share a target.
func repoMoveAdds(moves []RepoMove) []PackageMapping {
	var adds []PackageMapping
	seen := map[string]bool{}
	for _, move := range moves {
		if !move.needsAdd() || seen[move.New] {
			continue
		}
		seen[move.New] = true
		adds = append(adds, PackageMapping{Repository: move.Kind, RepoURL: move.New})
	}
	return adds
}

func repoMoveRemoves(moves []RepoMove) []RepoMove {
	var removes []RepoMove
	for _, move := range moves {
		if move.needsRemove() {
			removes = append(removes, move)
		}
	}
	return removes
}

func (b *BaseDistribution) aptUpdate(ctx context.Context, sudoPassword string, progressChan chan<- InstallProgressMsg) error {
	progressChan <- InstallProgressMsg{
		Phase:       PhaseSystemPackages,
		Progress:    0.36,
		Step:        "Updating package lists...",
		NeedsSudo:   true,
		CommandInfo: "sudo apt-get update",
	}
	if err := b.runWithProgress(privescExec(ctx, sudoPassword, "apt-get update"), progressChan, PhaseSystemPackages, 0.36, 0.40); err != nil {
		return fmt.Errorf("failed to update package lists: %w", err)
	}
	return nil
}

func LegacyRepoPaths(moves []RepoMove) []string {
	paths := []string{}
	for _, move := range repoMoveRemoves(moves) {
		if !slices.Contains(paths, move.OldPath) {
			paths = append(paths, move.OldPath)
		}
	}
	return paths
}
