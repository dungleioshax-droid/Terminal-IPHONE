# NewTerm 3 AI — add the bundled Node.js runtime to PATH (POSIX sh).
# Sourced by jailbreak shell profiles; the package also ships symlinks in
# <root>/usr/bin, so this snippet is a best-effort extra for /usr/local/bin.
for _newterm_ai_bin in /var/jb/usr/local/bin /usr/local/bin; do
	if [ -x "$_newterm_ai_bin/aienv" ]; then
		case ":$PATH:" in
			*":$_newterm_ai_bin:"*) ;;
			*) PATH="$_newterm_ai_bin:$PATH" ;;
		esac
		break
	fi
done
unset _newterm_ai_bin
export PATH
