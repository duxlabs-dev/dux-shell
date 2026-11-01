package niriconf

import (
	"errors"
	"regexp"
)

var ErrBadName = errors.New("bad fragment name")

var namePattern = regexp.MustCompile(`^[a-z0-9-]+\.kdl$`)

func validName(name string) bool {
	return namePattern.MatchString(name)
}
