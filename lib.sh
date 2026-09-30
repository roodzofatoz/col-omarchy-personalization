#!/usr/bin/env bash
# Shared helpers for sync.sh and apply.sh. Sourced, not executed.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO/manifest.txt"
EXCLUDES="$REPO/rsync-exclude.txt"
# Home directory the tracked files were exported from. apply.sh rewrites this
# literal in text files when the target machine's $HOME differs (e.g. .desktop
# Exec lines and shell.json paths cannot use ~ or $HOME).
SOURCE_HOME="/home/user"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Emits "kind<TAB>path" for every non-comment manifest line.
read_manifest() {
  [[ -f $MANIFEST ]] || die "manifest not found: $MANIFEST"
  local kind path
  while read -r kind path _; do
    [[ -z $kind || $kind == \#* ]] && continue
    [[ $kind == home || $kind == system ]] || die "manifest: unknown kind '$kind' for $path"
    printf '%s\t%s\n' "$kind" "$path"
  done < "$MANIFEST"
}

# Live (machine) location of a manifest entry.
live_path() {
  local kind=$1 path=$2
  case $kind in
    home)   printf '%s/%s' "$HOME" "$path" ;;
    system) printf '%s' "$path" ;;
  esac
}

# Repo location of a manifest entry.
repo_path() {
  local kind=$1 path=$2
  case $kind in
    home)   printf '%s/home/%s' "$REPO" "$path" ;;
    system) printf '%s/system%s' "$REPO" "$path" ;;
  esac
}

is_dir_entry() { [[ $1 == */ ]]; }

# rsync one entry from $1 to $2 (both already resolved). Directories get
# --delete so removed files disappear on the other side; excluded patterns
# are never deleted (no --delete-excluded), so a plugin's local .git survives.
sync_entry() {
  local src=$1 dst=$2 dry=${3:-0}
  local -a opts=(-a)
  (( dry )) && opts+=(-n -v)
  if is_dir_entry "$src"; then
    mkdir -p "$dst"
    rsync "${opts[@]}" --delete --exclude-from="$EXCLUDES" "$src" "$dst"
  else
    mkdir -p "$(dirname "$dst")"
    rsync "${opts[@]}" "$src" "$dst"
  fi
}
