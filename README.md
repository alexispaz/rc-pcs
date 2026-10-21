# maquina

Machine setup that needs root: scripts you run once (with sudo inside) to
configure a computer, kept apart from the dotfiles.

Nothing here holds personal data. Every machine-specific value (addresses,
interfaces, host names) is an option or comes from a config file under
`~/.config/maquina/`; the `*.example` files show the format with placeholder
values.

## Scripts

### `ip-fija-con-dhcp.sh`

Keeps a fixed public IP reachable while the interface runs on DHCP: the
NetworkManager profile stays on DHCP and the fixed IP is added as a second
address, with its own routing table and rule, so that what arrives at the fixed
IP is answered through its own gateway. Useful when a network blocks something
(a VPN port, for instance) on the fixed-IP profile but allows it on DHCP.

    cp ip-fija.conf.example ~/.config/maquina/ip-fija.conf   # then edit it
    ./ip-fija-con-dhcp.sh status
    ./ip-fija-con-dhcp.sh -n apply      # print the commands, change nothing
    ./ip-fija-con-dhcp.sh apply         # from the local console, not over ssh

`test` / `untest` do the same with `ip` alone, lost on the next reconnect.
`./ip-fija-con-dhcp.sh -h` lists the options.

Requires NetworkManager (`nmcli`), iproute2, python3 and sudo.
