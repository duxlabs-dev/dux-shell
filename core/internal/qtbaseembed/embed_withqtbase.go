//go:build withqtbase

package qtbaseembed

import "embed"

// all: keeps the .dankrev revision key, which go:embed would otherwise skip as a dotfile.
//
//go:embed all:lib
var libFS embed.FS
