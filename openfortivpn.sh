#!/usr/bin/env bash
# Install openfortivpn and its config, so that `sudo openfortivpn` connects with no arguments.
#
# The config is kept in the home, in openfortivpn's own format (see openfortivpn.conf.example), and
# copied to /etc/openfortivpn/config, the file `sudo openfortivpn` reads. Keep the password out of it:
# openfortivpn then asks for it when connecting.
#
# Usage:
#   openfortivpn.sh [options] install   # install the package if missing, then copy the config
#   openfortivpn.sh [options] status    # package installed? config in place and up to date?
# Options:
#   -f FILE     config to install  (default ${XDG_CONFIG_HOME:-~/.config}/maquina/openfortivpn.conf)
#   -t FILE     where it goes      (default /etc/openfortivpn/config)
#   -F          replace a different config already there (a copy is kept as FILE.bak)
#   -n          dry run: print the commands, change nothing
# Lines starting with `password` are never printed, and are ignored when comparing.
#
# Requires pacman (Arch) and sudo. Then connect with: sudo openfortivpn

set -euo pipefail

usage() { sed -n '2,18p' "$0"; exit "${1:-0}"; }

CONF=${XDG_CONFIG_HOME:-$HOME/.config}/maquina/openfortivpn.conf
TARGET=/etc/openfortivpn/config
FORCE=0 DRY=0

while getopts "f:t:Fnh" opt; do
    case $opt in
        f) CONF=$OPTARG ;;
        t) TARGET=$OPTARG ;;
        F) FORCE=1 ;;
        n) DRY=1 ;;
        h) usage 0 ;;
        *) usage 2 ;;
    esac
done
shift $((OPTIND - 1))
ACTION=${1:-status}

run() {
    echo "+ $*"
    if (( ! DRY )); then "$@"; fi
}

nopass() { grep -v -i '^[[:space:]]*password' || true; }

# The installed config is root's, mode 600: reading it takes sudo.
target_state() {
    if ! sudo test -e "$TARGET"; then
        echo missing
    elif diff -q <(sudo cat "$TARGET" | nopass) <(nopass < "$CONF") >/dev/null; then
        echo same
    else
        echo different
    fi
}

case $ACTION in
    status)
        if pacman -Q openfortivpn >/dev/null 2>&1; then
            echo "package: $(pacman -Q openfortivpn)"
        else
            echo "package: openfortivpn not installed"
        fi
        [[ -r $CONF ]] || { echo "config: $CONF not found"; exit 0; }
        case $(target_state) in
            missing)   echo "config: $TARGET missing" ;;
            same)      echo "config: $TARGET matches $CONF" ;;
            different) echo "config: $TARGET differs from $CONF (password lines not shown):"
                       diff <(sudo cat "$TARGET" | nopass) <(nopass < "$CONF") || true ;;
        esac
        if sudo grep -q -i '^[[:space:]]*password' "$TARGET" 2>/dev/null; then
            echo "note: $TARGET holds a password"
        fi
        ;;
    install)
        [[ -r $CONF ]] || { echo "cannot read $CONF (see openfortivpn.conf.example)" >&2; exit 2; }
        if grep -q -i '^[[:space:]]*password' "$CONF"; then
            echo "warning: $CONF holds a password; openfortivpn can ask for it instead" >&2
        fi
        pacman -Q openfortivpn >/dev/null 2>&1 || run sudo pacman -S --needed openfortivpn
        state=$(target_state)
        case $state in
            same)
                echo "$TARGET already matches $CONF"
                exit 0 ;;
            different)
                if (( ! FORCE )); then
                    echo "$TARGET differs from $CONF (password lines not shown):" >&2
                    diff <(sudo cat "$TARGET" | nopass) <(nopass < "$CONF") >&2 || true
                    echo "use -F to replace it (a copy is kept as $TARGET.bak)" >&2
                    exit 1
                fi
                run sudo cp -p "$TARGET" "$TARGET.bak" ;;
        esac
        run sudo install -D -m 600 -o root -g root "$CONF" "$TARGET"
        ;;
    *)
        usage 2 ;;
esac
