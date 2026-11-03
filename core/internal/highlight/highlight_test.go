package highlight

import (
	"bytes"
	"strings"
	"testing"

	"github.com/alecthomas/chroma/v2/formatters/html"
	"github.com/duxlabs-dev/dux-shell/core/internal/highlight/styles"
	"github.com/yuin/goldmark"
)

func TestMarkdown(t *testing.T) {
	md := goldmark.New(goldmark.WithExtensions(Markdown{Style: styles.Get("monokai"), Formatter: html.New(html.WithClasses(false))}))
	cases := []struct{ in, want string }{
		{"```go\nfunc main() {}\n```\n", `style="color:`},
		{"```nope\na < b\n```\n", `<pre><code class="language-nope">a &lt; b`},
		{"```\nplain\n```\n", `<pre><code>plain`},
	}
	for _, tc := range cases {
		var out bytes.Buffer
		if err := md.Convert([]byte(tc.in), &out); err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(out.String(), tc.want) {
			t.Errorf("%q rendered %q, want %q", tc.in, out.String(), tc.want)
		}
	}
}
