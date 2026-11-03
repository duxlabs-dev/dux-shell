package sysupdate

import (
	"reflect"
	"testing"
)

func TestParseZypperXML(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    []Package
		wantErr bool
	}{
		{
			name:  "empty stream",
			input: `<?xml version="1.0"?><stream><update-list></update-list></stream>`,
			want:  []Package{},
		},
		{
			name: "skips non-package kinds",
			input: `<?xml version="1.0"?>
<stream>
  <update-list>
    <update name="foo" edition="2.0" edition-old="1.0" kind="package"/>
    <update name="security-patch" edition="1" edition-old="0" kind="patch"/>
    <update name="bar" edition="3.0" edition-old="2.0" kind="package"/>
  </update-list>
</stream>`,
			want: []Package{
				{Name: "foo", Repo: RepoSystem, Backend: "zypper", FromVersion: "1.0", ToVersion: "2.0"},
				{Name: "bar", Repo: RepoSystem, Backend: "zypper", FromVersion: "2.0", ToVersion: "3.0"},
			},
		},
		{
			name: "treats missing kind as package",
			input: `<?xml version="1.0"?>
<stream><update-list>
  <update name="kernel" edition="6.18.1-1" edition-old="6.18.0-1"/>
</update-list></stream>`,
			want: []Package{
				{Name: "kernel", Repo: RepoSystem, Backend: "zypper", FromVersion: "6.18.0-1", ToVersion: "6.18.1-1"},
			},
		},
		{
			name:    "malformed XML returns error",
			input:   `not xml at all`,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseZypperXML([]byte(tt.input))
			if (err != nil) != tt.wantErr {
				t.Fatalf("parseZypperXML() err = %v, wantErr %v", err, tt.wantErr)
			}
			if tt.wantErr {
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("parseZypperXML() = %#v\nwant %#v", got, tt.want)
			}
		})
	}
}
