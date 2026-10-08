#!/usr/bin/env bash
# doctor.sh - find x86_64-only binaries that cannot run on Apple Silicon without Rosetta 2.
#
# Configuration (all optional, mainly for tests):
#   ROOT           directory to scan                  (default /usr/local/bin)
#   ARM_PREFIX     arm64 Homebrew prefix              (default /opt/homebrew)
#   FILE_CMD       command used instead of `file`     (default file)
#   ROSETTA_PROBE  command that succeeds if Rosetta runs x86_64 code
#                  (default: /usr/bin/arch -x86_64 /usr/bin/true)
# Exit code: 0 = nothing stale, 1 = stale x86_64-only binaries found.

ROOT="${ROOT:-/usr/local/bin}"
ARM_PREFIX="${ARM_PREFIX:-/opt/homebrew}"
FILE_CMD="${FILE_CMD:-file}"
ROSETTA_PROBE="${ROSETTA_PROBE:-/usr/bin/arch -x86_64 /usr/bin/true}"

echo "machine: ${DOCTOR_UNAME:-$(uname -m)}"

rosetta=no
if $ROSETTA_PROBE >/dev/null 2>&1; then rosetta=yes; fi
if [ "$rosetta" = yes ]; then
  echo "rosetta: available"
else
  echo "rosetta: NOT available (x86_64 binaries fail with 'Bad CPU type in executable')"
fi

# Index of the first PATH entry equal to $1, or -1.
path_index() {
  local i=0 entry
  local IFS=:
  for entry in $PATH; do
    if [ "$entry" = "$1" ]; then echo "$i"; return; fi
    i=$((i + 1))
  done
  echo -1
}

stale=()
for f in "$ROOT"/*; do
  [ -e "$f" ] || continue
  [ -d "$f" ] && continue
  info=$($FILE_CMD -L "$f" 2>/dev/null)
  case "$info" in
    *Mach-O*) ;;
    *) continue ;;
  esac
  # x86_64 only: mentions x86_64 and has no arm64 slice (universal binaries are fine)
  case "$info" in
    *arm64*) continue ;;
    *x86_64*) stale+=("$f") ;;
  esac
done

if [ ${#stale[@]} -eq 0 ]; then
  echo "ok: no x86_64-only binaries in $ROOT"
  exit 0
fi

echo "stale x86_64-only binaries in $ROOT: ${#stale[@]}"
old_idx=$(path_index "$ROOT")
new_idx=$(path_index "$ARM_PREFIX/bin")
for f in "${stale[@]}"; do
  name=$(basename "$f")
  echo "  - $name"
  if [ -x "$ARM_PREFIX/bin/$name" ]; then
    echo "      arm64 replacement exists: $ARM_PREFIX/bin/$name"
    echo "      fix: ln -sf $ARM_PREFIX/bin/$name $f"
  else
    echo "      fix: $ARM_PREFIX/bin/brew install $name   (then relink $f)"
  fi
  if [ "$old_idx" -ge 0 ] && { [ "$new_idx" -lt 0 ] || [ "$old_idx" -lt "$new_idx" ]; }; then
    echo "      shadowing: $ROOT comes BEFORE $ARM_PREFIX/bin in PATH, so the stale one wins"
  fi
done
echo "long-term: dump with 'brew bundle dump', remove the Intel Homebrew in /usr/local, put $ARM_PREFIX/bin first in ~/.zprofile"
exit 1
