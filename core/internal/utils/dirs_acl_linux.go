//go:build linux

package utils

import "golang.org/x/sys/unix"

var dirACLXattrs = []string{"system.posix_acl_access", "system.posix_acl_default"}

func copyDirACL(src, dst string) {
	for _, name := range dirACLXattrs {
		value, ok := readXattr(src, name)
		if !ok {
			continue
		}
		if _, exists := readXattr(dst, name); exists {
			continue
		}
		_ = unix.Setxattr(dst, name, value, 0)
	}
}

func readXattr(path, name string) ([]byte, bool) {
	size, err := unix.Getxattr(path, name, nil)
	if err != nil || size <= 0 {
		return nil, false
	}
	buf := make([]byte, size)
	n, err := unix.Getxattr(path, name, buf)
	if err != nil {
		return nil, false
	}
	return buf[:n], true
}
