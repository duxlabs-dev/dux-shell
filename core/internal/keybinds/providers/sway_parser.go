package providers

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	SwayTitleRegex  = "#+!"
	SwayHideComment = "[hidden]"
)

var SwayModSeparators = []rune{'+', ' '}

type SwayKeyBinding struct {
	Mods    []string `json:"mods"`
	Key     string   `json:"key"`
	Command string   `json:"command"`
	Comment string   `json:"comment"`
}

type SwaySection struct {
	Children []SwaySection    `json:"children"`
	Keybinds []SwayKeyBinding `json:"keybinds"`
	Name     string           `json:"name"`
}

type SwayParser struct {
	contentLines []string
	readingLine  int
	variables    map[string]string
}

func NewSwayParser() *SwayParser {
	return &SwayParser{
		contentLines: []string{},
		readingLine:  0,
		variables:    make(map[string]string),
	}
}

func (p *SwayParser) ReadContent(path string) error {
	expandedPath, err := utils.ExpandPath(path)
	if err != nil {
		return err
	}

	info, err := os.Stat(expandedPath)
	if err != nil {
		return err
	}

	var files []string
	if info.IsDir() {
		mainConfig := filepath.Join(expandedPath, "config")
		if fileInfo, err := os.Stat(mainConfig); err == nil && fileInfo.Mode().IsRegular() {
			files = []string{mainConfig}
		} else {
			return os.ErrNotExist
		}
	} else {
		files = []string{expandedPath}
	}

	var combinedContent []string
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			return err
		}
		combinedContent = append(combinedContent, string(data))
	}

	if len(combinedContent) == 0 {
		return os.ErrNotExist
	}

	fullContent := strings.Join(combinedContent, "\n")
	p.contentLines = strings.Split(fullContent, "\n")
	p.parseVariables()
	return nil
}

func (p *SwayParser) parseVariables() {
	setRegex := regexp.MustCompile(`^\s*set\s+\$(\w+)\s+(.+)$`)
	for _, line := range p.contentLines {
		matches := setRegex.FindStringSubmatch(line)
		if len(matches) == 3 {
			varName := matches[1]
			varValue := strings.TrimSpace(matches[2])
			p.variables[varName] = varValue
		}
	}
}

func (p *SwayParser) ModVariable() string {
	return p.variables["mod"]
}

func (p *SwayParser) expandVariables(text string) string {
	result := text
	for varName, varValue := range p.variables {
		result = strings.ReplaceAll(result, "$"+varName, varValue)
	}
	return result
}

func swayAutogenerateComment(command string) string {
	command = strings.TrimSpace(command)

	if after, ok := strings.CutPrefix(command, "exec "); ok {
		cmdPart := after
		cmdPart = strings.TrimPrefix(cmdPart, "--no-startup-id ")
		return cmdPart
	}

	switch {
	case command == "kill":
		return "Close window"
	case command == "exit":
		return "Exit Sway"
	case command == "reload":
		return "Reload configuration"
	case strings.HasPrefix(command, "fullscreen"):
		return "Toggle fullscreen"
	case strings.HasPrefix(command, "floating toggle"):
		return "Float/unfloat window"
	case strings.HasPrefix(command, "focus mode_toggle"):
		return "Toggle focus mode"
	case strings.HasPrefix(command, "focus parent"):
		return "Focus parent container"
	case strings.HasPrefix(command, "focus left"):
		return "Focus left"
	case strings.HasPrefix(command, "focus right"):
		return "Focus right"
	case strings.HasPrefix(command, "focus up"):
		return "Focus up"
	case strings.HasPrefix(command, "focus down"):
		return "Focus down"
	case strings.HasPrefix(command, "focus output"):
		return "Focus monitor"
	case strings.HasPrefix(command, "move left"):
		return "Move window left"
	case strings.HasPrefix(command, "move right"):
		return "Move window right"
	case strings.HasPrefix(command, "move up"):
		return "Move window up"
	case strings.HasPrefix(command, "move down"):
		return "Move window down"
	case strings.HasPrefix(command, "move container to workspace"):
		if strings.Contains(command, "prev") {
			return "Move to previous workspace"
		}
		if strings.Contains(command, "next") {
			return "Move to next workspace"
		}
		parts := strings.Fields(command)
		if len(parts) > 4 {
			return "Move to workspace " + parts[len(parts)-1]
		}
		return "Move to workspace"
	case strings.HasPrefix(command, "move workspace to output"):
		return "Move workspace to monitor"
	case strings.HasPrefix(command, "workspace"):
		if strings.Contains(command, "prev") {
			return "Previous workspace"
		}
		if strings.Contains(command, "next") {
			return "Next workspace"
		}
		parts := strings.Fields(command)
		if len(parts) > 1 {
			wsNum := parts[len(parts)-1]
			return "Workspace " + wsNum
		}
		return "Switch workspace"
	case strings.HasPrefix(command, "layout"):
		parts := strings.Fields(command)
		if len(parts) > 1 {
			return "Layout " + parts[1]
		}
		return "Change layout"
	case strings.HasPrefix(command, "split"):
		if strings.Contains(command, "h") {
			return "Split horizontal"
		}
		if strings.Contains(command, "v") {
			return "Split vertical"
		}
		return "Split container"
	case strings.HasPrefix(command, "resize"):
		return "Resize window"
	case strings.Contains(command, "scratchpad"):
		return "Toggle scratchpad"
	default:
		return command
	}
}

func (p *SwayParser) getKeybindAtLine(lineNumber int) *SwayKeyBinding {
	if lineNumber >= len(p.contentLines) {
		return nil
	}

	line := p.contentLines[lineNumber]

	bindMatch := regexp.MustCompile(`^\s*(bindsym|bindcode)\s+(.+)$`)
	matches := bindMatch.FindStringSubmatch(line)
	if len(matches) < 3 {
		return nil
	}

	content := matches[2]

	parts := strings.SplitN(content, "#", 2)
	keys := strings.TrimSpace(parts[0])

	var comment string
	if len(parts) > 1 {
		comment = strings.TrimSpace(parts[1])
	}

	if strings.HasPrefix(comment, SwayHideComment) {
		return nil
	}

	flags := ""
	if strings.HasPrefix(keys, "--") {
		spaceIdx := strings.Index(keys, " ")
		if spaceIdx > 0 {
			flags = keys[:spaceIdx]
			keys = strings.TrimSpace(keys[spaceIdx+1:])
		}
	}

	keyParts := strings.Fields(keys)
	if len(keyParts) < 2 {
		return nil
	}

	keyCombo := keyParts[0]
	keyCombo = p.expandVariables(keyCombo)
	command := strings.Join(keyParts[1:], " ")
	command = p.expandVariables(command)

	var modList []string
	var key string

	modstring := keyCombo + string(SwayModSeparators[0])
	pos := 0
	for index, char := range modstring {
		isModSep := slices.Contains(SwayModSeparators, char)
		if isModSep {
			if index-pos > 0 {
				part := modstring[pos:index]
				if swayIsMod(part) {
					modList = append(modList, part)
				} else {
					key = part
				}
			}
			pos = index + 1
		}
	}

	if comment == "" {
		comment = swayAutogenerateComment(command)
	}

	_ = flags

	return &SwayKeyBinding{
		Mods:    modList,
		Key:     key,
		Command: command,
		Comment: comment,
	}
}

func swayIsMod(s string) bool {
	s = strings.ToLower(s)
	if s == "mod1" || s == "mod2" || s == "mod3" || s == "mod4" || s == "mod5" ||
		s == "shift" || s == "control" || s == "ctrl" || s == "alt" || s == "super" ||
		strings.HasPrefix(s, "$") {
		return true
	}

	isNumeric := true
	for _, c := range s {
		if c < '0' || c > '9' {
			isNumeric = false
			break
		}
	}
	if isNumeric && len(s) >= 2 {
		return true
	}
	return false
}

func (p *SwayParser) getBindsRecursive(currentContent *SwaySection, scope int) *SwaySection {
	titleRegex := regexp.MustCompile(SwayTitleRegex)

	for p.readingLine < len(p.contentLines) {
		line := p.contentLines[p.readingLine]

		loc := titleRegex.FindStringIndex(line)
		if loc != nil && loc[0] == 0 {
			headingScope := strings.Index(line, "!")

			if headingScope <= scope {
				p.readingLine--
				return currentContent
			}

			sectionName := strings.TrimSpace(line[headingScope+1:])
			p.readingLine++

			childSection := &SwaySection{
				Children: []SwaySection{},
				Keybinds: []SwayKeyBinding{},
				Name:     sectionName,
			}
			result := p.getBindsRecursive(childSection, headingScope)
			currentContent.Children = append(currentContent.Children, *result)

		} else if line == "" || (!strings.Contains(line, "bindsym") && !strings.Contains(line, "bindcode")) {

		} else {
			keybind := p.getKeybindAtLine(p.readingLine)
			if keybind != nil {
				currentContent.Keybinds = append(currentContent.Keybinds, *keybind)
			}
		}

		p.readingLine++
	}

	return currentContent
}

func (p *SwayParser) ParseKeys() *SwaySection {
	p.readingLine = 0
	rootSection := &SwaySection{
		Children: []SwaySection{},
		Keybinds: []SwayKeyBinding{},
		Name:     "",
	}
	return p.getBindsRecursive(rootSection, 0)
}

func ParseSwayKeys(path string) (*SwaySection, error) {
	parser := NewSwayParser()
	if err := parser.ReadContent(path); err != nil {
		return nil, err
	}
	return parser.ParseKeys(), nil
}
