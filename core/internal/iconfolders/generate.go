package iconfolders

import (
	"errors"
	"fmt"
	"iter"
	"maps"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

const generatedKey = "X-DMS-Generated=icon-folders"

// item is one overlay file: contents, or a symlink target when data is nil.
type item struct {
	data []byte
	link string
}

type plan struct {
	scan    *scan
	colored map[fileKey]item
	// Base icons the overlay's names would shadow, carried as they are.
	unchanged map[fileKey]bool
}

// buildPlan decides every overlay file without writing, so probing can use it.
func buildPlan(s *scan, r *recipe, ramp Ramp) (*plan, error) {
	p := &plan{scan: s, colored: map[fileKey]item{}, unchanged: map[fileKey]bool{}}
	hidden := func(file string) bool { return r.hidden != nil && r.hidden(iconName(file)) }
	palette := func(string) bool { return false }
	if r.palette != nil {
		palette = r.palette(s.names)
	}

	recolored := map[fileKey][]byte{}
	shown := map[fileKey]fileKey{}
	for _, dir := range s.dirs {
		if !folderContexts[s.context[dir]] {
			continue
		}
		for name, target := range s.files[dir] {
			if target != "" || !isSVG(name) || !r.source(s.context[dir], iconName(name)) {
				continue
			}
			key := fileKey{dir, name}
			data, err := s.read(key)
			if errors.Is(err, errSkipped) {
				continue
			}
			if err != nil {
				return nil, err
			}
			out, ok := r.recolor(data, ramp)
			if !ok {
				continue
			}
			recolored[key] = out
			if !hidden(name) {
				shown[key] = key
			}
		}
	}
	for _, dir := range s.dirs {
		if !folderContexts[s.context[dir]] {
			continue
		}
		for name, target := range s.files[dir] {
			if target == "" || !isSVG(name) || hidden(name) {
				continue
			}
			key := fileKey{dir, name}
			if final, ok := s.resolve(key); ok && recolored[final] != nil {
				shown[key] = final
			}
		}
	}

	names := map[string]bool{}
	for key := range shown {
		names[iconName(key.name)] = true
	}
	dropShadowing(names, s.names)

	for key, final := range shown {
		if !names[iconName(key.name)] {
			continue
		}
		link, ok := s.linkWithin(key, func(next fileKey) bool {
			_, held := shown[next]
			return held && names[iconName(next.name)]
		})
		if ok {
			p.colored[key] = item{link: link}
			continue
		}
		p.colored[key] = item{data: recolored[final]}
	}
	if len(p.colored) == 0 {
		return p, nil
	}

	for _, dir := range s.dirs {
		for name := range s.files[dir] {
			key := fileKey{dir, name}
			if _, done := p.colored[key]; done {
				continue
			}
			switch icon := iconName(name); {
			case names[icon]:
				// Raster sizes would pin the pack's color, so the recolored art must answer there.
				if !isSVG(name) {
					continue
				}
			case palette(icon) || !shadowed(icon, names):
				continue
			}
			p.unchanged[key] = true
		}
	}
	return p, nil
}

// fallbackNames mirrors GTK's generic fallback, which tries every name in the applied theme first.
func fallbackNames(icon string) []string {
	plain, symbolic := strings.CutSuffix(icon, "-symbolic")
	var names []string
	for name := plain; ; {
		cut := strings.LastIndexByte(name, '-')
		if cut <= 0 {
			break
		}
		name = name[:cut]
		if symbolic {
			names = append(names, name+"-symbolic")
		}
		names = append(names, name)
	}
	if symbolic {
		names = append(names, plain)
	}
	return names
}

func shadowed(icon string, names map[string]bool) bool {
	return slices.ContainsFunc(fallbackNames(icon), func(name string) bool { return names[name] })
}

// dropShadowing drops names that would answer for base icons the overlay lacks; folder names stay.
func dropShadowing(names, base map[string]bool) {
	for changed := true; changed; {
		changed = false
		for icon := range base {
			if names[icon] {
				continue
			}
			for _, name := range fallbackNames(icon) {
				if names[name] && !isFolderName(name) {
					delete(names, name)
					changed = true
				}
			}
		}
	}
}

func (p *plan) dirs(keys iter.Seq[fileKey]) map[string]bool {
	dirs := map[string]bool{}
	for key := range keys {
		dirs[key.dir] = true
	}
	for alias, canonical := range p.scan.alias {
		if dirs[canonical] {
			dirs[alias] = true
		}
	}
	return dirs
}

type tree struct {
	root string
	made map[string]bool
}

func (t *tree) put(key fileKey, it item) error {
	dir := filepath.Join(t.root, key.dir)
	if !t.made[key.dir] {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		t.made[key.dir] = true
	}
	if it.data == nil {
		return os.Symlink(it.link, filepath.Join(dir, key.name))
	}
	return os.WriteFile(filepath.Join(dir, key.name), it.data, 0o644)
}

func (t *tree) linkDirs(alias map[string]string) error {
	for from, to := range alias {
		if !t.made[to] {
			continue
		}
		dst := filepath.Join(t.root, from)
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return err
		}
		target, err := filepath.Rel(path.Dir(from), to)
		if err != nil {
			return err
		}
		if err := os.Symlink(target, dst); err != nil {
			return err
		}
	}
	return nil
}

// write reads the unchanged contents here, not in planning: a probe never needs them.
func (p *plan) write(root string) error {
	t := tree{root: root, made: map[string]bool{}}
	for key, it := range p.colored {
		if err := t.put(key, it); err != nil {
			return err
		}
	}
	held := func(key fileKey) bool { return p.unchanged[key] }
	copied := map[fileKey]bool{}
	links := map[fileKey]string{}
	for key := range p.unchanged {
		if link, ok := p.scan.linkWithin(key, held); ok {
			links[key] = link
			continue
		}
		data, err := p.scan.read(key)
		if errors.Is(err, errSkipped) {
			continue
		}
		if err != nil {
			return err
		}
		if err := t.put(key, item{data: data}); err != nil {
			return err
		}
		copied[key] = true
	}
	for key, link := range links {
		if !p.lands(key, copied) {
			continue
		}
		if err := t.put(key, item{link: link}); err != nil {
			return err
		}
	}
	if err := t.linkDirs(p.scan.alias); err != nil {
		return err
	}
	dirs := p.dirs(maps.Keys(p.colored))
	maps.Copy(dirs, p.dirs(maps.Keys(p.unchanged)))
	return os.WriteFile(filepath.Join(root, "index.theme"), p.index(dirs), 0o644)
}

// lands reports whether a link chain ends at a copied file; a skipped one would dangle.
func (p *plan) lands(key fileKey, copied map[fileKey]bool) bool {
	for range 16 {
		if copied[key] {
			return true
		}
		next, ok := p.scan.follow(key, p.scan.files[key.dir][key.name])
		if !ok || !p.unchanged[next] {
			return false
		}
		key = next
	}
	return false
}

func (p *plan) index(own map[string]bool) []byte {
	th := p.scan.theme
	var plain, scaled []string
	var sections strings.Builder
	declare := func(rel string, dir themeDir) {
		if dir.scaled {
			scaled = append(scaled, rel)
		} else {
			plain = append(plain, rel)
		}
		fmt.Fprintf(&sections, "\n[%s]\n", rel)
		for _, key := range directoryKeys {
			if value := dir.keys[key]; value != "" {
				fmt.Fprintf(&sections, "%s=%s\n", key, value)
			}
		}
	}
	for _, dir := range th.dirs {
		if own[dir.rel] {
			declare(dir.rel, dir)
		}
	}

	var b strings.Builder
	fmt.Fprintf(&b, "[Icon Theme]\nName=%s (DMS folders)\nComment=Generated by DMS. Do not edit.\nInherits=%s,hicolor\nHidden=true\n%s\n", th.name, th.name, generatedKey)
	// Without this, KIconLoader stops tinting inherited monochrome icons in KDE apps.
	if th.follow != "" {
		fmt.Fprintf(&b, "FollowsColorScheme=%s\n", th.follow)
	}
	fmt.Fprintf(&b, "Directories=%s\n", strings.Join(plain, ","))
	if len(scaled) > 0 {
		fmt.Fprintf(&b, "ScaledDirectories=%s\n", strings.Join(scaled, ","))
	}
	b.WriteString(sections.String())
	return []byte(b.String())
}

type rank struct {
	scalable bool
	size     int
	rel      string
}

func (r rank) beats(other rank) bool {
	switch {
	case r.scalable != other.scalable:
		return r.scalable
	case r.size != other.size:
		return r.size > other.size
	}
	return r.rel < other.rel
}

func (p *plan) manifest() map[string]string {
	ranks := map[string]rank{}
	for _, dir := range p.scan.theme.dirs {
		if scale := dir.keys["Scale"]; dir.scaled || scale != "" && scale != "1" {
			continue
		}
		size, _ := strconv.Atoi(dir.keys["Size"])
		ranks[dir.rel] = rank{scalable: dir.keys["Type"] == "Scalable", size: size, rel: dir.rel}
	}
	reached := map[string][]string{}
	for alias, canonical := range p.scan.alias {
		reached[canonical] = append(reached[canonical], alias)
	}

	best := map[string]rank{}
	icons := map[string]string{}
	for key := range p.colored {
		icon := iconName(key.name)
		for _, rel := range append([]string{key.dir}, reached[key.dir]...) {
			r, declared := ranks[rel]
			if !declared {
				continue
			}
			if held, found := best[icon]; found && !r.beats(held) {
				continue
			}
			best[icon] = r
			icons[icon] = rel + "/" + key.name
		}
	}
	return icons
}
