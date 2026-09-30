#!/usr/bin/env bash
# Reapply chosen pilotfish role->model assignments.
#
# pilotfish ships its agents inside the plugin cache, which is version-pinned
# (…/pilotfish/<version>/agents). `claude plugin update` creates a NEW version
# directory, so these edits do not survive an update — re-run this script after
# updating. Roles not listed keep whatever the plugin shipped.
set -euo pipefail

declare -A ROLES=(
  [scout]=haiku
  [mech-executor]=opus
  [executor]=opus
  [plan-verifier]=fable
  [verifier]=fable
  [security-reviewer]=opus
  [security-executor]=opus
)

base="$HOME/.claude/plugins/cache/pilotfish/pilotfish"
[[ -d $base ]] || { echo "pilotfish not installed at $base" >&2; exit 1; }

# Newest version directory that actually contains agents/
dir=$(find "$base" -maxdepth 2 -type d -name agents | sort -V | tail -1)
[[ -n $dir ]] || { echo "no agents/ directory found under $base" >&2; exit 1; }
echo "Applying to: $dir"

for role in "${!ROLES[@]}"; do
  f="$dir/$role.md"
  want="${ROLES[$role]}"
  [[ -f $f ]] || { echo "  ! $role.md missing, skipped"; continue; }
  cur=$(awk -F': *' '/^model:/{print $2; exit}' "$f")
  if [[ $cur == "$want" ]]; then
    echo "  = $role: $want"
  else
    # Only the frontmatter model: line (the first one in the file).
    awk -v m="$want" '!d && /^model:/ {sub(/^model:.*/, "model: " m); d=1} 1' "$f" > "$f.tmp" \
      && mv "$f.tmp" "$f"
    echo "  ~ $role: $cur -> $want"
  fi
done
