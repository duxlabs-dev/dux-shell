package distros

import (
	"testing"
)

func TestManualPackageInstaller_parseLatestTagFromGitOutput(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name: "normal tag output",
			input: `a1a150fab00a93ea983aaca5df55304bc837f51b	refs/tags/v0.2.1
a5431dd02dc23d9ef1680e67777fed00fe5f7cda	refs/tags/v0.2.0
703a3789083d2f990c4e99cd25c97c2a4cccbd81	refs/tags/v0.1.0`,
			expected: "v0.2.1",
		},
		{
			name: "annotated tags with ^{}",
			input: `a1a150fab00a93ea983aaca5df55304bc837f51b	refs/tags/v0.2.1
b1b150fab00a93ea983aaca5df55304bc837f51c	refs/tags/v0.2.1^{}
a5431dd02dc23d9ef1680e67777fed00fe5f7cda	refs/tags/v0.2.0`,
			expected: "v0.2.1",
		},
		{
			name:     "empty output",
			input:    "",
			expected: "",
		},
		{
			name: "only annotated tags",
			input: `a1a150fab00a93ea983aaca5df55304bc837f51b	refs/tags/v0.2.1^{}
a5431dd02dc23d9ef1680e67777fed00fe5f7cda	refs/tags/v0.2.0^{}`,
			expected: "",
		},
	}

	logChan := make(chan string, 100)
	defer close(logChan)

	base := NewBaseDistribution(logChan)
	installer := &ManualPackageInstaller{BaseDistribution: base}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := installer.parseLatestTagFromGitOutput(tt.input)

			if result != tt.expected {
				t.Errorf("parseLatestTagFromGitOutput() = %q, expected %q", result, tt.expected)
			}
		})
	}
}
