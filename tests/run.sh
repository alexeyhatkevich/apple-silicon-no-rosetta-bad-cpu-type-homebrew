#!/usr/bin/env bash
# Plain-shell tests for doctor.sh. Fixtures are built per run, nothing touches the real system.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
DOCTOR="$HERE/../doctor.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   - $1"; }
bad()  { fail=$((fail+1)); echo "FAIL - $1"; }
assert_contains() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 (missing: $3)"; echo "$2";; esac; }
assert_not_contains() { case "$2" in *"$3"*) bad "$1 (unexpected: $3)";; *) ok "$1";; esac; }

# Fake `file`: prints the first line of the fixture as its description.
cat > "$TMP/fake-file" <<'EOS'
#!/bin/sh
for last; do :; done
head -n 1 "$last" | sed "s|^|$last: |"
EOS
chmod +x "$TMP/fake-file"

mk() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; chmod +x "$1"; }
INTEL=$TMP/intel/bin; ARM=$TMP/arm
mk "$INTEL/node" "Mach-O 64-bit executable x86_64"
mk "$INTEL/wget" "Mach-O universal binary with 2 architectures: [x86_64] [arm64]"
mk "$INTEL/script.sh" "POSIX shell script text executable"
mk "$ARM/bin/node" "Mach-O 64-bit executable arm64"

run() { ROOT="$INTEL" ARM_PREFIX="$ARM" FILE_CMD="$TMP/fake-file" ROSETTA_PROBE="$1" PATH="$2" "$DOCTOR"; }

# test_naive_x86_only_binary_is_reported_when_rosetta_is_missing
out=$(run false "$INTEL:$ARM/bin:/usr/bin:/bin"); code=$?
assert_contains "test_doctor_flags_x86_64_only_binary" "$out" "- node"
assert_contains "test_doctor_reports_missing_rosetta" "$out" "rosetta: NOT available"
[ $code -eq 1 ] && ok "test_doctor_exits_1_when_stale_found" || bad "test_doctor_exits_1_when_stale_found"

# universal binaries and scripts are not stale
assert_not_contains "test_universal_binary_is_not_flagged" "$out" "- wget"
assert_not_contains "test_shell_script_is_not_flagged" "$out" "- script.sh"

# PATH order: the stale directory first means shadowing
assert_contains "test_shadowing_reported_when_intel_dir_first" "$out" "shadowing"
out=$(run false "$ARM/bin:$INTEL:/usr/bin:/bin")
assert_not_contains "test_no_shadowing_when_arm_dir_first" "$out" "shadowing"

# suggestion points at the arm64 replacement
assert_contains "test_suggests_relink_to_arm64_binary" "$out" "ln -sf $ARM/bin/node $INTEL/node"
rm "$ARM/bin/node"
out=$(run false "$INTEL:/usr/bin:/bin")
assert_contains "test_suggests_brew_install_when_no_replacement" "$out" "$ARM/bin/brew install node"

# Rosetta present
out=$(run true "$INTEL:/usr/bin:/bin")
assert_contains "test_reports_rosetta_available" "$out" "rosetta: available"

# clean root
mkdir -p "$TMP/clean"; mk "$TMP/clean/tool" "Mach-O 64-bit executable arm64"
out=$(ROOT="$TMP/clean" FILE_CMD="$TMP/fake-file" ROSETTA_PROBE=false "$DOCTOR"); code=$?
[ $code -eq 0 ] && ok "test_clean_root_exits_0" || bad "test_clean_root_exits_0"

# Real binaries with real `file` (macOS with clang only)
if [ "$(uname)" = Darwin ] && command -v clang >/dev/null; then
  echo 'int main(void){return 0;}' > "$TMP/m.c"
  mkdir -p "$TMP/real"
  clang -arch x86_64 "$TMP/m.c" -o "$TMP/real/intel-tool" 2>/dev/null
  clang -arch arm64 "$TMP/m.c" -o "$TMP/real/arm-tool" 2>/dev/null
  clang -arch x86_64 -arch arm64 "$TMP/m.c" -o "$TMP/real/fat-tool" 2>/dev/null
  out=$(ROOT="$TMP/real" ARM_PREFIX="$TMP/none" ROSETTA_PROBE=false "$DOCTOR")
  assert_contains "test_real_x86_64_macho_is_flagged" "$out" "- intel-tool"
  assert_not_contains "test_real_arm64_macho_is_not_flagged" "$out" "- arm-tool"
  assert_not_contains "test_real_universal_macho_is_not_flagged" "$out" "- fat-tool"
fi

echo "passed=$pass failed=$fail"
[ $fail -eq 0 ]
