package highlight

import (
	"bytes"

	"github.com/alecthomas/chroma/v2"
	"github.com/alecthomas/chroma/v2/formatters/html"
	"github.com/duxlabs-dev/dux-shell/core/internal/highlight/lexers"
	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/renderer"
	ghtml "github.com/yuin/goldmark/renderer/html"
	"github.com/yuin/goldmark/util"
)

// Markdown is a goldmark extension that highlights fenced code blocks with a
// known language; other blocks render as plain <pre><code>.
type Markdown struct {
	Style     *chroma.Style
	Formatter *html.Formatter
}

func (m Markdown) Extend(md goldmark.Markdown) {
	md.Renderer().AddOptions(renderer.WithNodeRenderers(util.Prioritized(m, 200)))
}

func (m Markdown) RegisterFuncs(reg renderer.NodeRendererFuncRegisterer) {
	reg.Register(ast.KindFencedCodeBlock, m.renderFencedCodeBlock)
}

func (m Markdown) renderFencedCodeBlock(w util.BufWriter, source []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
	if !entering {
		return ast.WalkContinue, nil
	}
	n := node.(*ast.FencedCodeBlock)
	language := n.Language(source)

	var code bytes.Buffer
	for i := range n.Lines().Len() {
		line := n.Lines().At(i)
		code.Write(line.Value(source))
	}

	var lexer chroma.Lexer
	if language != nil {
		lexer = lexers.Get(string(language))
	}
	if lexer == nil {
		_, _ = w.WriteString("<pre><code")
		if language != nil {
			_, _ = w.WriteString(` class="language-`)
			ghtml.DefaultWriter.Write(w, language)
			_, _ = w.WriteString(`"`)
		}
		_ = w.WriteByte('>')
		ghtml.DefaultWriter.RawWrite(w, code.Bytes())
		_, _ = w.WriteString("</code></pre>\n")
		return ast.WalkContinue, nil
	}

	iterator, err := chroma.Coalesce(lexer).Tokenise(nil, code.String())
	if err != nil {
		return ast.WalkStop, err
	}
	return ast.WalkContinue, m.Formatter.Format(w, m.Style, iterator)
}
