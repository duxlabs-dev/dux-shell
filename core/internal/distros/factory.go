package distros

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

// NewDependencyDetector creates a DependencyDetector for the specified distribution
func NewDependencyDetector(distribution string, logChan chan<- string) (deps.DependencyDetector, error) {
	distro, err := NewDistribution(distribution, logChan)
	if err != nil {
		return nil, err
	}
	return distro, nil
}

// NewPackageInstaller creates a Distribution for package installation
func NewPackageInstaller(distribution string, logChan chan<- string) (Distribution, error) {
	return NewDistribution(distribution, logChan)
}
