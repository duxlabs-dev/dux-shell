#!/bin/sh
# Rejects the config when the -c file, a file it includes, or any .kdl under
# $HOME/.config/niri contains BAD. FAKE_NIRI_OLD mimics a niri without "validate -c".
# FAKE_NIRI_PATHS first prints the path of the file holding BAD.
[ "$1" = validate ] && [ "$2" = -c ] && [ -n "$3" ] && [ -z "$FAKE_NIRI_OLD" ] || exit 2

cfg=$3
set --
while IFS= read -r f; do
	[ -n "$f" ] && set -- "$@" "$f"
done <<EOF
$(find "$HOME/.config/niri" -name '*.kdl' 2>/dev/null)
EOF
while IFS= read -r inc; do
	[ -n "$inc" ] || continue
	case $inc in
	\~/*) inc="$HOME/${inc#\~/}" ;;
	/*) ;;
	*) inc="$(dirname "$cfg")/$inc" ;;
	esac
	set -- "$@" "$inc"
done <<EOF
$(sed -n 's/^[[:space:]]*include[^"]*"\([^"]*\)".*/\1/p' "$cfg")
EOF

if grep -qs BAD "$cfg" "$@"; then
	[ -n "$FAKE_NIRI_PATHS" ] && grep -ls BAD "$cfg" "$@" | head -n 1
	echo "error: bad"
	exit 1
fi
echo ok
