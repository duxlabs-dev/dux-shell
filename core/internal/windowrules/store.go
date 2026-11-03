package windowrules

type RuleStore interface {
	EnsureWritable() error
	LoadDMSRules() ([]WindowRule, error)
	WriteDMSRules([]WindowRule) error
}

const OpaqueRuleID = "dms-window-opaque"

// pinDMSRules puts the opaque rule last, since compositors apply rules in
// order and the last match wins.
func pinDMSRules(rules []WindowRule) []WindowRule {
	var rest, last []WindowRule
	for _, rule := range rules {
		if rule.ID == OpaqueRuleID {
			last = append(last, rule)
		} else {
			rest = append(rest, rule)
		}
	}
	return append(rest, last...)
}

func Set(store RuleStore, rule WindowRule) error {
	if err := store.EnsureWritable(); err != nil {
		return err
	}
	rules, err := store.LoadDMSRules()
	if err != nil {
		rules = []WindowRule{}
	}

	for i, existing := range rules {
		if existing.ID != rule.ID {
			continue
		}
		rules[i] = rule
		return store.WriteDMSRules(pinDMSRules(rules))
	}

	return store.WriteDMSRules(pinDMSRules(append(rules, rule)))
}

func Remove(store RuleStore, id string) error {
	if err := store.EnsureWritable(); err != nil {
		return err
	}
	rules, err := store.LoadDMSRules()
	if err != nil {
		return err
	}

	kept := make([]WindowRule, 0, len(rules))
	for _, rule := range rules {
		if rule.ID == id {
			continue
		}
		kept = append(kept, rule)
	}

	return store.WriteDMSRules(pinDMSRules(kept))
}

func Reorder(store RuleStore, ids []string) error {
	if err := store.EnsureWritable(); err != nil {
		return err
	}
	rules, err := store.LoadDMSRules()
	if err != nil {
		return err
	}

	wanted := make(map[string]int, len(ids))
	for position, id := range ids {
		if _, seen := wanted[id]; seen {
			continue
		}
		wanted[id] = position
	}

	ordered := make([]WindowRule, len(ids))
	placed := make([]bool, len(ids))
	leftover := make([]WindowRule, 0, len(rules))
	for _, rule := range rules {
		position, ok := wanted[rule.ID]
		if !ok || placed[position] {
			leftover = append(leftover, rule)
			continue
		}
		ordered[position] = rule
		placed[position] = true
	}

	result := make([]WindowRule, 0, len(rules))
	for position, rule := range ordered {
		if !placed[position] {
			continue
		}
		result = append(result, rule)
	}

	return store.WriteDMSRules(pinDMSRules(append(result, leftover...)))
}
