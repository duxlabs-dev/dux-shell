package backup

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const dirName = "dms"

func ConfigDir() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(configDir, dirName), nil
}

func DefaultArchiveName() string {
	return fmt.Sprintf("dms-backup-%s.tar.gz", time.Now().Format("20060102-150405"))
}

func Create(outputPath string) error {
	srcDir, err := ConfigDir()
	if err != nil {
		return err
	}
	if _, err := os.Stat(srcDir); err != nil {
		return fmt.Errorf("no DMS configuration found at %s: %w", srcDir, err)
	}

	return writeArchive(outputPath, func(tw *tar.Writer) error {
		return addPath(tw, srcDir, dirName)
	})
}

func writeArchive(outputPath string, fill func(*tar.Writer) error) error {
	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()

	gz := gzip.NewWriter(out)
	defer gz.Close()
	tw := tar.NewWriter(gz)
	defer tw.Close()

	return fill(tw)
}

// addPath archives the file or tree at src as name. A symlinked src is followed so dotfile-managed
// configs are captured, not just the link.
func addPath(tw *tar.Writer, src, name string) error {
	root, err := filepath.EvalSymlinks(src)
	if err != nil {
		return err
	}
	return filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}

		var link string
		if info.Mode()&os.ModeSymlink != 0 {
			if link, err = os.Readlink(path); err != nil {
				return err
			}
		}

		header, err := tar.FileInfoHeader(info, link)
		if err != nil {
			return err
		}
		header.Name = filepath.ToSlash(filepath.Join(name, rel))

		if err := tw.WriteHeader(header); err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return nil
		}

		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = io.Copy(tw, f)
		return err
	})
}

func Restore(archivePath string) (string, error) {
	dstDir, err := ConfigDir()
	if err != nil {
		return "", err
	}

	if err := validateArchive(archivePath); err != nil {
		return "", err
	}

	previous := ""
	if _, err := os.Stat(dstDir); err == nil {
		previous = dstDir + ".pre-restore-" + time.Now().Format("20060102-150405")
		if err := os.Rename(dstDir, previous); err != nil {
			return "", fmt.Errorf("failed to move existing configuration aside: %w", err)
		}
	}

	if err := extract(archivePath, filepath.Dir(dstDir)); err != nil {
		if previous != "" {
			os.RemoveAll(dstDir)
			os.Rename(previous, dstDir)
		}
		return "", err
	}
	return previous, nil
}

func validateArchive(archivePath string) error {
	hasSettings := false
	err := walkArchive(archivePath, func(header *tar.Header, _ *tar.Reader) error {
		name := filepath.ToSlash(filepath.Clean(header.Name))
		if strings.HasPrefix(name, "..") || filepath.IsAbs(header.Name) {
			return fmt.Errorf("unsafe path in archive: %s", header.Name)
		}
		if !strings.HasPrefix(name, dirName+"/") && name != dirName {
			return fmt.Errorf("not a DMS backup: unexpected entry %s", header.Name)
		}
		if name == dirName+"/settings.json" {
			hasSettings = true
		}
		return nil
	})
	if err != nil {
		return err
	}
	if !hasSettings {
		return fmt.Errorf("not a DMS backup: settings.json missing from archive")
	}
	return nil
}

func extract(archivePath, destParent string) error {
	return walkArchive(archivePath, func(header *tar.Header, tr *tar.Reader) error {
		target := filepath.Join(destParent, filepath.Clean(header.Name))

		switch header.Typeflag {
		case tar.TypeDir:
			return os.MkdirAll(target, os.FileMode(header.Mode))
		case tar.TypeSymlink:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			return os.Symlink(header.Linkname, target)
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			f, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(header.Mode))
			if err != nil {
				return err
			}
			defer f.Close()
			_, err = io.Copy(f, tr)
			return err
		default:
			return nil
		}
	})
}

func walkArchive(archivePath string, visit func(*tar.Header, *tar.Reader) error) error {
	f, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("not a gzip archive: %w", err)
	}
	defer gz.Close()

	tr := tar.NewReader(gz)
	for {
		header, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if err := visit(header, tr); err != nil {
			return err
		}
	}
}
