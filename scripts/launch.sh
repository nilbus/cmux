#!/usr/bin/env bash
set -euo pipefail

# Launch an already-built tagged Debug app. This script intentionally never
# invokes reload.sh, xcodebuild, zig, or any other build step.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/mobile-attach.sh
source "$SCRIPT_DIR/lib/mobile-attach.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/launch.sh --tag <name>

Launch an existing tagged Debug app without building it.
EOF
}

tag=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      tag="${2:-}"
      [[ -n "$tag" ]] || { echo "error: --tag requires a value" >&2; exit 1; }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unexpected argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "$tag" ]] || { echo "error: --tag is required" >&2; usage >&2; exit 1; }
cmux_attach_validate_dev_tag "$tag"
slug="$(cmux_attach__slug "$tag")"
bundle_id="$(cmux_attach_mac_bundle_id "$tag")"
app_path="$(cmux_attach_mac_app_path "$tag")"
if [[ ! -d "$app_path" && "$slug" == "nilbus" ]]; then
  # nilbus may have been renamed in a shared DerivedData root before its next
  # tagged rebuild. Find only a bundle whose plist proves the nilbus identity.
  while IFS= read -r candidate; do
    candidate_plist="$candidate/Contents/Info.plist"
    candidate_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate_plist" 2>/dev/null || true)"
    candidate_tag="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:CMUX_TAG' "$candidate_plist" 2>/dev/null || true)"
    if [[ "$candidate_id" == "$bundle_id" && "$candidate_tag" == "$slug" ]]; then
      app_path="$candidate"
      break
    fi
  done < <(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/cmux.app' -type d -print 2>/dev/null)
fi
executable="$app_path/Contents/MacOS/cmux DEV"
plist="$app_path/Contents/Info.plist"
socket_path="$(cmux_attach_socket_path "$tag")"
cmuxd_socket="$HOME/Library/Application Support/cmux/cmuxd-dev-${slug}.sock"
debug_log="/tmp/cmux-debug-${slug}.log"

[[ -d "$app_path" ]] || { echo "error: tagged app not found: $app_path" >&2; exit 1; }
[[ -x "$executable" ]] || { echo "error: tagged app executable not found: $executable" >&2; exit 1; }
[[ -f "$plist" ]] || { echo "error: tagged app Info.plist not found: $plist" >&2; exit 1; }
actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
[[ "$actual_bundle_id" == "$bundle_id" ]] || {
  echo "error: tagged app bundle ID mismatch: expected $bundle_id, found ${actual_bundle_id:-<missing>}" >&2
  exit 1
}
actual_tag="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:CMUX_TAG' "$plist" 2>/dev/null || true)"
[[ "$actual_tag" == "$slug" ]] || {
  echo "error: tagged app tag mismatch: expected $slug, found ${actual_tag:-<missing>}" >&2
  exit 1
}

# Stop only this exact bundle, then launch it directly so LaunchServices cannot
# reuse stale environment state for another bundle. The bundle-id lookup also
# handles a process whose executable was renamed in place (as with nilbus).
/usr/bin/osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
sleep 0.3
while IFS= read -r pid; do
  [[ -n "$pid" ]] || continue
  kill "$pid" 2>/dev/null || true
done < <(ps ax -o pid=,command= | awk -v exe="$executable" 'index($0, exe) { print $1 }')
sleep 0.3
for socket in "$socket_path" "$cmuxd_socket"; do
  if [[ -L "$socket" ]]; then
    echo "error: refusing to remove symlink at tagged socket path: $socket" >&2
    exit 1
  fi
  if [[ -e "$socket" && ! -S "$socket" ]]; then
    echo "error: refusing to remove non-socket at tagged socket path: $socket" >&2
    exit 1
  fi
done
rm -f -- "$socket_path" "$cmuxd_socket"

clean_env=(
  env
  -u CMUX_SOCKET_PATH -u CMUX_SOCKET_MODE -u CMUX_TAB_ID -u CMUX_PANEL_ID
  -u CMUX_SURFACE_ID -u CMUX_WORKSPACE_ID -u CMUXD_UNIX_PATH -u CMUX_TAG
  -u CMUX_PORT -u CMUX_PORT_END -u CMUX_PORT_RANGE -u CMUX_DEBUG_LOG
  -u CMUX_BUNDLE_ID -u CMUX_SHELL_INTEGRATION -u CMUX_SHELL_INTEGRATION_DIR
  -u CMUX_LOAD_GHOSTTY_ZSH_INTEGRATION -u GHOSTTY_BIN_DIR -u GHOSTTY_RESOURCES_DIR
  -u GHOSTTY_SHELL_FEATURES -u GIT_PAGER -u GH_PAGER -u TERMINFO -u XDG_DATA_DIRS
  "CMUX_TAG=$slug"
  "CMUX_BUNDLE_ID=$bundle_id"
  "CMUX_AUTH_CALLBACK_SCHEME=cmux-dev-$slug"
  "CMUX_SOCKET_ENABLE=1"
  "CMUX_SOCKET_MODE=allowAll"
  "CMUX_SOCKET_PATH=$socket_path"
  "CMUXD_UNIX_PATH=$cmuxd_socket"
  "CMUX_DEBUG_LOG=$debug_log"
  "CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1"
  "CMUXTERM_REPO_ROOT=$SCRIPT_DIR/.."
  "CMUX_BUNDLED_CLI_PATH=$app_path/Contents/Resources/bin/cmux"
  "CMUX_SHELL_INTEGRATION_DIR=$app_path/Contents/Resources/shell-integration"
)
# Preserve the build's remaining non-secret runtime settings, including local
# auth origins and the selected dev port, without inheriting caller state.
for key in CMUX_PORT CMUX_PORT_END CMUX_PORT_RANGE PORT CMUX_AUTH_WWW_ORIGIN CMUX_WWW_ORIGIN CMUX_API_BASE_URL CMUX_VM_API_BASE_URL CMUX_IROH_BROKER_BASE_URL CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD; do
  value="$(/usr/libexec/PlistBuddy -c "Print :LSEnvironment:$key" "$plist" 2>/dev/null || true)"
  [[ -n "$value" ]] && clean_env+=("$key=$value")
done

launch_log="/tmp/cmux-launch-${slug}.out"
nohup "${clean_env[@]}" "$executable" >"$launch_log" 2>&1 </dev/null &
for _ in {1..100}; do
  [[ -S "$socket_path" ]] && break
  sleep 0.1
done
if [[ ! -S "$socket_path" ]]; then
  echo "error: tagged app did not create its socket: $socket_path" >&2
  echo "launch log: $launch_log" >&2
  exit 1
fi
printf 'launched %s\napp: %s\nbundle_id: %s\nsocket: %s\nlog: %s\n' "$slug" "$app_path" "$bundle_id" "$socket_path" "$launch_log"
