# Shared helpers for scripts/*.sh: one output style, and commands whose full
# output goes to build/logs/ and is shown only when they fail.
#
# Source it from the repository root:  source scripts/lib.sh

LOG_DIR="build/logs"

step() { printf '\n▶ %s\n' "$*"; }
ok()   { printf '✓ %s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
fail() { printf '\n✗ %s\n' "$*" >&2; exit 1; }

# need TOOL HOW-TO-INSTALL
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 is missing: $2"; }

# run NAME CMD... : runs CMD with its output in build/logs/NAME.log. On failure,
# prints the error lines (or the end of the log) and stops the script.
run() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  mkdir -p "$LOG_DIR"
  "$@" >"$log" 2>&1 && return 0
  echo >&2
  if grep -qE 'error:|Error:' "$log"; then
    grep -E 'error:|Error:' "$log" | awk '!seen[$0]++' | head -20 | sed 's/^/  /' >&2
  else
    tail -20 "$log" | sed 's/^/  /' >&2
  fi
  fail "$name failed. Full log: $log"
}

# app_version APP : CFBundleShortVersionString of an .app bundle.
app_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null \
    || fail "cannot read the version of $1"
}

# dmg_path APP : where the DMG for that app goes.
dmg_path() { printf 'dist/LiveLoop-%s.dmg' "$(app_version "$1")"; }
