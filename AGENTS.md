# maquina — working notes

What the repo is: README.md. Part of the `~/work/rc` group (see its AGENTS.md).

- Never run anything here that changes the machine (`apply`, `remove`, `test`,
  `untest`, or any `sudo`): only `-n` dry runs and `status`, which read.
- No personal data in this repo (Alexis 2026-10-20: rc must be shareable).
  Real values go in the private repo `~/work/rc/privado`.

## State

- `ip-fija-con-dhcp.sh`: from coord's `/home/claude/coord/clementina/` (task
  rc-3, Alexis 2026-10-20 "El script pasaselo a rc"). Applied by hand on the desktop
  before it came here; this copy takes its values from options or
  `~/.config/maquina/ip-fija.conf` instead of hard-coded defaults, finds the
  interface from the default route, and for status/remove reads the address
  and gateway back from the profile. Dry runs there give the same commands
  as the original for apply, remove, test and untest.
- `openfortivpn.sh` (branch `claude/vpn`, Alexis 2026-10-21 "si, lo vamos a
  hacer asi"): installs the package and copies the config to /etc. Tested only
  with stub sudo/pacman/install and a scratch target (scratchpad `vpn/`):
  fresh install, rerun, different config with and without -F, missing config;
  a password line is never printed. Never run for real here.
