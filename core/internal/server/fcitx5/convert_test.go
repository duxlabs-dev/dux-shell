package fcitx5

import (
	"reflect"
	"testing"

	"github.com/godbus/dbus/v5"
)

func sv(s string) dbus.Variant { return dbus.MakeVariant(s) }

func hangulSchema() []rawStruct {
	return []rawStruct{
		{Name: "HangulConfig", Fields: []rawField{
			{Name: "Keyboard", Type: "Enum", Default: sv("Dubeolsik"), Props: map[string]dbus.Variant{
				"Enum": dbus.MakeVariant(map[string]dbus.Variant{"1": sv("Romaja"), "0": sv("Dubeolsik")}),
			}},
			{Name: "NextPage", Type: "List|Key", Default: dbus.MakeVariant(map[string]dbus.Variant{"0": sv("Down")})},
			{Name: "Group", Type: "Group$GroupConfig", Default: sv("")},
		}},
		{Name: "Group$GroupConfig", Fields: []rawField{
			{Name: "Keys", Type: "List|Key"},
			{Name: "Flag", Type: "Boolean"},
		}},
	}
}

func hangulValue() dbus.Variant {
	return dbus.MakeVariant(map[string]dbus.Variant{
		"Keyboard": sv("Romaja"),
		"NextPage": dbus.MakeVariant(map[string]dbus.Variant{"1": sv("Tab"), "0": sv("Down"), "10": sv("F9"), "2": sv("Up")}),
		"Group": dbus.MakeVariant(map[string]dbus.Variant{
			"Keys": dbus.MakeVariant(map[string]dbus.Variant{"0": sv("a")}),
			"Flag": sv("True"),
		}),
	})
}

func TestToTypedOrdersListsAndNestsStructs(t *testing.T) {
	schema := buildSchema(hangulSchema())
	got := toTyped(decode(hangulValue()), schema.Root, structIndex(schema.Structs))
	want := map[string]any{
		"Keyboard": "Romaja",
		"NextPage": []any{"Down", "Tab", "Up", "F9"},
		"Group":    map[string]any{"Keys": []any{"a"}, "Flag": "True"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
}

func TestSchemaListifiesEnumPropsAndDefaults(t *testing.T) {
	schema := buildSchema(hangulSchema())
	kb := schema.Structs[0].Fields[0]
	if !reflect.DeepEqual(kb.Props["Enum"], []any{"Dubeolsik", "Romaja"}) {
		t.Fatalf("enum not ordered: %#v", kb.Props["Enum"])
	}
	if !reflect.DeepEqual(schema.Structs[0].Fields[1].Default, []any{"Down"}) {
		t.Fatalf("list default: %#v", schema.Structs[0].Fields[1].Default)
	}
}

func TestFromTypedRoundTrip(t *testing.T) {
	schema := buildSchema(hangulSchema())
	structs := structIndex(schema.Structs)
	typed := toTyped(decode(hangulValue()), schema.Root, structs)

	back := fromTyped(typed, schema.Root, structs)
	if !reflect.DeepEqual(decode(back), decode(canonical())) {
		t.Fatalf("round trip differs:\n%#v\n%#v", decode(back), decode(canonical()))
	}
}

// Wire form has dense list indexes, which is what we must send back.
func canonical() dbus.Variant {
	return dbus.MakeVariant(map[string]dbus.Variant{
		"Keyboard": sv("Romaja"),
		"NextPage": dbus.MakeVariant(map[string]dbus.Variant{"0": sv("Down"), "1": sv("Tab"), "2": sv("Up"), "3": sv("F9")}),
		"Group": dbus.MakeVariant(map[string]dbus.Variant{
			"Keys": dbus.MakeVariant(map[string]dbus.Variant{"0": sv("a")}),
			"Flag": sv("True"),
		}),
	})
}

func TestFromTypedStringifiesScalarsAndKeepsEmptyLists(t *testing.T) {
	schema := buildSchema(hangulSchema())
	structs := structIndex(schema.Structs)
	back := decode(fromTyped(map[string]any{
		"Group":    map[string]any{"Flag": true},
		"NextPage": []any{},
	}, schema.Root, structs))
	want := map[string]any{
		"Group":    map[string]any{"Flag": "True"},
		"NextPage": map[string]any{},
	}
	if !reflect.DeepEqual(back, want) {
		t.Fatalf("got %#v, want %#v", back, want)
	}
}
