package distros

import (
	"bufio"
	"fmt"
	"os"
	"runtime"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/spf13/afero"
)

// DistroInfo contains basic information about a distribution
type DistroInfo struct {
	ID           string
	HexColorCode string
}

// OSInfo contains complete OS information
type OSInfo struct {
	// Raw os-release ID; Distribution.ID is the registered distro it resolves to via ID_LIKE (bazzite -> fedora).
	ID              string
	Distribution    DistroInfo
	Version         string
	VersionID       string
	VersionCodename string
	PrettyName      string
	Architecture    string
	IDLike          []string
	VariantID       string
	Immutable       bool
	ImmutableReason string
}

// GetOSInfo detects the current OS and returns information about it
func GetOSInfo() (*OSInfo, error) {
	if runtime.GOOS != "linux" {
		return nil, errdefs.NewCustomError(errdefs.ErrTypeNotLinux, fmt.Sprintf("Only linux is supported, but I found %s", runtime.GOOS))
	}

	if runtime.GOARCH != "amd64" && runtime.GOARCH != "arm64" {
		return nil, errdefs.NewCustomError(errdefs.ErrTypeInvalidArchitecture, fmt.Sprintf("Only amd64 and arm64 are supported, but I found %s", runtime.GOARCH))
	}

	return getOSInfo(afero.NewOsFs(), runtime.GOARCH)
}

// An unregistered ID is only an error on a mutable system; immutable hosts
// stop at the guidance screen and need no Distribution implementation.
func getOSInfo(fs afero.Fs, arch string) (*OSInfo, error) {
	values := readOSRelease(fs)
	if len(values) == 0 {
		return nil, fmt.Errorf("cannot read /etc/os-release")
	}

	info := &OSInfo{
		Architecture:    arch,
		Version:         values["VERSION"],
		VersionID:       values["VERSION_ID"],
		VersionCodename: values["VERSION_CODENAME"],
		PrettyName:      values["PRETTY_NAME"],
		IDLike:          strings.Fields(values["ID_LIKE"]),
		VariantID:       values["VARIANT_ID"],
	}
	if info.VersionID == "" {
		info.VersionID = values["BUILD_ID"]
	}
	info.Immutable, info.ImmutableReason = detectImmutable(fs, values)

	info.ID = values["ID"]
	id := info.ID
	config, exists := Registry[id]
	if !exists && !info.Immutable {
		return nil, errdefs.NewCustomError(errdefs.ErrTypeUnsupportedDistribution, fmt.Sprintf("Unsupported distribution: %s", id))
	}
	if !exists {
		for _, like := range info.IDLike {
			if likeConfig, ok := Registry[like]; ok {
				id, config = like, likeConfig
				break
			}
		}
	}
	info.Distribution = DistroInfo{ID: id, HexColorCode: config.ColorHex}

	return info, nil
}

func readOSRelease(fs afero.Fs) map[string]string {
	values := make(map[string]string)

	file, err := fs.Open("/etc/os-release")
	if err != nil {
		return values
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		parts := strings.SplitN(scanner.Text(), "=", 2)
		if len(parts) != 2 {
			continue
		}
		values[strings.TrimSpace(parts[0])] = strings.Trim(strings.TrimSpace(parts[1]), "\"'")
	}

	return values
}

func HasSystemd() bool {
	_, err := os.Stat("/run/systemd/system")
	return err == nil
}

// IsUnsupportedDistro checks if a distribution/version combination is supported
func IsUnsupportedDistro(distroID, versionID string) bool {
	if !IsDistroSupported(distroID) {
		return true
	}

	if distroID == "ubuntu" {
		parts := strings.Split(versionID, ".")
		if len(parts) >= 2 {
			major, err1 := strconv.Atoi(parts[0])
			minor, err2 := strconv.Atoi(parts[1])

			if err1 == nil && err2 == nil {
				return major < 25 || (major == 25 && minor < 4)
			}
		}
		return true
	}

	if IsEnterpriseLinux(distroID) {
		major, err := strconv.Atoi(strings.SplitN(versionID, ".", 2)[0])
		return err != nil || major < 10
	}

	if distroID == "debian" {
		// unstable/sid support
		if versionID == "sid" || versionID == "testing" {
			return false
		}
		if versionID == "" {
			// debian testing/sid have no version ID
			return false
		}
		versionNum, err := strconv.Atoi(versionID)
		if err == nil {
			return versionNum < 12
		}
		return true
	}

	return false
}
