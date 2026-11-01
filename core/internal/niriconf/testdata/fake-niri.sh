#!/bin/sh
# Rejects the config when the -c file, a file it includes, or any .kdl under
# $HOME/.config/niri contains BAD. FAKE_NIRI_OLD mimics a niri without "validate -c".
# FAKE_NIRI_PATHS first prints the path of the file holding BAD.
[ "$1" = validate ] && [ "$2" = -c ] && [ -n "$3" ] && [ -z "$FAKE_NIRI_OLD" ] || exit 2

files=$(find "$HOME/.config/niri" -name '*.kdl' 2>/dev/null)
for inc in $(sed -n 's/^[[:space:]]*include[^"]*"\([^"]*\)".*/\1/p' "$3"); do
	case $inc in
	"~/"*) inc="$HOME/${inc#\~/}" ;;
	/*) ;;
	*) inc="$(dirname "$3")/$inc" ;;
	esac
	files="$files $inc"
done

if grep -qs BAD "$3" $files; then
	[ -n "$FAKE_NIRI_PATHS" ] && grep -ls BAD "$3" $files | head -n 1
	echo "error: bad"
	exit 1
fi
echo ok
