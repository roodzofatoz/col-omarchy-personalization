#!/usr/bin/env bash
# Export this machine's tracked customizations into the repo (machine → repo).
#
#   ./sync.sh                 copy live files into home/ and system/, show git status
#   ./sync.sh --commit "msg"  ...then commit everything
#   ./sync.sh --push          ...then push main to origin (implies nothing else)
#
# Nothing is committed or pushed unless asked. Review `git diff` first.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

commit_msg="" do_push=0
while (( $# )); do
  case $1 in
    --commit) commit_msg=${2:-}; [[ -n $commit_msg ]] || die "--commit needs a message"; shift 2 ;;
    --push)   do_push=1; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

command -v rsync >/dev/null || die "rsync is required"

missing=0
while IFS=$'\t' read -r kind path; do
  src=$(live_path "$kind" "$path")
  dst=$(repo_path "$kind" "$path")
  if [[ ! -e $src ]]; then
    warn "not on this machine, left untouched in repo: $src"
    missing=1
    continue
  fi
  sync_entry "$src" "$dst"
done < <(read_manifest)

info "repo updated from $HOME (source home recorded as $SOURCE_HOME)"
(( missing )) && warn "some manifest entries were missing locally; check manifest.txt"

cd "$REPO"
if [[ -n $(git status --porcelain) ]]; then
  info "changes:"
  git status --short
else
  info "repo already matches this machine"
fi

if [[ -n $commit_msg ]]; then
  git add -A
  git commit -q -m "$commit_msg" && info "committed: $commit_msg"
fi
if (( do_push )); then
  git push -u origin main && info "pushed main to origin"
fi
