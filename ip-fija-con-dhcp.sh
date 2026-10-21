#!/usr/bin/env bash
# Keep a fixed public IP reachable while the interface runs on DHCP.
#
# Why: on some networks (the UNC one, for instance) a VPN port is blocked from the fixed-IP profile
# but allowed on DHCP. This script leaves the NetworkManager profile on DHCP and adds the fixed IP as
# a second address, with a policy rule so that traffic from the fixed IP is answered through the
# fixed IP's own gateway. Everything else (the VPN included) goes out by DHCP.
#
# Usage:
#   ip-fija-con-dhcp.sh [options] apply     # write it into the NetworkManager profile and reactivate it
#   ip-fija-con-dhcp.sh [options] remove    # take it out of the profile and reactivate it
#   ip-fija-con-dhcp.sh [options] status    # show what is configured and what the kernel has
#   ip-fija-con-dhcp.sh [options] test      # temporary: same thing with `ip` only, lost on reconnect
#   ip-fija-con-dhcp.sh [options] untest    # undo `test`
# Options (they override the config file):
#   -f FILE     config file   (default ${XDG_CONFIG_HOME:-~/.config}/maquina/ip-fija.conf, if present)
#   -a IP/LEN   fixed address              (required for apply and test)
#   -g GW       fixed address's gateway    (required for apply and test)
#   -d DEV      interface                  (default: the one with the default route)
#   -t TABLE    routing table number       (default: 100)
#   -c NAME     NetworkManager profile     (default: the active one on DEV)
#   -n          dry run: print the commands, change nothing
# The config file is bash with the same names: ADDR=, GW=, DEV=, TABLE=, CON= (see ip-fija.conf.example).
# For status and remove, a missing address and gateway are read from the profile, if apply put them there.
#
# Run `apply` and `remove` from the local console, not over ssh to the fixed IP: reactivating the
# profile drops the connection for a few seconds.

set -euo pipefail

usage() { sed -n '2,27p' "$0"; exit "${1:-0}"; }

CONF=${XDG_CONFIG_HOME:-$HOME/.config}/maquina/ip-fija.conf
ADDR= GW= DEV= TABLE= CON= DRY=0
declare -A opt_set=()

while getopts "f:a:g:d:t:c:nh" opt; do
    case $opt in
        f) CONF=$OPTARG; [[ -r $CONF ]] || { echo "cannot read $CONF" >&2; exit 2; } ;;
        a|g|d|t|c) opt_set[$opt]=$OPTARG ;;
        n) DRY=1 ;;
        h) usage 0 ;;
        *) usage 2 ;;
    esac
done
shift $((OPTIND - 1))
ACTION=${1:-status}

# config file first, then the command line wins
if [[ -r $CONF ]]; then
    # shellcheck source=/dev/null
    source "$CONF"
fi
ADDR=${opt_set[a]:-$ADDR}
GW=${opt_set[g]:-$GW}
DEV=${opt_set[d]:-$DEV}
TABLE=${opt_set[t]:-${TABLE:-100}}
CON=${opt_set[c]:-$CON}

if [[ -z $DEV ]]; then
    DEV=$(ip -4 route show default | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
    [[ -n $DEV ]] || { echo "no default route to take the interface from; use -d DEV" >&2; exit 1; }
fi

run() {
    echo "+ $*"
    if (( ! DRY )); then "$@"; fi
}

profile() {
    if [[ -z $CON ]]; then
        CON=$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="$DEV" '$2 == d { print $1; exit }')
        [[ -n $CON ]] || { echo "no active NetworkManager profile on $DEV; use -c NAME" >&2; exit 1; }
    fi
    local method
    method=$(nmcli -g ipv4.method con show "$CON")
    if [[ $method != auto ]]; then
        echo "profile '$CON' has ipv4.method=$method, not auto (DHCP): switch it to DHCP first" >&2
        exit 1
    fi
}

# Fill ADDR and GW from what apply left in the profile (for status and remove)
from_profile() {
    local addrs routes
    if [[ -z $ADDR ]]; then
        addrs=$(nmcli -g ipv4.addresses con show "$CON" | tr ',' '\n' | sed 's/^ *//')
        if (( $(grep -c . <<< "$addrs") > 1 )); then
            echo "profile '$CON' has several addresses; use -a" >&2; exit 1
        fi
        ADDR=$addrs
    fi
    if [[ -z $GW ]]; then
        routes=$(nmcli -g ipv4.routes con show "$CON" | tr ',' '\n')
        GW=$(awk -v t="table=$TABLE" '$1 == "0.0.0.0/0" && index($0, t) { print $2; exit }' <<< "$routes")
    fi
}

need() {
    [[ -n $ADDR && -n $GW ]] || {
        echo "$ACTION needs the fixed address and its gateway: -a IP/LEN -g GW, or ADDR= and GW= in $CONF" >&2
        exit 2
    }
    [[ $ADDR == */* ]] || { echo "address needs a prefix length: $ADDR" >&2; exit 2; }
    IP=${ADDR%/*}
    # network of ADDR, e.g. 192.0.2.0/24
    NET=$(python3 -c "import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)" "$ADDR")
    PRIO=$TABLE
    ROUTE_NET="$NET table=$TABLE src=$IP"
    ROUTE_DEF="0.0.0.0/0 $GW table=$TABLE"
    RULE="priority $PRIO from $IP table $TABLE"
}

case $ACTION in
    apply)
        profile; need
        if nmcli -g ipv4.addresses con show "$CON" | tr ',' '\n' | grep -qx " *$ADDR"; then
            echo "profile '$CON' already has $ADDR; nothing to do (use remove first to change it)"
            exit 0
        fi
        # leftovers of `test` would clash with what NetworkManager adds
        run sudo ip rule del from "$IP" table "$TABLE" 2>/dev/null || true
        run sudo ip route flush table "$TABLE" 2>/dev/null || true
        run sudo ip addr del "$ADDR" dev "$DEV" 2>/dev/null || true
        run sudo nmcli con mod "$CON" \
            +ipv4.addresses "$ADDR" \
            +ipv4.routes "$ROUTE_NET" \
            +ipv4.routes "$ROUTE_DEF" \
            +ipv4.routing-rules "$RULE"
        run sudo nmcli con up "$CON"
        ;;
    remove)
        profile; from_profile; need
        run sudo nmcli con mod "$CON" \
            -ipv4.addresses "$ADDR" \
            -ipv4.routes "$ROUTE_NET" \
            -ipv4.routes "$ROUTE_DEF" \
            -ipv4.routing-rules "$RULE"
        run sudo nmcli con up "$CON"
        ;;
    test)
        need
        if ip -4 addr show "$DEV" | grep -qF " $ADDR "; then
            echo "$DEV already has $ADDR (from apply or an earlier test): see status" >&2
            exit 1
        fi
        run sudo ip addr add "$ADDR" dev "$DEV"
        run sudo ip route add "$NET" dev "$DEV" src "$IP" table "$TABLE"
        run sudo ip route add default via "$GW" dev "$DEV" table "$TABLE"
        run sudo ip rule add from "$IP" table "$TABLE" priority "$PRIO"
        ;;
    untest)
        need
        # undo every step, even if an earlier one finds nothing to undo
        run sudo ip rule del from "$IP" table "$TABLE" || true
        run sudo ip route flush table "$TABLE" || true
        run sudo ip addr del "$ADDR" dev "$DEV" || true
        ;;
    status)
        profile; from_profile
        echo "profile: $CON (ipv4.method auto) on $DEV"
        echo "  addresses:     $(nmcli -g ipv4.addresses con show "$CON")"
        echo "  routes:        $(nmcli -g ipv4.routes con show "$CON")"
        echo "  routing-rules: $(nmcli -g ipv4.routing-rules con show "$CON")"
        echo "kernel:"
        ip -4 addr show "$DEV" | sed 's/^/  /'
        if [[ -n $ADDR ]]; then
            IP=${ADDR%/*}
            ip rule | grep -F "from $IP" | sed 's/^/  rule: /' || echo "  rule: none from $IP"
        else
            echo "  rule: no fixed address configured"
        fi
        ip route show table "$TABLE" 2>/dev/null | sed 's/^/  table '"$TABLE"': /' || echo "  table $TABLE: empty"
        ;;
    *)
        echo "unknown action: $ACTION (apply, remove, status, test, untest)" >&2
        exit 2
        ;;
esac

if [[ $ACTION != status && $DRY == 0 ]]; then
    cat <<EOF

Check:
  ping -c 3 -I $IP $GW
  curl -s --interface $IP http://portquiz.net/ | grep -i "your ip"
  then ssh to $IP from outside, with and without the VPN up.
EOF
fi
