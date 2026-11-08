package fcitx5

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/godbus/dbus/v5"
)

const listPrefix = "List|"

type Field struct {
	Name        string         `json:"name"`
	Type        string         `json:"type"`
	Description string         `json:"description"`
	Default     any            `json:"default"`
	Props       map[string]any `json:"props,omitempty"`
}

type Struct struct {
	Name   string  `json:"name"`
	Fields []Field `json:"fields"`
}

type Schema struct {
	Root    string   `json:"root"`
	Structs []Struct `json:"structs"`
}

type rawField struct {
	Name        string
	Type        string
	Description string
	Default     dbus.Variant
	Props       map[string]dbus.Variant
}

type rawStruct struct {
	Name   string
	Fields []rawField
}

func listify(m map[string]any) ([]any, bool) {
	idx := make([]int, 0, len(m))
	for k := range m {
		n, err := strconv.Atoi(k)
		if err != nil {
			return nil, false
		}
		idx = append(idx, n)
	}
	sort.Ints(idx)
	out := make([]any, 0, len(idx))
	for _, n := range idx {
		out = append(out, m[strconv.Itoa(n)])
	}
	return out, true
}

func structIndex(structs []Struct) map[string][]Field {
	idx := make(map[string][]Field, len(structs))
	for _, s := range structs {
		idx[s.Name] = s.Fields
	}
	return idx
}

func buildSchema(raw []rawStruct) Schema {
	schema := Schema{Structs: make([]Struct, 0, len(raw))}
	if len(raw) > 0 {
		schema.Root = raw[0].Name
	}
	for _, s := range raw {
		out := Struct{Name: s.Name, Fields: make([]Field, 0, len(s.Fields))}
		for _, f := range s.Fields {
			props := make(map[string]any, len(f.Props))
			for k, p := range f.Props {
				d := dbusutil.Normalize(p)
				if m, ok := d.(map[string]any); ok {
					if l, isList := listify(m); isList {
						d = l
					}
				}
				props[k] = d
			}
			out.Fields = append(out.Fields, Field{
				Name:        f.Name,
				Type:        f.Type,
				Description: f.Description,
				Default:     dbusutil.Normalize(f.Default),
				Props:       props,
			})
		}
		schema.Structs = append(schema.Structs, out)
	}

	structs := structIndex(schema.Structs)
	for i := range schema.Structs {
		for j := range schema.Structs[i].Fields {
			f := &schema.Structs[i].Fields[j]
			f.Default = toTyped(f.Default, f.Type, structs)
		}
	}
	return schema
}

func toTyped(raw any, typ string, structs map[string][]Field) any {
	m, isMap := raw.(map[string]any)
	if !isMap {
		return raw
	}
	if elem, ok := strings.CutPrefix(typ, listPrefix); ok {
		items, isList := listify(m)
		if !isList {
			return raw
		}
		for i, item := range items {
			items[i] = toTyped(item, elem, structs)
		}
		return items
	}
	fields, ok := structs[typ]
	if !ok {
		return raw
	}
	byName := make(map[string]string, len(fields))
	for _, f := range fields {
		byName[f.Name] = f.Type
	}
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = toTyped(v, byName[k], structs)
	}
	return out
}

func keepHidden(value, live map[string]any, typ string, structs map[string][]Field) map[string]any {
	types := make(map[string]string, len(structs[typ]))
	for _, f := range structs[typ] {
		types[f.Name] = f.Type
	}
	out := make(map[string]any, len(value))
	for k, v := range value {
		if _, known := types[k]; known {
			out[k] = v
		}
	}
	for k, v := range live {
		fieldType, known := types[k]
		if !known {
			out[k] = v
			continue
		}
		sent, isSent := out[k].(map[string]any)
		current, isCurrent := v.(map[string]any)
		if _, isStruct := structs[fieldType]; isStruct && isSent && isCurrent {
			out[k] = keepHidden(sent, current, fieldType, structs)
		}
	}
	return out
}

func scalarString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case bool:
		if t {
			return "True"
		}
		return "False"
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	case nil:
		return ""
	default:
		return fmt.Sprint(t)
	}
}

func fromTyped(v any, typ string, structs map[string][]Field) dbus.Variant {
	elem, isList := strings.CutPrefix(typ, listPrefix)
	switch t := v.(type) {
	case []any:
		out := make(map[string]dbus.Variant, len(t))
		for i, item := range t {
			out[strconv.Itoa(i)] = fromTyped(item, elem, structs)
		}
		return dbus.MakeVariant(out)
	case map[string]any:
		byName := make(map[string]string)
		for _, f := range structs[typ] {
			byName[f.Name] = f.Type
		}
		out := make(map[string]dbus.Variant, len(t))
		for k, e := range t {
			out[k] = fromTyped(e, byName[k], structs)
		}
		return dbus.MakeVariant(out)
	default:
		if isList {
			return dbus.MakeVariant(map[string]dbus.Variant{})
		}
		return dbus.MakeVariant(scalarString(v))
	}
}
