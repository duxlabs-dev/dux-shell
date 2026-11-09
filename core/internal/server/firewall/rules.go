package firewall

import (
	"errors"
	"fmt"
	"net/netip"
	"regexp"
	"strconv"
	"strings"
)

const (
	ActionAllow  = "allow"
	ActionDrop   = "drop"
	ActionReject = "reject"

	KindService = "service"
	KindPort    = "port"
	KindRaw     = "raw"

	ProtoTCP  = "tcp"
	ProtoUDP  = "udp"
	ProtoBoth = "both"
)

var (
	serviceNamePattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9 _.+-]*$`)
	// Only the shapes richRule writes. Anything else firewalld holds stays raw.
	richRulePattern = regexp.MustCompile(`^rule(?: family="ipv[46]" source address="([^"]+)")? (?:service name="([^"]+)"|port port="([0-9]+(?:-[0-9]+)?)" protocol="(tcp|udp)") (accept|drop|reject)$`)
)

const maxRuleNameLength = 64

type RuleSpec struct {
	Kind   string
	Action string
	Target string
	Proto  string
	Source string
	Name   string
}

// Rules must follow spec before reaching firewalld/ufw
func (s RuleSpec) Validate() error {
	switch s.Action {
	case ActionAllow, ActionDrop, ActionReject:
	default:
		return fmt.Errorf("invalid action: %q", s.Action)
	}

	switch s.Kind {
	case KindService:
		if !serviceNamePattern.MatchString(s.Target) {
			return fmt.Errorf("invalid service name: %q", s.Target)
		}
	case KindPort:
		if err := validatePort(s.Target); err != nil {
			return err
		}
		switch s.Proto {
		case ProtoTCP, ProtoUDP, ProtoBoth:
		default:
			return fmt.Errorf("invalid protocol: %q", s.Proto)
		}
		if s.Proto == ProtoBoth && strings.Contains(s.Target, "-") {
			return errors.New("a port range needs tcp or udp")
		}
	default:
		return fmt.Errorf("invalid rule kind: %q", s.Kind)
	}

	if err := validateRuleName(s.Name); err != nil {
		return err
	}
	if s.Source == "" {
		return nil
	}
	if _, err := parseSource(s.Source); err != nil {
		return fmt.Errorf("invalid source: %q", s.Source)
	}
	return nil
}

func validateRuleName(name string) error {
	if len(name) > maxRuleNameLength {
		return fmt.Errorf("rule name is longer than %d characters", maxRuleNameLength)
	}
	for _, r := range name {
		if r == '\'' || r < ' ' || r == 0x7f {
			return fmt.Errorf("invalid character %q in rule name", r)
		}
	}
	return nil
}

// spec rebuilds what created the rule, so an edit can put it back when the new one fails.
func (r Rule) spec() (RuleSpec, error) {
	if r.Kind != KindService && r.Kind != KindPort {
		return RuleSpec{}, errors.New("this rule can only be removed")
	}
	spec := RuleSpec{Kind: r.Kind, Action: r.Action, Target: r.Target, Proto: r.Proto, Source: r.Source, Name: r.Name}
	if spec.Kind == KindPort && spec.Proto == "" {
		spec.Proto = ProtoBoth
	}
	return spec, nil
}

func (s RuleSpec) sameMatch(other RuleSpec) bool {
	proto := func(spec RuleSpec) string {
		if spec.Kind == KindService {
			return ""
		}
		if spec.Proto == "" {
			return ProtoBoth
		}
		return spec.Proto
	}
	return s.Kind == other.Kind && s.Target == other.Target && s.Source == other.Source && proto(s) == proto(other)
}

func parseRichRule(rich string) Rule {
	rule := Rule{ID: KindRaw + ":" + rich, Kind: KindRaw, Raw: rich}
	m := richRulePattern.FindStringSubmatch(rich)
	if m == nil {
		return rule
	}
	if m[1] != "" {
		if _, err := parseSource(m[1]); err != nil {
			return rule
		}
	}
	rule.Raw, rule.Source = "", m[1]
	switch m[5] {
	case "drop":
		rule.Action = ActionDrop
	case "reject":
		rule.Action = ActionReject
	default:
		rule.Action = ActionAllow
	}
	if m[2] != "" {
		rule.Kind, rule.Target = KindService, m[2]
		return rule
	}
	rule.Kind, rule.Target, rule.Proto = KindPort, m[3], m[4]
	return rule
}

func validatePort(port string) error {
	first, last, isRange := strings.Cut(port, "-")
	low, err := parsePortNumber(first)
	if err != nil {
		return fmt.Errorf("invalid port: %q", port)
	}
	if !isRange {
		return nil
	}
	high, err := parsePortNumber(last)
	if err != nil || high <= low {
		return fmt.Errorf("invalid port range: %q", port)
	}
	return nil
}

func parsePortNumber(value string) (int, error) {
	if value == "" || strings.ContainsAny(value, "+-") {
		return 0, errors.New("not a port")
	}
	port, err := strconv.Atoi(value)
	if err != nil || port < 1 || port > 65535 {
		return 0, errors.New("not a port")
	}
	return port, nil
}

func parseSource(source string) (netip.Addr, error) {
	if prefix, err := netip.ParsePrefix(source); err == nil {
		return prefix.Addr(), nil
	}
	addr, err := netip.ParseAddr(source)
	if err != nil {
		return netip.Addr{}, err
	}
	// A zone may hold quotes and spaces, which would break out of a rich rule.
	if addr.Zone() != "" {
		return netip.Addr{}, errors.New("zones are not supported")
	}
	return addr, nil
}

func (s RuleSpec) protocols() []string {
	if s.Kind != KindPort {
		return []string{""}
	}
	if s.Proto == ProtoBoth {
		return []string{ProtoTCP, ProtoUDP}
	}
	return []string{s.Proto}
}

func (s RuleSpec) needsRichRule() bool {
	return s.Action != ActionAllow || s.Source != ""
}

func (s RuleSpec) richRule(proto string) string {
	parts := []string{"rule"}
	if s.Source != "" {
		family := "ipv4"
		if addr, err := parseSource(s.Source); err == nil && addr.Is6() {
			family = "ipv6"
		}
		parts = append(parts, fmt.Sprintf(`family="%s" source address="%s"`, family, s.Source))
	}
	if s.Kind == KindService {
		parts = append(parts, fmt.Sprintf(`service name="%s"`, s.Target))
	} else {
		parts = append(parts, fmt.Sprintf(`port port="%s" protocol="%s"`, s.Target, proto))
	}
	switch s.Action {
	case ActionDrop:
		parts = append(parts, "drop")
	case ActionReject:
		parts = append(parts, "reject")
	default:
		parts = append(parts, "accept")
	}
	return strings.Join(parts, " ")
}

func (s RuleSpec) ufwArgs() []string {
	args := s.ufwRuleArgs()
	if s.Name != "" {
		args = append(args, "comment", s.Name)
	}
	return args
}

func ufwAction(verb string) string {
	if verb == "deny" {
		return ActionDrop
	}
	return verb
}

// ufw has no "drop" verb; its equivalent is "deny".
func ufwVerb(action string) string {
	if action == ActionDrop {
		return "deny"
	}
	return action
}

func (s RuleSpec) ufwRuleArgs() []string {
	verb := ufwVerb(s.Action)
	if s.Kind == KindService {
		if s.Source == "" {
			return []string{verb, s.Target}
		}
		return []string{verb, "from", s.Source, "to", "any", "app", s.Target}
	}

	port := strings.ReplaceAll(s.Target, "-", ":")
	if s.Source != "" {
		args := []string{verb, "from", s.Source, "to", "any", "port", port}
		if s.Proto != ProtoBoth {
			args = append(args, "proto", s.Proto)
		}
		return args
	}
	if s.Proto != ProtoBoth {
		port += "/" + s.Proto
	}
	return []string{verb, port}
}
