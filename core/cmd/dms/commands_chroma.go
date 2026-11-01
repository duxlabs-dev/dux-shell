package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"

	"github.com/alecthomas/chroma/v2"
	"github.com/alecthomas/chroma/v2/formatters/html"
	"github.com/duxlabs-dev/dux-shell/core/internal/highlight"
	"github.com/duxlabs-dev/dux-shell/core/internal/highlight/lexers"
	"github.com/duxlabs-dev/dux-shell/core/internal/highlight/styles"
	"github.com/spf13/cobra"
	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/extension"
	"github.com/yuin/goldmark/parser"
	ghtml "github.com/yuin/goldmark/renderer/html"
)

var (
	chromaLanguage    string
	chromaStyle       string
	chromaInline      bool
	chromaMarkdown    bool
	chromaLineNumbers bool

	// Caching layer for performance
	lexerCache     = make(map[string]chroma.Lexer)
	styleCache     = make(map[string]*chroma.Style)
	formatterCache = make(map[string]*html.Formatter)
	cacheMutex     sync.RWMutex
	maxFileSize    = int64(5 * 1024 * 1024) // 5MB default
)

var chromaCmd = &cobra.Command{
	Use:   "chroma [file]",
	Short: "Syntax highlight source code",
	Long: `Generate syntax-highlighted HTML from source code.

Reads from file or stdin, outputs HTML with syntax highlighting.
Language is auto-detected from filename or can be specified with --language.

Examples:
  dms chroma main.go
  dms chroma --language python script.py
  echo "def foo(): pass" | dms chroma -l python
  cat code.rs | dms chroma -l rust --style dracula
  dms chroma --markdown README.md
  dms chroma --markdown --style github-dark notes.md
  dms chroma list-languages
  dms chroma list-styles`,
	Args: cobra.MaximumNArgs(1),
	Run:  runChroma,
}

var chromaListLanguagesCmd = &cobra.Command{
	Use:   "list-languages",
	Short: "List all supported languages",
	Run: func(cmd *cobra.Command, args []string) {
		for _, name := range lexers.Names(true) {
			fmt.Println(name)
		}
	},
}

var chromaListStylesCmd = &cobra.Command{
	Use:   "list-styles",
	Short: "List all available color styles",
	Run: func(cmd *cobra.Command, args []string) {
		for _, name := range styles.Names() {
			fmt.Println(name)
		}
	},
}

func init() {
	chromaCmd.Flags().StringVarP(&chromaLanguage, "language", "l", "", "Language for highlighting (auto-detect if not specified)")
	chromaCmd.Flags().StringVarP(&chromaStyle, "style", "s", "monokai", "Color style (monokai, dracula, github, etc.)")
	chromaCmd.Flags().BoolVar(&chromaInline, "inline", false, "Output inline styles instead of CSS classes")
	chromaCmd.Flags().BoolVar(&chromaLineNumbers, "line-numbers", false, "Show line numbers in output")
	chromaCmd.Flags().BoolVarP(&chromaMarkdown, "markdown", "m", false, "Render markdown with syntax-highlighted code blocks")
	chromaCmd.Flags().Int64Var(&maxFileSize, "max-size", 5*1024*1024, "Maximum file size to process without warning (bytes)")

	chromaCmd.AddCommand(chromaListLanguagesCmd)
	chromaCmd.AddCommand(chromaListStylesCmd)
}

func getCachedLexer(key string, fallbackFunc func() chroma.Lexer) chroma.Lexer {
	cacheMutex.RLock()
	if lexer, ok := lexerCache[key]; ok {
		cacheMutex.RUnlock()
		return lexer
	}
	cacheMutex.RUnlock()

	lexer := fallbackFunc()
	if lexer != nil {
		cacheMutex.Lock()
		lexerCache[key] = lexer
		cacheMutex.Unlock()
	}
	return lexer
}

func getCachedStyle(name string) *chroma.Style {
	cacheMutex.RLock()
	if style, ok := styleCache[name]; ok {
		cacheMutex.RUnlock()
		return style
	}
	cacheMutex.RUnlock()

	style := styles.Get(name)
	if style == nil {
		fmt.Fprintf(os.Stderr, "Warning: Style '%s' not found, using fallback\n", name)
		style = styles.Fallback()
	}

	cacheMutex.Lock()
	styleCache[name] = style
	cacheMutex.Unlock()
	return style
}

func getCachedFormatter(inline bool, lineNumbers bool) *html.Formatter {
	key := fmt.Sprintf("inline=%t,lineNumbers=%t", inline, lineNumbers)

	cacheMutex.RLock()
	if formatter, ok := formatterCache[key]; ok {
		cacheMutex.RUnlock()
		return formatter
	}
	cacheMutex.RUnlock()

	var opts []html.Option
	if inline {
		opts = append(opts, html.WithClasses(false))
	} else {
		opts = append(opts, html.WithClasses(true))
	}
	opts = append(opts, html.TabWidth(4))

	if lineNumbers {
		opts = append(opts, html.WithLineNumbers(true))
		opts = append(opts, html.LineNumbersInTable(false))
		opts = append(opts, html.WithLinkableLineNumbers(false, ""))
	}

	formatter := html.New(opts...)

	cacheMutex.Lock()
	formatterCache[key] = formatter
	cacheMutex.Unlock()
	return formatter
}

func runChroma(cmd *cobra.Command, args []string) {
	var source string
	var filename string

	// Read from file or stdin
	if len(args) > 0 {
		filename = args[0]

		// Check file size before reading
		fileInfo, err := os.Stat(filename)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading file info: %v\n", err)
			os.Exit(1)
		}

		if fileInfo.Size() > maxFileSize {
			fmt.Fprintf(os.Stderr, "Warning: File size (%d bytes) exceeds recommended limit (%d bytes)\n",
				fileInfo.Size(), maxFileSize)
			fmt.Fprintf(os.Stderr, "Processing may be slow. Consider using smaller files.\n")
		}

		content, err := os.ReadFile(filename)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading file: %v\n", err)
			os.Exit(1)
		}
		source = string(content)
	} else {
		stat, _ := os.Stdin.Stat()
		if (stat.Mode() & os.ModeCharDevice) != 0 {
			_ = cmd.Help()
			os.Exit(0)
		}

		content, err := io.ReadAll(os.Stdin)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading stdin: %v\n", err)
			os.Exit(1)
		}
		source = string(content)
	}

	// Handle empty input
	if strings.TrimSpace(source) == "" {
		return
	}

	// Handle Markdown rendering
	if chromaMarkdown {
		md := goldmark.New(
			goldmark.WithExtensions(
				extension.GFM,
				highlight.Markdown{
					Style:     styles.Get(chromaStyle),
					Formatter: html.New(html.WithClasses(!chromaInline)),
				},
			),
			goldmark.WithParserOptions(
				parser.WithAutoHeadingID(),
			),
			goldmark.WithRendererOptions(
				ghtml.WithHardWraps(),
				ghtml.WithXHTML(),
			),
		)

		var buf bytes.Buffer
		if err := md.Convert([]byte(source), &buf); err != nil {
			fmt.Fprintf(os.Stderr, "Markdown rendering error: %v\n", err)
			os.Exit(1)
		}
		fmt.Print(buf.String())
		return
	}

	// Detect or use specified lexer
	var lexer chroma.Lexer
	if chromaLanguage != "" {
		lexer = getCachedLexer(chromaLanguage, func() chroma.Lexer {
			l := lexers.Get(chromaLanguage)
			if l == nil {
				fmt.Fprintf(os.Stderr, "Unknown language: %s\n", chromaLanguage)
				os.Exit(1)
			}
			return l
		})
	} else if filename != "" {
		lexer = getCachedLexer("file:"+filename, func() chroma.Lexer {
			return lexers.Match(filename)
		})
	}

	// Try content analysis if no lexer found (limit to first 1KB for performance)
	if lexer == nil {
		analyzeContent := source
		if len(source) > 1024 {
			analyzeContent = source[:1024]
		}
		lexer = lexers.Analyse(analyzeContent)
	}

	// Fallback to plaintext
	if lexer == nil {
		lexer = lexers.Fallback
	}

	lexer = chroma.Coalesce(lexer)

	// Get cached style
	style := getCachedStyle(chromaStyle)

	// Get cached formatter
	formatter := getCachedFormatter(chromaInline, chromaLineNumbers)

	// Tokenize
	iterator, err := lexer.Tokenise(nil, source)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Tokenization error: %v\n", err)
		os.Exit(1)
	}

	// Format and output
	if chromaLineNumbers {
		var buf bytes.Buffer
		if err := formatter.Format(&buf, style, iterator); err != nil {
			fmt.Fprintf(os.Stderr, "Formatting error: %v\n", err)
			os.Exit(1)
		}
		// Add spacing between line numbers
		output := buf.String()
		output = strings.ReplaceAll(output, "</span><span>", "</span>\u00A0\u00A0<span>")
		fmt.Print(output)
	} else {
		if err := formatter.Format(os.Stdout, style, iterator); err != nil {
			fmt.Fprintf(os.Stderr, "Formatting error: %v\n", err)
			os.Exit(1)
		}
	}
}
