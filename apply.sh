#!/usr/bin/env bash
# Apply this repo's customizations to the current Omarchy machine (repo → machine).
#
#   ./apply.sh --dry-run        show what would be copied, change nothing
#   ./apply.sh                  copy user-level files (asks once before writing)
#   ./apply.sh --yes            same, no prompt
#   ./apply.sh --system         also install the udev rules (needs sudo)
#   ./apply.sh --skip-monitors  leave monitors.lua / grid.json / monitor-workspaces.json alone
#   ./apply.sh --no-restart     do not reload Hyprland or restart the Omarchy shell afterwards
#
# Existing targets are backed up to ~/.local/state/col-omarchy/backup-<timestamp>/ first.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dry=0 yes=0 system=0 skip_monitors=0 restart=1
while (( $# )); do
  case $1 in
    --dry-run) dry=1 ;;
    --yes|-y) yes=1 ;;
    --system) system=1 ;;
    --skip-monitors) skip_monitors=1 ;;
    --no-restart) restart=0 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- preflight
command -v rsync >/dev/null || die "rsync is required (pacman -S rsync)"
command -v python3 >/dev/null || warn "python3 missing: omarchy-grid and several plugin helpers need it"
if ! command -v omarchy >/dev/null; then
  warn "this does not look like an Omarchy machine (no 'omarchy' command); continuing anyway"
fi

monitor_specific() {
  case $1 in
    .config/hypr/monitors.lua|.config/omarchy/grid.json|.config/omarchy/monitor-workspaces.json) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------- plan
declare -a plan_kind plan_path
while IFS=$'\t' read -r kind path; do
  [[ $kind == system ]] && (( ! system )) && continue
  if (( skip_monitors )) && monitor_specific "$path"; then
    info "skipping (--skip-monitors): $path"
    continue
  fi
  src=$(repo_path "$kind" "$path")
  [[ -e $src ]] || { warn "not in repo, skipped: $path"; continue; }
  plan_kind+=("$kind"); plan_path+=("$path")
done < <(read_manifest)

info "will apply ${#plan_kind[@]} entries from $REPO to $HOME$( (( system )) && printf ' and /etc')"
for i in "${!plan_path[@]}"; do printf '   %-6s %s\n' "${plan_kind[$i]}" "${plan_path[$i]}"; done
(( system )) || info "udev rules not installed (add --system for a75/mouse hidraw access)"

if (( dry )); then
  info "dry run: rsync preview"
  for i in "${!plan_path[@]}"; do
    [[ ${plan_kind[$i]} == home ]] || continue
    sync_entry "$(repo_path home "${plan_path[$i]}")" "$(live_path home "${plan_path[$i]}")" 1 | sed 's/^/   /'
  done
  exit 0
fi

if (( ! yes )); then
  read -r -p "Proceed? [y/N] " answer
  [[ $answer == [yY]* ]] || { info "aborted"; exit 0; }
fi

# ---------------------------------------------------------------- backup
backup="${XDG_STATE_HOME:-$HOME/.local/state}/col-omarchy/backup-$(date +%Y%m%d-%H%M%S)"
backed=0
for i in "${!plan_path[@]}"; do
  [[ ${plan_kind[$i]} == home ]] || continue
  target=$(live_path home "${plan_path[$i]}")
  [[ -e $target ]] || continue
  mkdir -p "$backup/$(dirname "${plan_path[$i]}")"
  cp -a "${target%/}" "$backup/${plan_path[$i]%/}"
  backed=1
done
(( backed )) && info "existing files backed up to $backup"

# ---------------------------------------------------------------- copy home/
for i in "${!plan_path[@]}"; do
  [[ ${plan_kind[$i]} == home ]] || continue
  sync_entry "$(repo_path home "${plan_path[$i]}")" "$(live_path home "${plan_path[$i]}")"
done

# Paths that cannot use ~ (desktop Exec lines, shell.json) carry the source
# machine's home literally; rewrite them for this account.
if [[ $HOME != "$SOURCE_HOME" ]]; then
  rewritten=0
  for i in "${!plan_path[@]}"; do
    [[ ${plan_kind[$i]} == home ]] || continue
    target=$(live_path home "${plan_path[$i]}")
    while IFS= read -r -d '' f; do
      sed -i "s|$SOURCE_HOME|$HOME|g" "$f"
      rewritten=$((rewritten + 1))
    done < <(grep -rIlZ --fixed-strings "$SOURCE_HOME" "${target%/}" 2>/dev/null || true)
  done
  (( rewritten )) && info "rewrote $SOURCE_HOME -> $HOME in $rewritten file(s)"
fi

# Executable bits: rsync preserves them, but be explicit for the helpers.
chmod +x "$HOME"/.local/bin/omarchy-grid "$HOME"/.local/bin/omarchy-monitor-workspace 2>/dev/null || true
find "$HOME/.config/omarchy/plugins" -path '*/bin/*' -type f -exec chmod +x {} + 2>/dev/null || true
chmod +x "$HOME"/.claude/hooks/* "$HOME"/.claude/pilotfish-roles.sh 2>/dev/null || true

# Claude skills are symlinks into the Omarchy package, not copied files.
skills_src=/usr/share/omarchy/default/agents/skills
if [[ -d $skills_src ]]; then
  mkdir -p "$HOME/.claude/skills"
  for s in omarchy diagnose-crash; do
    [[ -d $skills_src/$s ]] && ln -sfn "$skills_src/$s" "$HOME/.claude/skills/$s"
  done
  info "linked Claude skills from $skills_src"
fi

# ---------------------------------------------------------------- system/
if (( system )); then
  info "installing udev rules (sudo)"
  for i in "${!plan_path[@]}"; do
    [[ ${plan_kind[$i]} == system ]] || continue
    sudo install -D -m 0644 "$(repo_path system "${plan_path[$i]}")" "${plan_path[$i]}"
  done
  sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=hidraw || warn "udev reload failed"
fi

# ---------------------------------------------------------------- post
command -v fc-cache >/dev/null && fc-cache -f >/dev/null && info "font cache refreshed"
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

if command -v claude >/dev/null && [[ -f $HOME/.claude/plugins/known_marketplaces.json ]]; then
  info "registering Claude Code plugin marketplaces and plugins (best effort)"
  python3 - "$HOME/.claude/plugins" <<'PY' | while read -r cmd; do claude plugin $cmd >/dev/null 2>&1 || warn "claude plugin $cmd failed"; done
import json, sys, os
d = sys.argv[1]
mk = json.load(open(os.path.join(d, "known_marketplaces.json")))
for name, m in mk.items():
    if m.get("source") == "github" and m.get("repo"):
        print("marketplace add " + m["repo"])
inst = json.load(open(os.path.join(d, "installed_plugins.json")))
for name in (inst.get("plugins") or inst):
    print("install " + name)
PY
fi

if (( restart )); then
  command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1 && info "Hyprland reloaded"
  command -v omarchy >/dev/null && omarchy restart shell >/dev/null 2>&1 && info "Omarchy shell restarted"
fi

cat <<'TXT'

Review on a new machine
  - Monitor names DP-1 / DP-2 / HDMI-A-1 are hard-coded in .config/hypr/monitors.lua,
    .config/hypr/bindings.lua (workspace_bases), .config/omarchy/shell.json (hideOnMonitors,
    notifications.monitors), grid.json and monitor-workspaces.json. Edit them for your outputs
    or re-run with --skip-monitors and keep Omarchy's monitor defaults.
  - user.flac in shell.json points at a Focal Bathys DAC (alsaDevice, pwDeviceName) and a
    music library path; user.torrent downloads to ~/Downloads/Torrents.
  - Packages the config expects but this script does not install: brave-bin, tidal-hifi-bin,
    transmission-cli, libldac, libfreeaptx, typora, docker (devsrv), plus the VGN A75 keyboard
    and Razer mouse hardware for those two bar widgets (harmless when absent).
  - Root step: ./apply.sh --system installs /etc/udev/rules.d/60-omarchy-{a75,mouse}-hidraw.rules.
  - Claude Code: run `claude` once to sign in; credentials are never part of this repo.
TXT
info "done"
