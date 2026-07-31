#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

# Small helpers
log() { echo "🔧 $*"; }
warn() { echo "⚠️  $*" >&2; }
die() { echo "❌ $*" >&2; exit 1; }
step() { echo ""; echo "── $* ─────────────────────────────────────"; }

usage() {
    cat <<'EOF'
Usage: ./apply.sh [flags]

  (no flags)        Interactive: pick a letter, then an app, or reset changes
  --app NAME        Apply that app's config without prompting
  --list-apps       Print the available app names, one per line
  --reset           Reset the config paths without the Y/N prompt
  --screenshots     Capture App Store screenshots for one app (see below)
  -h, --help        Show this help

Screenshot flags (only with --screenshots):
  --device WHICH    iphone | ipad | both              (default: both)
  --out DIR         Parent folder for <AppName>_Screenshots (default: ~/Desktop)
  --skip-git        Don't touch branches — use the checkout exactly as it is
  --check           Report the environment and exit without changing anything

  The run prints one line per step. For every tap and keystroke, set
  SCREENSHOT_VERBOSE=true (see config.env for the other knobs).

Examples:
  ./apply.sh                                  # switch app, or reset
  ./apply.sh --app ZopStore
  ./apply.sh --screenshots                    # fully automated, pick app from menu
  ./apply.sh --screenshots --app ZopStore --device ipad
  ./apply.sh --screenshots --check
EOF
}

# ── Options ──

APP_ARG=""
LIST_ONLY=false
RESET_ONLY=false
SCREENSHOTS=false
DEVICE_CHOICE="both"
SKIP_GIT=false
CHECK_ONLY=false
OUT_ROOT_OVERRIDE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app)
            [ "$#" -ge 2 ] || die "--app needs an app name"
            APP_ARG="$2"; shift 2 ;;
        --list-apps)    LIST_ONLY=true; shift ;;
        --reset)        RESET_ONLY=true; shift ;;
        --screenshots)  SCREENSHOTS=true; shift ;;
        --device)
            [ "$#" -ge 2 ] || die "--device needs a value (iphone | ipad | both)"
            DEVICE_CHOICE="$2"; shift 2 ;;
        --out)
            [ "$#" -ge 2 ] || die "--out needs a directory"
            OUT_ROOT_OVERRIDE="$2"; shift 2 ;;
        --skip-git)     SKIP_GIT=true; shift ;;
        --check)        CHECK_ONLY=true; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              usage >&2; echo "" >&2; die "Unknown flag: $1" ;;
    esac
done

case "$DEVICE_CHOICE" in
    iphone|ipad|both) ;;
    *) die "--device must be one of: iphone, ipad, both (got: $DEVICE_CHOICE)" ;;
esac

if [ "$SCREENSHOTS" = false ]; then
    for flag in "--device:$DEVICE_CHOICE:both" "--skip-git:$SKIP_GIT:false" "--check:$CHECK_ONLY:false"; do
        name="${flag%%:*}"; rest="${flag#*:}"; value="${rest%%:*}"; default="${rest##*:}"
        [ "$value" = "$default" ] || die "$name only applies with --screenshots"
    done
    [ -z "$OUT_ROOT_OVERRIDE" ] || die "--out only applies with --screenshots"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    die "Missing config.env at: $CONFIG_FILE"
fi

source "$CONFIG_FILE"

# Validate environment
# Unset or empty? Fall back to a sibling checkout, so a fresh clone of this repo
# next to ios-consumer-app works without editing config.env first.
if [ -z "${CONSUMER_APP_DIR:-}" ] && [ -d "$SCRIPT_DIR/../ios-consumer-app" ]; then
    CONSUMER_APP_DIR="$(cd "$SCRIPT_DIR/../ios-consumer-app" && pwd)"
    # stderr, so --list-apps stays machine-readable on stdout
    log "CONSUMER_APP_DIR not set — using sibling checkout: $CONSUMER_APP_DIR" >&2
fi

if [ -z "${CONSUMER_APP_DIR:-}" ]; then
    die "CONSUMER_APP_DIR must be set in $CONFIG_FILE (or clone ios-consumer-app next to this repo)"
fi

if [ ! -d "$CONSUMER_APP_DIR" ]; then
    die "CONSUMER_APP_DIR does not exist: $CONSUMER_APP_DIR"
fi

if [ ! -w "$CONSUMER_APP_DIR" ]; then
    die "CONSUMER_APP_DIR is not writable: $CONSUMER_APP_DIR"
fi

# Everything is derived from CONSUMER_APP_DIR — the Apps/ folder is the source,
# the rest of the checkout is the destination the config gets applied into.
APPS_DIR="$CONSUMER_APP_DIR/Apps"
DEST="$CONSUMER_APP_DIR"
CONFIG_DEST="$DEST/Configuration.xcconfig"
ASSETS_XCASSETS="$DEST/Consumer/Assets/Assets.xcassets"
ASSETS_DEST="$ASSETS_XCASSETS/_Configuration"
GOOGLE_SERVICE_DEST="$DEST/Consumer/GoogleService-Info.plist"
GOOGLE_SERVICE_DEFAULT="$APPS_DIR/_default/GoogleService-Info.plist"
PBXPROJ_PATH="$DEST/Consumer.xcodeproj/project.pbxproj"

if [ ! -d "$APPS_DIR" ]; then
    die "Apps folder not found at: $APPS_DIR"
fi

# ── Collect app folder names (skip the _default scaffold) ──
APPS_RAW=()
for d in "$APPS_DIR"/*; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    [ "$name" == "_default" ] && continue
    APPS_RAW+=("$name")
done

if [ "${#APPS_RAW[@]}" -eq 0 ]; then
    die "No app folders found under $APPS_DIR"
fi

ALL_APPS=()
while IFS= read -r name; do
    ALL_APPS+=("$name")
done < <(printf '%s\n' "${APPS_RAW[@]}" | sort)

if [ "$LIST_ONLY" = true ]; then
    printf '%s\n' "${ALL_APPS[@]}"
    exit 0
fi

# ── Actions ──

apply_app() {
    local app="$1"
    local src="$APPS_DIR/$app"

    echo ""
    echo "🚀 Applying configuration for: $app"

    # 1. Replace xcconfig
    if [ -f "$src/config.xcconfig" ]; then
        cp -f "$src/config.xcconfig" "$CONFIG_DEST"
        echo "✅ Config applied"
    else
        die "Missing config.xcconfig for $app at $src"
    fi

    # 2. Replace GoogleService-Info.plist (fall back to Apps/_default if the app has none)
    if [ -f "$src/GoogleService-Info.plist" ]; then
        cp -f "$src/GoogleService-Info.plist" "$GOOGLE_SERVICE_DEST"
        echo "✅ GoogleService-Info applied"
    elif [ -f "$GOOGLE_SERVICE_DEFAULT" ]; then
        cp -f "$GOOGLE_SERVICE_DEFAULT" "$GOOGLE_SERVICE_DEST"
        echo "⚠️  No GoogleService-Info.plist for $app — fell back to Apps/_default"
    else
        die "Missing GoogleService-Info.plist for $app (and no Apps/_default fallback)"
    fi

    # 3. Replace assets (Assets folder -> _Configuration)
    if [ -d "$src/Assets" ]; then
        rm -rf "$ASSETS_DEST"
        cp -R "$src/Assets" "$ASSETS_DEST"
        echo "✅ Assets replaced"
    else
        die "Missing Assets folder for $app at $src"
    fi

    # Nudge Xcode into noticing the swap
    touch "$PBXPROJ_PATH" 2>/dev/null || true
    find "$ASSETS_DEST" -name "Contents.json" -exec touch {} \; 2>/dev/null || true

    echo ""
    echo "🎉 Done. $app is now active — re-open Xcode (or close/reopen the project) to pick it up."
}

# The reset itself. reset_changes() below is the interactive wrapper; --reset calls
# this directly so the screenshot run can revert itself without a prompt.
do_reset() {
    if ! git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        die "DEST is not a git repository: $DEST"
    fi
    echo "🧹 Resetting..."
    git -C "$DEST" checkout -- \
        "Configuration.xcconfig" \
        "Consumer/GoogleService-Info.plist" \
        "Consumer/Assets/Assets.xcassets/_Configuration" \
        || die "Failed to reset. Do these paths exist in the last commit?"
    git -C "$DEST" clean -fd -- "Consumer/Assets/Assets.xcassets/_Configuration" >/dev/null 2>&1 || true
    echo ""
    log "✅ Done. Repo config reset."
}

reset_changes() {
    echo ""
    log "⚠️  This restores Configuration.xcconfig, Consumer/GoogleService-Info.plist,"
    log "   and Consumer/Assets/Assets.xcassets/_Configuration in:"
    log "   $DEST"
    log "   to their last committed state. Nothing else in the repo is touched."
    echo ""
    echo "This action cannot be undone."
    echo -n "Proceed? (Y/N): "
    read -r answer
    echo ""

    case "$answer" in
        y|Y|yes|YES|Yes)
            do_reset
            ;;
        *)
            log "❎ Cancelled. Nothing was changed."
            ;;
    esac
}

# Shared two-step letter menu. Sets SELECTED_APP.
SELECTED_APP=""
pick_app() {
    local include_reset="$1"
    local letters=() prev="" letter i reset_index letter_choice app_choice matches=()

    for app in "${ALL_APPS[@]}"; do
        letter="$(printf '%s' "${app:0:1}" | tr '[:lower:]' '[:upper:]')"
        if [ "$letter" != "$prev" ]; then
            letters+=("$letter")
            prev="$letter"
        fi
    done

    echo "📋 ${#ALL_APPS[@]} apps available under $APPS_DIR"
    echo ""
    echo "Select a letter:"
    i=1
    for letter in "${letters[@]}"; do
        echo "  $i) $letter"
        ((i++))
    done
    reset_index=$i
    if [ "$include_reset" = true ]; then
        echo "  $reset_index) Reset changes"
    fi
    echo ""
    read -r -p "👉 Choice: " letter_choice

    if ! [[ "$letter_choice" =~ ^[0-9]+$ ]]; then
        echo ""
        die "Invalid input. Please enter a number."
    fi

    if [ "$include_reset" = true ] && [ "$letter_choice" -eq "$reset_index" ]; then
        SELECTED_APP="__RESET__"
        return 0
    fi

    if [ "$letter_choice" -lt 1 ] || [ "$letter_choice" -gt "${#letters[@]}" ]; then
        echo ""
        die "Invalid choice."
    fi

    local chosen_letter="${letters[$((letter_choice - 1))]}"
    for app in "${ALL_APPS[@]}"; do
        letter="$(printf '%s' "${app:0:1}" | tr '[:lower:]' '[:upper:]')"
        [ "$letter" == "$chosen_letter" ] && matches+=("$app")
    done

    echo ""
    echo "Apps starting with '$chosen_letter':"
    i=1
    for app in "${matches[@]}"; do
        echo "  $i) $app"
        ((i++))
    done
    echo ""
    read -r -p "👉 Choice: " app_choice

    if ! [[ "$app_choice" =~ ^[0-9]+$ ]] || [ "$app_choice" -lt 1 ] || [ "$app_choice" -gt "${#matches[@]}" ]; then
        echo ""
        die "Invalid choice."
    fi

    SELECTED_APP="${matches[$((app_choice - 1))]}"
}

# ── Non-interactive: reset, or apply a named app, and stop ──

if [ "$RESET_ONLY" = true ]; then
    do_reset
    exit 0
fi

if [ "$SCREENSHOTS" = false ]; then
    if [ -n "$APP_ARG" ]; then
        if [ ! -d "$APPS_DIR/$APP_ARG" ]; then
            die "No such app folder: $APPS_DIR/$APP_ARG"
        fi
        apply_app "$APP_ARG"
        exit 0
    fi

    # Interactive: show the flags first, then the menu.
    usage
    echo ""
    pick_app true
    if [ "$SELECTED_APP" = "__RESET__" ]; then
        reset_changes
    else
        apply_app "$SELECTED_APP"
    fi
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
#  --screenshots
#
#  Fully automated: branch + pull, hide the debug theme icon, apply the app,
#  resolve the delivery pincode from the org, build, and drive the app through
#  home → category → product → cart with an XCUITest that sets the address and
#  taps through the flow. Every screen is captured at App Store resolution, and
#  only once it has finished loading.
#
#  Nothing is left behind: source edits reverted, config reset, simulators closed —
#  on success, on failure, and on Ctrl-C / kill / a closed terminal. What a SIGKILL
#  leaves behind is repaired by reclaim_stale_run() at the start of the next run.
#  A PID lock keeps two runs from fighting over the same checkout.
# ══════════════════════════════════════════════════════════════════════════════

SCREENSHOT_BRANCH="${SCREENSHOT_BRANCH:-development}"
SCREENSHOT_IPHONE_DEVICE="${SCREENSHOT_IPHONE_DEVICE:-iPhone 14 Plus}"
SCREENSHOT_IPAD_DEVICE="${SCREENSHOT_IPAD_DEVICE:-iPad Pro 13-inch (M5)}"
SCREENSHOT_OUTPUT_ROOT="${SCREENSHOT_OUTPUT_ROOT:-$HOME/Desktop}"
SCREENSHOT_CLEAN_STATUS_BAR="${SCREENSHOT_CLEAN_STATUS_BAR:-true}"
SCREENSHOT_WORKSPACE="${SCREENSHOT_WORKSPACE:-Consumer.xcworkspace}"
SCREENSHOT_SCHEME="${SCREENSHOT_SCHEME:-Consumer}"
SCREENSHOT_DERIVED_DATA="${SCREENSHOT_DERIVED_DATA:-$HOME/Library/Caches/consumerBuildAutomation/DerivedData}"
SCREENSHOT_CART_ITEMS="${SCREENSHOT_CART_ITEMS:-3}"
# true → also stream every tap and keystroke. Off by default: the step narrative
# plus failures is enough to follow a run, and the full log is always on disk.
SCREENSHOT_VERBOSE="${SCREENSHOT_VERBOSE:-false}"
# Hard ceiling on the UI test, so a screen the test can't reach can never hang the
# run — XCTest kills it and the screenshots taken so far still come back.
SCREENSHOT_TEST_TIMEOUT="${SCREENSHOT_TEST_TIMEOUT:-1500}"

[ -n "$OUT_ROOT_OVERRIDE" ] && SCREENSHOT_OUTPUT_ROOT="$OUT_ROOT_OVERRIDE"

REPO="$CONSUMER_APP_DIR"
TOOLBAR_REL="Consumer/Helper Views/CustomToolbarView.swift"
TOOLBAR_ABS="$REPO/$TOOLBAR_REL"
UITEST_REL="ConsumerUITests/ConsumerUITests.swift"
UITEST_ABS="$REPO/$UITEST_REL"

# The 4 shots, in capture order. Slugs must match the XCUITest below.
SHOT_SLUGS=("01_home" "02_category" "03_product" "04_cart")

# ── Preflight ──

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found — install Xcode + command line tools"
command -v xcrun >/dev/null 2>&1 || die "xcrun not found — install Xcode command line tools"
command -v python3 >/dev/null 2>&1 || die "python3 not found — install Xcode command line tools"
xcrun simctl help >/dev/null 2>&1 || die "xcrun simctl is unavailable — check 'xcode-select -p'"
[ -f "$TOOLBAR_ABS" ] || die "Not found: $TOOLBAR_ABS (is CONSUMER_APP_DIR the ios-consumer-app checkout?)"
[ -f "$UITEST_ABS" ] || die "Not found: $UITEST_ABS — the ConsumerUITests target is required to drive the app."
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "CONSUMER_APP_DIR is not a git repository: $REPO"

# ── Teardown ──
#
# Everything this run changes is undone on every exit path — success, failure or
# Ctrl-C. Each part is flag-guarded, so running teardown twice is harmless.

TOOLBAR_PATCHED=false
UITEST_PATCHED=false
CONFIG_APPLIED=false
BOOTED_BY_US=()
LAUNCHED_SIMULATOR_APP=false

booted_udids() {
    xcrun simctl list devices booted 2>/dev/null \
        | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}' || true
}

# Snapshot before anything is booted: everything running now is the user's, and stays.
PRE_BOOTED_UDIDS=" $(booted_udids | tr '\n' ' ') "
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/consumer-screenshots.XXXXXX")"
TOOLBAR_BACKUP="$WORK_DIR/CustomToolbarView.swift.orig"
UITEST_BACKUP="$WORK_DIR/ConsumerUITests.swift.orig"
# Outside WORK_DIR on purpose: the logs have to outlive the run to be any use when
# something failed. One per device, so the iPhone log survives the iPad leg.
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}"
BUILD_LOG="$LOG_DIR/consumer-screenshots-build.log"

LOCK_DIR="$LOG_DIR/consumer-screenshots.lock"

# Restores byte-for-byte originals rather than 'git checkout --', so unrelated
# uncommitted edits to these files survive (possible with --skip-git).
restore_file() {
    local flag_name="$1" backup="$2" target="$3" label="$4"
    [ "$(eval "echo \$$flag_name")" = true ] || return 0
    eval "$flag_name=false"
    if [ -f "$backup" ] && cp "$backup" "$target" 2>/dev/null; then
        log "Reverted $label"
    else
        warn "Could not revert $label — undo it manually before committing."
    fi
}

reset_applied_config() {
    [ "$CONFIG_APPLIED" = true ] || return 0
    CONFIG_APPLIED=false
    log "Resetting the applied config"
    do_reset || warn "Reset failed — run ./apply.sh ▸ Reset changes yourself."
}

# Shuts down anything that wasn't already running when this run started, and leaves
# whatever the user had open alone. Comparing against a snapshot rather than tracking
# our own `simctl boot` calls matters: `open -a Simulator` also boots whichever device
# it had last, which we never asked for and would otherwise leave running.
shutdown_simulators() {
    local closed=0 udid
    for udid in $(booted_udids); do
        case " $PRE_BOOTED_UDIDS " in
            *" $udid "*) continue ;;
        esac
        xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
        xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
        closed=$((closed + 1))
    done
    [ "$closed" -gt 0 ] && log "Shut down $closed simulator(s)"
    BOOTED_BY_US=()

    if [ "$LAUNCHED_SIMULATOR_APP" = true ]; then
        LAUNCHED_SIMULATOR_APP=false
        if ! xcrun simctl list devices booted 2>/dev/null | grep -q "Booted"; then
            osascript -e 'quit app "Simulator"' >/dev/null 2>&1 || true
        fi
    fi
}

teardown() {
    restore_file UITEST_PATCHED "$UITEST_BACKUP" "$UITEST_ABS" "$UITEST_REL"
    restore_file TOOLBAR_PATCHED "$TOOLBAR_BACKUP" "$TOOLBAR_ABS" "$TOOLBAR_REL"
    reset_applied_config
    shutdown_simulators
}

cleanup() {
    local code="$?"
    teardown
    [ -n "${WORK_DIR:-}" ] && rm -rf "$WORK_DIR"
    [ -n "${LOCK_DIR:-}" ] && rm -rf "$LOCK_DIR" 2>/dev/null
    [ "$code" -ne 0 ] && echo "" && warn "Stopped early (exit $code) — changes above were rolled back."
    return 0
}
trap cleanup EXIT
# Ctrl-C, `kill`, and a closed terminal all need to reach the EXIT trap — without
# handlers for these, bash dies on the signal and the checkout stays patched.
# (A SIGKILL still can't be caught; that's what reclaim_stale_run is for.)
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Taken only once the trap above is armed, so the lock can't outlive the run.
# Two runs at once would fight over the same checkout — one would revert the
# other's patches mid-build. A lock left by a killed run is detected via its PID.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        LOCK_DIR=""   # not ours — cleanup must not remove it
        die "Another screenshot run is already going (pid $lock_pid).
   Wait for it to finish, or stop it and re-run."
    fi
    log "Clearing a stale lock from a run that didn't finish (pid ${lock_pid:-unknown})"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || die "Could not create the run lock at $LOCK_DIR"
fi
echo "$$" > "$LOCK_DIR/pid"

# ── Simulator resolution ──

resolve_udid() {
    # Prefers an already-booted device, then the newest runtime — device names
    # like "iPad Pro 13-inch (M5)" exist once per installed runtime.
    local device_name="$1"
    local list_file="$WORK_DIR/devices.json"
    xcrun simctl list -j devices available >"$list_file" 2>/dev/null || return 1
    python3 - "$device_name" "$list_file" <<'PY'
import json, re, sys

name = sys.argv[1]
try:
    with open(sys.argv[2], encoding="utf-8") as handle:
        devices = json.load(handle).get("devices") or {}
except Exception:
    sys.exit(1)

def runtime_key(runtime):
    digits = re.findall(r"\d+", runtime.rsplit(".", 1)[-1])
    return tuple(int(d) for d in digits) or (0,)

best = None
for runtime, entries in devices.items():
    for entry in entries:
        if entry.get("name") != name or not entry.get("isAvailable", True):
            continue
        key = (entry.get("state") == "Booted", runtime_key(runtime))
        if best is None or key > best[0]:
            best = (key, entry["udid"])

if best is None:
    sys.exit(1)
print(best[1])
PY
}

# Exact-name lookup in this Xcode's device types → "<identifier>" (empty if absent).
find_device_type() {
    local device_name="$1"
    local types_file="$WORK_DIR/devicetypes.json"
    xcrun simctl list -j devicetypes >"$types_file" 2>/dev/null || return 1
    python3 - "$device_name" "$types_file" <<'PY'
import json, sys

name = sys.argv[1]
try:
    with open(sys.argv[2], encoding="utf-8") as handle:
        types = json.load(handle).get("devicetypes") or []
except Exception:
    sys.exit(1)

for entry in types:
    if entry.get("name") == name:
        print(entry.get("identifier", ""))
        break
else:
    sys.exit(1)
PY
}

# Newest usable iOS runtime → "<identifier>|<friendly name>" (empty if none installed).
newest_ios_runtime() {
    local runtimes_file="$WORK_DIR/runtimes.json"
    xcrun simctl list -j runtimes >"$runtimes_file" 2>/dev/null || return 1
    python3 - "$runtimes_file" <<'PY'
import json, re, sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        runtimes = json.load(handle).get("runtimes") or []
except Exception:
    sys.exit(1)

def version_key(runtime):
    parts = re.findall(r"\d+", runtime.get("version") or "0")
    return tuple(int(p) for p in parts) or (0,)

usable = [
    r for r in runtimes
    if r.get("isAvailable", True) and "iOS" in (r.get("name") or r.get("identifier", ""))
]
if not usable:
    sys.exit(1)
best = max(usable, key=version_key)
print(f"{best['identifier']}|{best.get('name') or best['identifier']}")
PY
}

# What this Xcode *can* offer, so the message below is actionable rather than a dead end.
suggest_devices() {
    local keyword="$1"
    local types_file="$WORK_DIR/devicetypes.json"
    xcrun simctl list -j devicetypes >"$types_file" 2>/dev/null || return 0
    python3 - "$keyword" "$types_file" <<'PY' || true
import json, sys

keyword = sys.argv[1].lower()
try:
    with open(sys.argv[2], encoding="utf-8") as handle:
        types = json.load(handle).get("devicetypes") or []
except Exception:
    sys.exit(0)

# simctl lists device types newest-first, so the head is the most useful suggestion.
names = [t["name"] for t in types if keyword in t.get("name", "").lower()]
for name in names[:8]:
    print(f"     • {name}")
PY
}

# Resolves a simulator by name, creating it when the device type exists but no
# simulator has been made yet. Sets RESOLVED_UDID. Returns 1 with install
# instructions when this Xcode can't provide the device at all.
RESOLVED_UDID=""
ensure_device() {
    local device_name="$1" slot="$2" config_key="$3"
    local udid dtype runtime_info runtime_id runtime_name answer keyword

    RESOLVED_UDID=""
    udid="$(resolve_udid "$device_name" || true)"
    if [ -n "$udid" ]; then
        log "$slot: '$device_name' ready"
        RESOLVED_UDID="$udid"
        return 0
    fi

    case "$device_name" in
        *iPad*|*iPod*) keyword="iPad" ;;
        *) keyword="iPhone" ;;
    esac

    log "$slot: no '$device_name' simulator exists yet"
    dtype="$(find_device_type "$device_name" || true)"

    if [ -z "$dtype" ]; then
        echo "" >&2
        warn "This Xcode has no device type named '$device_name', so it can't be created."
        {
            echo "   Install the simulators, then re-run:"
            echo "     • Xcode ▸ Settings ▸ Components — install a newer iOS simulator runtime"
            echo "     • or from the terminal: xcodebuild -downloadPlatform iOS"
            echo "     • a newer device model may need a newer Xcode ($(xcodebuild -version 2>/dev/null | head -1))"
            echo ""
            echo "   Or point $config_key in config.env at a device you already have:"
            suggest_devices "$keyword"
        } >&2
        return 1
    fi

    runtime_info="$(newest_ios_runtime || true)"
    if [ -z "$runtime_info" ]; then
        echo "" >&2
        warn "No iOS simulator runtime is installed, so '$device_name' can't be created."
        {
            echo "   Install one, then re-run:"
            echo "     • xcodebuild -downloadPlatform iOS"
            echo "     • or Xcode ▸ Settings ▸ Components ▸ iOS simulators"
        } >&2
        return 1
    fi
    runtime_id="${runtime_info%%|*}"
    runtime_name="${runtime_info##*|}"

    log "$slot: creating '$device_name' on $runtime_name"
    udid="$(xcrun simctl create "$device_name" "$dtype" "$runtime_id" 2>/dev/null || true)"
    if [ -z "$udid" ]; then
        echo "" >&2
        warn "Could not create '$device_name' ($runtime_name)."
        echo "   Try: xcrun simctl create \"$device_name\" \"$dtype\" \"$runtime_id\"" >&2
        return 1
    fi
    log "$slot: created — it stays available for future runs"
    RESOLVED_UDID="$udid"
    return 0
}

# ── --check: report the environment and stop ──

if [ "$CHECK_ONLY" = true ]; then
    step "Environment check"
    echo ""
    echo "   $(xcodebuild -version 2>/dev/null | head -1 || echo 'Xcode: unknown')"
    echo "   python3          $(python3 --version 2>&1 | awk '{print $2}')"
    echo "   ios-consumer-app $REPO"
    echo "   branch           $(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    echo "   apps available    ${#ALL_APPS[@]}"
    echo "   UI test target   $([ -f "$UITEST_ABS" ] && echo 'ConsumerUITests ✅' || echo 'missing ❌')"
    echo "   output folder    $SCREENSHOT_OUTPUT_ROOT"
    echo ""
    echo "   Simulators:"
    CHECK_FAILED=false
    for entry in "6.5-inch|$SCREENSHOT_IPHONE_DEVICE" "13-inch|$SCREENSHOT_IPAD_DEVICE"; do
        check_slot="${entry%%|*}"
        check_name="${entry#*|}"
        if [ -n "$(resolve_udid "$check_name" || true)" ]; then
            echo "     ✅ $check_slot  $check_name"
        elif [ -n "$(find_device_type "$check_name" || true)" ]; then
            echo "     ⚠️  $check_slot  $check_name — not created yet; the run creates it automatically"
        else
            echo "     ❌ $check_slot  $check_name — this Xcode has no such device type"
            CHECK_FAILED=true
        fi
    done

    if [ "$CHECK_FAILED" = true ]; then
        echo ""
        echo "   To install the missing simulators:"
        echo "     • xcodebuild -downloadPlatform iOS"
        echo "     • or Xcode ▸ Settings ▸ Components ▸ iOS simulators"
        echo "     • a newer device model may need a newer Xcode"
        echo ""
        echo "   Or set SCREENSHOT_IPHONE_DEVICE / SCREENSHOT_IPAD_DEVICE in config.env to"
        echo "   devices you already have — 'xcrun simctl list devices available' lists them."
        echo ""
        die "Environment is not ready."
    fi

    echo ""
    log "Ready. Run ./apply.sh --screenshots to capture."
    exit 0
fi

# ── Step 0: clean up after an interrupted run ──
#
# If a previous run was killed (terminal closed, Ctrl-C that outran the trap, a
# crash), its teardown never ran and the checkout is still carrying the generated
# UI test, the commented-out theme icon and an applied config. Recover from that
# automatically — the alternative is a "working tree must be clean" refusal that
# blames the user for our mess.

reclaim_stale_run() {
    local reclaimed=false

    if git -C "$REPO" diff --quiet -- "$UITEST_REL" 2>/dev/null; then :; else
        if grep -q "GENERATED by ios-local-consumerBuildAutomation" "$UITEST_ABS" 2>/dev/null; then
            git -C "$REPO" checkout -- "$UITEST_REL" 2>/dev/null && reclaimed=true
        fi
    fi

    if git -C "$REPO" diff --quiet -- "$TOOLBAR_REL" 2>/dev/null; then :; else
        # Revert only if our commented-out block is present AND every added line is a
        # comment — anything else means someone is working in that file.
        if git -C "$REPO" diff -- "$TOOLBAR_REL" 2>/dev/null \
            | grep -q '^+[[:space:]]*//[[:space:]]*if AppInfo.currentTarget == .consumer {'; then
            if git -C "$REPO" diff -U0 -- "$TOOLBAR_REL" 2>/dev/null \
                | grep '^+' | grep -v '^+++' | grep -qv '^+[[:space:]]*//' ; then
                warn "$TOOLBAR_REL also has edits that aren't ours — leaving it alone."
            else
                git -C "$REPO" checkout -- "$TOOLBAR_REL" 2>/dev/null && reclaimed=true
            fi
        fi
    fi

    # A config left applied by an interrupted run. This run applies its own and
    # resets at the end regardless, so restoring it now costs nothing.
    # do_reset dies on a broken repo, so run it where that can't kill this script.
    if ! git -C "$REPO" diff --quiet -- \
        "Configuration.xcconfig" \
        "Consumer/GoogleService-Info.plist" \
        "Consumer/Assets/Assets.xcassets/_Configuration" 2>/dev/null; then
        if ( do_reset ) >/dev/null 2>&1; then
            reclaimed=true
        else
            warn "Could not reset a previously applied config — continuing."
        fi
    fi

    if [ "$reclaimed" = true ]; then
        log "Cleaned up leftovers from an interrupted run"
    fi
}

reclaim_stale_run

# ── Step 1: development branch, latest pull ──

step "Step 1/6 · Branch"

if [ "$SKIP_GIT" = true ]; then
    log "Skipping git prep (--skip-git). Current branch: $(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
    # The closing reset restores these three paths from HEAD — say so up front.
    DIRTY_CONFIG_PATHS="$(git -C "$REPO" status --porcelain -- \
        "Configuration.xcconfig" \
        "Consumer/GoogleService-Info.plist" \
        "Consumer/Assets/Assets.xcassets/_Configuration" 2>/dev/null || true)"
    if [ -n "$DIRTY_CONFIG_PATHS" ]; then
        echo ""
        echo "$DIRTY_CONFIG_PATHS" | sed 's/^/   /'
        warn "These are uncommitted, and the closing reset will discard them."
        echo -n "   Continue? (Y/N): "
        read -r confirm
        case "$confirm" in
            y|Y|yes|YES|Yes) ;;
            *) die "Cancelled. Nothing was changed." ;;
        esac
    fi
else
    if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
        echo ""
        echo "Uncommitted changes in $REPO:"
        git -C "$REPO" status --short | sed 's/^/   /'
        echo ""
        die "Working tree must be clean before screenshots. Commit or stash first (or pass --skip-git)."
    fi

    ORIGINAL_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
    if [ "$ORIGINAL_BRANCH" != "$SCREENSHOT_BRANCH" ]; then
        log "Switching from '$ORIGINAL_BRANCH' to '$SCREENSHOT_BRANCH' (switch back yourself when you're done)"
        git -C "$REPO" checkout "$SCREENSHOT_BRANCH" >/dev/null 2>&1 \
            || die "Could not check out '$SCREENSHOT_BRANCH' in $REPO"
    fi

    log "Pulling latest ${SCREENSHOT_BRANCH}…"
    git -C "$REPO" pull --ff-only >/dev/null 2>&1 \
        || die "'git pull --ff-only' failed on $SCREENSHOT_BRANCH. Resolve it manually, or pass --skip-git."
    log "On $SCREENSHOT_BRANCH @ $(git -C "$REPO" rev-parse --short HEAD)"
fi

# ── Step 2: hide the debug theme-selector icon ──

step "Step 2/6 · Theme-selector icon"

cp "$TOOLBAR_ABS" "$TOOLBAR_BACKUP" || die "Could not back up $TOOLBAR_REL"
PATCH_RESULT="$(python3 - "$TOOLBAR_ABS" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()

# The DEBUG-only block that puts the local theme/store switcher in the toolbar:
#     #if DEBUG
#                     if AppInfo.currentTarget == .consumer {
#                         localThemeSelectorIcon
#                     }
BLOCK = [
    "if AppInfo.currentTarget == .consumer {",
    "localThemeSelectorIcon",
    "}",
]

def commented(line):
    return line.strip().startswith("//")

for i, line in enumerate(lines):
    if line.strip() != "#if DEBUG":
        continue
    body = lines[i + 1 : i + 1 + len(BLOCK)]
    if len(body) < len(BLOCK):
        continue
    if [b.strip() for b in body] == BLOCK:
        for offset in range(1, len(BLOCK) + 1):
            target = lines[i + offset]
            indent = target[: len(target) - len(target.lstrip())]
            lines[i + offset] = f"{indent}// {target.strip()}\n"
        with open(path, "w", encoding="utf-8") as handle:
            handle.writelines(lines)
        print(f"patched:{i + 2}")
        break
    if all(commented(b) for b in body) and [
        b.strip().lstrip("/").strip() for b in body
    ] == BLOCK:
        print("already")
        break
else:
    print("notfound")
PY
)" || die "Failed to inspect $TOOLBAR_REL"

case "$PATCH_RESULT" in
    patched:*)
        TOOLBAR_PATCHED=true
        log "Commented out localThemeSelectorIcon (${TOOLBAR_REL##*/}:${PATCH_RESULT#patched:})"
        ;;
    already)
        log "Theme-selector block is already commented out — leaving it as is"
        ;;
    *)
        die "Could not find the '#if DEBUG / localThemeSelectorIcon' block in $TOOLBAR_REL.
   It may have moved — comment it out by hand, or update the BLOCK pattern in apply.sh."
        ;;
esac

# ── Step 3: pick the app and apply its config ──

step "Step 3/6 · App"

if [ -n "$APP_ARG" ]; then
    [ -d "$APPS_DIR/$APP_ARG" ] || die "No such app folder: $APPS_DIR/$APP_ARG"
    APP_NAME="$APP_ARG"
else
    pick_app false
    APP_NAME="$SELECTED_APP"
fi

log "App: $APP_NAME"
apply_app "$APP_NAME"
CONFIG_APPLIED=true

# ── Step 4: delivery pincode from the org's response ──

step "Step 4/6 · Delivery pincode"

APP_CONFIG="$APPS_DIR/$APP_NAME/config.xcconfig"
[ -f "$APP_CONFIG" ] || die "Missing config.xcconfig for $APP_NAME"

# Used to wipe the app before each run — a cart or delivery address left over from a
# previous run would otherwise turn up in the screenshots.
APP_BUNDLE_ID="$(sed -n 's/^[[:space:]]*BUNDLE_ID[[:space:]]*=[[:space:]]*//p' "$APP_CONFIG" | head -1 | tr -d '[:space:]')"
# Home-screen icon label, used to relaunch the app so the status bar carries no
# "◀ <app>" breadcrumb from the test runner.
APP_DISPLAY_NAME="$(sed -n 's/^[[:space:]]*DISPLAY_NAME[[:space:]]*=[[:space:]]*//p' "$APP_CONFIG" | head -1 | sed 's/[[:space:]]*$//')"
log "App label: ${APP_DISPLAY_NAME:-<none>}"

# xcconfig hides the '//' from the include-parser as 'https:/$()/host'
DOMAIN="$(sed -n 's/^[[:space:]]*DOMAIN_NAME[[:space:]]*=[[:space:]]*//p' "$APP_CONFIG" | head -1 | sed 's/\$()//g' | tr -d '[:space:]')"
[ -n "$DOMAIN" ] || die "No DOMAIN_NAME in $APP_CONFIG — can't look up the org's default address."

ORG_URL="${DOMAIN%/}/api/organization"
ORG_FILE="$WORK_DIR/org.json"
log "GET $ORG_URL"
curl -fsS -m 30 "$ORG_URL" -o "$ORG_FILE" 2>/dev/null && [ -s "$ORG_FILE" ] \
    || die "Couldn't reach $ORG_URL — the address can't be set automatically without it."

PIN_INFO="$(python3 - "$ORG_FILE" <<'PY' || true
import json, re, sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception:
    sys.exit(1)

data = payload.get("data") or {}

def candidates():
    store = data.get("defaultStore")
    if isinstance(store, dict):
        yield store.get("address")
    basic = ((data.get("config") or {}).get("basic")) or {}
    yield basic.get("address")
    for loc in data.get("pickupLocations") or []:
        if isinstance(loc, dict) and loc.get("default"):
            yield loc.get("address")

def pincode_of(address):
    # Postal code is the trailing component of the flattened address string.
    parts = [p.strip() for p in address.split(",") if p.strip()]
    for part in reversed(parts):
        if re.fullmatch(r"\d{4,10}", part):
            return part
        if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 -]{2,9}", part) and any(c.isdigit() for c in part):
            return part
    matches = re.findall(r"\b\d{4,10}\b", address)
    return matches[-1] if matches else ""

for address in candidates():
    if not isinstance(address, str) or not address.strip():
        continue
    pin = pincode_of(address)
    if pin:
        print(pin)
        print(address.strip())
        break
else:
    sys.exit(1)
PY
)"

[ -n "$PIN_INFO" ] || die "No pincode found in the org response at $ORG_URL."
PINCODE="$(printf '%s' "$PIN_INFO" | sed -n '1p')"
PIN_ADDRESS="$(printf '%s' "$PIN_INFO" | sed -n '2p')"
log "Pincode: $PINCODE"
log "From default address: $PIN_ADDRESS"

# ── Step 5: drive the app and capture ──

step "Step 5/6 · Capture"

# Screenshots are only ever wanted for the consumer target — Scarlet/GetzPH/GetzHK
# are separate apps.
case "$SCREENSHOT_SCHEME" in
    Scarlet|GetzPH|GetzHK|ConsumerTests|ConsumerUITests)
        die "SCREENSHOT_SCHEME is '$SCREENSHOT_SCHEME' — screenshots are for the Consumer target only." ;;
    Consumer) ;;
    *)
        warn "SCREENSHOT_SCHEME is '$SCREENSHOT_SCHEME', not 'Consumer'." ;;
esac

IPHONE_UDID=""
IPAD_UDID=""
if [ "$DEVICE_CHOICE" != "ipad" ]; then
    ensure_device "$SCREENSHOT_IPHONE_DEVICE" "6.5-inch" "SCREENSHOT_IPHONE_DEVICE" || exit 1
    IPHONE_UDID="$RESOLVED_UDID"
fi
if [ "$DEVICE_CHOICE" != "iphone" ]; then
    ensure_device "$SCREENSHOT_IPAD_DEVICE" "13-inch" "SCREENSHOT_IPAD_DEVICE" || exit 1
    IPAD_UDID="$RESOLVED_UDID"
fi

OUT_DIR="$SCREENSHOT_OUTPUT_ROOT/${APP_NAME}_Screenshots"
mkdir -p "$OUT_DIR" || die "Could not create $OUT_DIR"
CAPTURED_TOTAL=0

# Writes the UI test that does the driving. The pincode and slot are baked in as
# literals — nothing needs to reach the test process at runtime.
write_uitest() {
    local slot="$1"
    if [ "$UITEST_PATCHED" = false ]; then
        cp "$UITEST_ABS" "$UITEST_BACKUP" || die "Could not back up $UITEST_REL"
        UITEST_PATCHED=true
    fi
    # Escape anything sed would treat as syntax in the replacement — display names
    # like "Tom & Jerry" or "A/B Store" would otherwise corrupt the generated file.
    local safe_label
    safe_label="$(printf '%s' "$APP_DISPLAY_NAME" | sed -e 's/[\/&]/\\&/g')"

    sed -e "s/__PINCODE__/$PINCODE/g" \
        -e "s/__SLOT__/$slot/g" \
        -e "s/__CART_ITEMS__/$SCREENSHOT_CART_ITEMS/g" \
        -e "s/__APP_LABEL__/$safe_label/g" \
        "$WORK_DIR/UITestTemplate.swift" > "$UITEST_ABS" \
        || die "Could not write $UITEST_REL"
}

prepare_device() {
    local udid="$1" label="$2" was_booted="no"

    xcrun simctl list devices booted 2>/dev/null | grep -q "$udid" && was_booted="yes"
    log "Booting ${label}…"
    if xcrun simctl boot "$udid" >/dev/null 2>&1; then
        [ "$was_booted" = "no" ] && BOOTED_BY_US+=("$udid")
    fi
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

    pgrep -qx Simulator || LAUNCHED_SIMULATOR_APP=true
    open -a Simulator --args -CurrentDeviceUDID "$udid" >/dev/null 2>&1 || open -a Simulator || true

    # Start from a clean install every time. Without this the app keeps the previous
    # run's cart and delivery address, so the cart shot shows accumulated junk and the
    # address flow silently never runs.
    if [ -n "${APP_BUNDLE_ID:-}" ]; then
        xcrun simctl uninstall "$udid" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
        log "Cleared any previous app data ($APP_BUNDLE_ID)"
    fi

    # App Store screenshots want a clean status bar.
    if [ "$SCREENSHOT_CLEAN_STATUS_BAR" = true ]; then
        xcrun simctl status_bar "$udid" override \
            --time "9:41" --batteryState charged --batteryLevel 100 \
            --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
            >/dev/null 2>&1 \
            || xcrun simctl status_bar "$udid" override --time "9:41" >/dev/null 2>&1 \
            || warn "Could not clean up the status bar on $label"
    fi
}

report_size() {
    local file="$1" expected="$2"
    command -v sips >/dev/null 2>&1 || return 0
    local w h actual
    w="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/{print $2}')"
    h="$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/{print $2}')"
    [ -n "$w" ] && [ -n "$h" ] || return 0
    actual="${w}x${h}"
    if [ "$actual" = "$expected" ] || [ "${h}x${w}" = "$expected" ]; then
        echo "      $(basename "$file")  ${actual} ✅"
    else
        echo "      $(basename "$file")  ${actual} (App Store expects ${expected})"
    fi
}

# Pulls the XCUITest's screenshot attachments out of the result bundle and files
# them under <out>/<slot>/ using the slug baked into each attachment name.
collect_attachments() {
    local result_bundle="$1" slot="$2" dest="$3"
    local export_dir="$WORK_DIR/attachments-$slot"
    local export_log="$WORK_DIR/export-$slot.log"

    rm -rf "$export_dir"
    mkdir -p "$export_dir" "$dest"

    if [ ! -d "$result_bundle" ]; then
        echo "result bundle missing: $result_bundle" > "$export_log"
        return 1
    fi

    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$export_dir" >"$export_log" 2>&1 || true

    # Match on the slug rather than the attachment name: xcresulttool decorates names
    # with an index and UUID ("6.5-inch__01_home_0_<uuid>.png"), and each result
    # bundle belongs to one device anyway, so the slot prefix adds nothing.
    python3 - "$export_dir" "$dest" <<'PY'
import json, os, shutil, sys

export_dir, dest = sys.argv[1], sys.argv[2]
SLUGS = ("01_home", "02_category", "03_product", "04_cart")

def slug_of(text):
    for slug in SLUGS:
        if slug in text:
            return slug
    return None

# Newest attachment wins per slug, so a retried step doesn't leave a stale frame.
best = {}
manifest_path = os.path.join(export_dir, "manifest.json")
if os.path.exists(manifest_path):
    try:
        with open(manifest_path, encoding="utf-8") as handle:
            manifest = json.load(handle)
    except Exception:
        manifest = []
    for test in manifest:
        for attachment in test.get("attachments") or []:
            exported = attachment.get("exportedFileName") or ""
            name = attachment.get("suggestedHumanReadableName") or ""
            slug = slug_of(name) or slug_of(exported)
            if not slug or not exported:
                continue
            stamp = attachment.get("timestamp") or 0
            if slug not in best or stamp >= best[slug][0]:
                best[slug] = (stamp, exported)

# No manifest, or a shape we didn't expect: fall back to the exported filenames.
if not best and os.path.isdir(export_dir):
    for entry in sorted(os.listdir(export_dir)):
        if not entry.lower().endswith(".png"):
            continue
        slug = slug_of(entry)
        if slug and slug not in best:
            best[slug] = (0, entry)

for slug, (_, exported) in sorted(best.items()):
    source = os.path.join(export_dir, exported)
    if not os.path.exists(source):
        continue
    shutil.copyfile(source, os.path.join(dest, f"{slug}.png"))
    print(slug)
PY
}

capture_device() {
    local udid="$1" device_name="$2" slot="$3" expected="$4"
    local dest="$OUT_DIR/$slot"
    local result_bundle="$WORK_DIR/$slot.xcresult"
    local collected=()

    # One log per device, so the first leg's log survives the second.
    BUILD_LOG="$LOG_DIR/consumer-screenshots-$slot.log"

    # Clear the slot first. Otherwise a shot this run fails to take leaves the
    # previous run's file sitting there looking current.
    rm -rf "$dest"
    mkdir -p "$dest"

    echo ""
    log "$slot · $device_name"
    prepare_device "$udid" "$device_name"
    write_uitest "$slot"

    log "Building and running the UI test — the first build takes a while."
    log "Dots are compile progress; '│' lines are the test's steps."
    [ "$SCREENSHOT_VERBOSE" = true ] || log "Set SCREENSHOT_VERBOSE=true for every tap."
    log "Full log: $BUILD_LOG"
    echo ""
    rm -rf "$result_bundle"

    # Streamed through awk so the terminal keeps moving: compile steps collapse to
    # dots, while test stages, XCUITest activity and errors print in full. The
    # complete log still lands in $BUILD_LOG for diagnosis.
    set +e
    xcodebuild test \
        -workspace "$REPO/$SCREENSHOT_WORKSPACE" \
        -scheme "$SCREENSHOT_SCHEME" \
        -configuration Debug \
        -destination "id=$udid" \
        -derivedDataPath "$SCREENSHOT_DERIVED_DATA" \
        -resultBundlePath "$result_bundle" \
        -only-testing:ConsumerUITests/ConsumerUITests/testCaptureAppStoreScreenshots \
        -parallel-testing-enabled NO \
        -test-timeouts-enabled YES \
        -default-test-execution-time-allowance "$SCREENSHOT_TEST_TIMEOUT" \
        -maximum-test-execution-time-allowance "$SCREENSHOT_TEST_TIMEOUT" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        2>&1 | tee "$BUILD_LOG" | awk -v verbose="$SCREENSHOT_VERBOSE" '
function flushdots() { if (dots > 0) { printf "\n"; dots = 0 } }

# Build chatter collapses to dots so the terminal stays visibly alive.
/^(CompileSwift|CompileC|SwiftCompile|SwiftDriver|Ld |PhaseScriptExecution|CodeSign|ProcessInfoPlist|CpResource|Copy|Touch|RegisterExecution|WriteAuxiliary|CreateBuildDirectory|MkDir|SwiftEmitModule|ExtractAppIntents|Validate)/ {
    dots++; if (dots % 8 == 0) { printf "."; fflush() } next
}

# The narrative: one line per step, with the elapsed time inside the test.
/ STEP / {
    flushdots()
    stamp = ""
    if (match($0, /t = +[0-9.]+s/)) { stamp = substr($0, RSTART, RLENGTH); sub(/t = +/, "", stamp) }
    text = substr($0, index($0, "STEP ") + 5)
    if (stamp != "") printf "   │ %7s  %s\n", stamp, text
    else            printf "   │           %s\n", text
    fflush(); next
}

# Anything that explains a failure.
/SCREENSHOT_NOTES|error: |\*\* TEST FAILED|\*\* BUILD FAILED|Restarting after unexpected|unexpected exit|crashed|Application is not running|Assertion Failure|terminated unexpectedly|Test Case .*(passed|failed) \(/ {
    flushdots(); sub(/^ +/, ""); print "   │ " $0; fflush(); next
}

# Every tap and keystroke — only with SCREENSHOT_VERBOSE=true.
verbose == "true" && /^ +t = +[0-9.]+s (Tap|Type|Press|Swipe|Scroll|Drag|Open|Launch|Terminate|Wait for)/ {
    flushdots(); sub(/^ +/, ""); print "   │   " $0; fflush(); next
}

END { flushdots() }'
    local test_status="${PIPESTATUS[0]}"
    set -e
    echo ""

    if grep -q "error: " "$BUILD_LOG" && [ ! -d "$result_bundle" ]; then
        echo ""
        grep "error: " "$BUILD_LOG" | head -8 >&2
        echo "" >&2
        die "The build failed before the app could run. Full log: $BUILD_LOG"
    fi

    # What the test itself reported.
    local notes
    notes="$(grep -o "SCREENSHOT_NOTES:.*" "$BUILD_LOG" | tail -1 | sed 's/^SCREENSHOT_NOTES://' || true)"

    while IFS= read -r slug; do
        [ -n "$slug" ] && collected+=("$slug")
    done < <(collect_attachments "$result_bundle" "$slot" "$dest" || true)

    if [ "${#collected[@]}" -eq 0 ]; then
        warn "No screenshots came back for $slot (test exit $test_status)."
        [ -s "$WORK_DIR/export-$slot.log" ] && head -5 "$WORK_DIR/export-$slot.log" | sed 's/^/   /' >&2
        [ -n "$notes" ] && warn "$slot: $notes"
        warn "Log: $BUILD_LOG"
        return 0
    fi

    local slug
    for slug in "${collected[@]}"; do
        report_size "$dest/$slug.png" "$expected"
        CAPTURED_TOTAL=$((CAPTURED_TOTAL + 1))
    done

    # Name the screens the test could not reach, rather than silently returning 3 of 4.
    local missing=()
    local expected_slug found
    for expected_slug in "${SHOT_SLUGS[@]}"; do
        found=false
        for slug in "${collected[@]}"; do
            [ "$slug" = "$expected_slug" ] && found=true
        done
        [ "$found" = false ] && missing+=("$expected_slug")
    done
    # Caveats are worth surfacing even when all four shots came back — "added 1 of 3"
    # or "no cart wording matched" changes how much you trust the result.
    if [ -n "$notes" ]; then
        warn "$slot: $notes"
    fi
    if [ "${#missing[@]}" -gt 0 ]; then
        warn "$slot: missing $(printf '%s ' "${missing[@]}")"
        warn "$slot log: $BUILD_LOG"
    fi
    return 0
}

# The XCUITest that does the actual driving. Written once, specialised per device.
cat > "$WORK_DIR/UITestTemplate.swift" <<'SWIFT'
//
//  ConsumerUITests.swift
//  ConsumerUITests
//
//  GENERATED by ios-local-consumerBuildAutomation/apply.sh --screenshots.
//  This file is restored to its committed state when the run finishes.
//

import XCTest

final class ConsumerUITests: XCTestCase {

    private let pincode = "__PINCODE__"
    private let slot = "__SLOT__"
    private let cartItems = __CART_ITEMS__
    private let appLabel = "__APP_LABEL__"
    /// Ceiling on the hunt for cart items, so it can't crowd out the cart screenshot.
    /// Covers the whole hunt — finding a screen with cards, the card path and the
    /// product-page path — not just one of the three.
    ///
    /// It gates *starting* another attempt, so the phase can overrun by however long
    /// the attempt in flight takes (a page load, a back, a re-settle: ~30s). That is
    /// deliberate — cutting an attempt off mid-way would leave the app on a random
    /// screen for the cart step.
    private let addBudgetSeconds: TimeInterval = 180
    private var addDeadline = Date.distantFuture
    private var addBudgetSpent: Bool { Date() >= addDeadline }

    private let app = XCUIApplication()
    private var notes: [String] = []

    /// Toolbar and tab-bar furniture. None of it is ever a category, product or
    /// content tile — tapping one of these by accident derails the whole run (the
    /// "Deliver To" row in particular opens the address sheet over everything).
    private let chrome = [
        "home", "shop", "offers", "cart", "bag", "basket", "deliver to", "delivery",
        "notifications_", "notification", "account_", "wishlist", "search", "mic.",
        "heart", "options", "increasequantity", "decreasequantity", "dismiss_icon",
        "use my current location", "address", "retry", "scroll bar", "skip", "menu",
        "hamburger", "back", "close", "okay", "got it", "selected"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
        app.launch()
        relaunchFromHomeScreen()
    }

    /// Launching from the test runner leaves a "◀ <app>" breadcrumb in the status bar
    /// (very visible on iPad), which has no business being in an App Store screenshot.
    /// Relaunching from the home screen clears it.
    private func relaunchFromHomeScreen() {
        guard !appLabel.isEmpty else { return }
        app.terminate()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons[appLabel]
        if icon.waitForExistence(timeout: 6), icon.isHittable {
            icon.tap()
        } else {
            app.launch()
        }
    }

    // MARK: - The run

    func testCaptureAppStoreScreenshots() {
        stage("app launching")
        _ = app.wait(for: .runningForeground, timeout: 90)
        dismissBlockers()

        // The splash screen means the tree is empty for the first several seconds.
        // Everything below depends on the home page actually being on screen.
        _ = waitForContent("launch", maxSeconds: 90)

        stage("setting the delivery address to \(pincode)")
        if setDeliveryAddress() {
            stage("address set")
        } else {
            notes.append("could not set the delivery address — listings may be empty")
            stage("address NOT set — carrying on")
        }

        // Confirming an address raises a popup that has to be acknowledged.
        if dismissPopup(timeout: 12) { stage("dismissed the confirmation popup") }

        // waitForContent returns false only for the error screen, so this is "the home
        // page is real" rather than "the home page is fully settled".
        if waitForContent("home") {
            capture("01_home")
        } else {
            notes.append("home is stuck on an error — no home screenshot")
        }

        stage("opening a category")
        if openCategory() {
            if waitForContent("category") { capture("02_category") }
        } else {
            notes.append("no category page reached")
            stage("no category page found")
        }

        stage("opening a product")
        if openProduct() {
            if waitForContent("product") { capture("03_product") }
            goBack()
            _ = waitForContent("listing", maxSeconds: 30)
        } else {
            notes.append("no product page reached")
            stage("no product page found")
        }

        stage("adding \(cartItems) products to the cart")
        let added = addProductsToCart(target: cartItems)
        stage("added \(added) product(s)")
        if added == 0 { notes.append("nothing could be added to the cart") }

        stage("opening the cart")
        if openCart() {
            if waitForContent("cart") { capture("04_cart") }
        } else {
            notes.append("no cart page reached")
            stage("no cart page found")
        }

        stage("done")
        if !notes.isEmpty {
            print("SCREENSHOT_NOTES:" + notes.joined(separator: " | "))
        }
    }

    /// Progress markers. XCTest activities are guaranteed to reach the xcodebuild
    /// log, which is what the terminal streams — so the run never looks frozen.
    /// Deliberately not also `print()`ed: that produced every step twice.
    private func stage(_ name: String) {
        XCTContext.runActivity(named: "STEP " + name) { _ in }
    }

    /// Banners and promo tiles can deep-link out to Safari. If that happens the
    /// screenshot would be of the wrong app entirely — this genuinely produced a
    /// Safari start page filed as "02_category".
    @discardableResult
    private func returnToAppIfLeft() -> Bool {
        guard app.state != .runningForeground else { return false }
        stage("a link opened outside the app — returning")
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 20)
        settle(3)
        // Whatever opened the link is still on the nav stack behind us.
        goBack()
        settle(2)
        return true
    }

    private func capture(_ name: String) {
        // Never capture another app's UI.
        returnToAppIfLeft()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(slot)__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        stage("captured \(name)")
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - Element lookup
    //
    // Predicate queries throughout: one snapshot per call instead of walking every
    // element in Swift, which was both slow and drowned the log.

    private func filtered(_ base: XCUIElementQuery, contains needles: [String],
                          excluding: [String] = []) -> XCUIElementQuery {
        var parts: [NSPredicate] = []
        if !needles.isEmpty {
            parts.append(NSCompoundPredicate(orPredicateWithSubpredicates:
                needles.map { NSPredicate(format: "label CONTAINS[c] %@", $0) }))
        }
        for token in excluding {
            parts.append(NSPredicate(format: "NOT (label CONTAINS[c] %@)", token))
        }
        guard !parts.isEmpty else { return base }
        return base.matching(NSCompoundPredicate(andPredicateWithSubpredicates: parts))
    }

    private func exists(_ base: XCUIElementQuery, contains needles: [String]) -> Bool {
        return filtered(base, contains: needles).firstMatch.exists
    }

    private func tap(_ base: XCUIElementQuery, contains needles: [String],
                     excluding: [String] = [], timeout: TimeInterval = 2) -> Bool {
        let element = filtered(base, contains: needles, excluding: excluding).firstMatch
        guard element.waitForExistence(timeout: timeout) else { return false }
        return tapElement(element)
    }

    /// Taps through `isHittable == false`, which this app hits constantly: cards
    /// below the fold and controls under a sheet still respond to a coordinate tap.
    private func tapElement(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        let onScreen = frame.width > 1 && frame.height > 1 && window.intersects(frame)

        // Decorative images often have no valid activation point, and merely *asking*
        // such an element for `isHittable` raises "Activation point invalid…", which
        // fails the entire test. Go straight to screen coordinates for those.
        if element.elementType == .image {
            guard onScreen else { return false }
            tapPoint(CGPoint(x: frame.midX, y: frame.midY))
            return true
        }

        if element.isHittable {
            element.tap()
            return true
        }
        guard onScreen else { return false }
        tapPoint(CGPoint(x: frame.midX, y: frame.midY))
        return true
    }

    /// A tap in screen space — never consults the element, so it cannot raise.
    private func tapPoint(_ point: CGPoint) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: point.x, dy: point.y))
            .tap()
    }

    /// Tab strips are not consistent: iPhone gets a real UITabBar at the bottom, iPad
    /// renders the same tabs as a pill along the top (so `app.tabBars` is empty), and
    /// the labels are per-app — this org calls its categories tab "Shop".
    ///
    /// So: look inside a tab bar if one exists, otherwise match the same labels
    /// anywhere in the top or bottom strip. The position filter matters — a home-page
    /// banner reading "SHOP NOW" would otherwise win over the "Shop" tab.
    private func tabButton(matching needles: [String]) -> XCUIElement? {
        let bar = app.tabBars.firstMatch
        if bar.exists {
            let button = filtered(bar.buttons, contains: needles).firstMatch
            if button.exists { return button }
        }

        let window = app.windows.firstMatch.frame
        guard window.height > 0 else { return nil }
        let topStrip = window.minY + window.height * 0.16
        let bottomStrip = window.maxY - window.height * 0.16

        for button in filtered(app.buttons, contains: needles,
                               excluding: ["now", "add", "all products"]).allElementsBoundByIndex {
            guard button.exists else { continue }
            let midY = button.frame.midY
            if midY <= topStrip || midY >= bottomStrip { return button }
        }
        return nil
    }

    private func tapTab(contains needles: [String]) -> Bool {
        closeSheetIfOpen()
        guard let button = tabButton(matching: needles) else { return false }
        return tapElement(button)
    }

    /// Content tiles in this app carry no accessibility label, so they're found
    /// structurally: something big enough to be a card, inside the content area,
    /// that isn't chrome. `skip` walks past candidates already tried.
    private func tapContentCandidate(skip: Int = 0) -> Bool {
        let window = app.windows.firstMatch.frame
        guard window.height > 0 else { return false }
        let top = window.minY + window.height * 0.12
        let bottom = window.maxY - window.height * 0.08

        var candidates = filtered(app.buttons, contains: [], excluding: chrome).allElementsBoundByIndex
        candidates += app.images.allElementsBoundByIndex

        var seen = 0
        for element in candidates {
            guard element.exists else { continue }
            let frame = element.frame
            guard frame.height >= 44, frame.width >= 44 else { continue }
            guard frame.midY > top, frame.midY < bottom else { continue }
            if seen < skip {
                seen += 1
                continue
            }
            if tapElement(element) { return true }
        }
        return false
    }

    private func goBack() {
        // Only a real back affordance. Tapping the first nav-bar button blindly is
        // what opened the address sheet and wrecked the previous run.
        let backish = filtered(app.navigationBars.buttons, contains: ["back", "chevron", "arrow"])
        if backish.firstMatch.exists, tapElement(backish.firstMatch) {
            settle(2)
            return
        }
        // Interactive pop — a left-edge drag can't hit the wrong control.
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        left.press(forDuration: 0.05, thenDragTo: right)
        settle(2)
    }

    // MARK: - Blockers, popups, sheets, error screens

    private func dismissBlockers() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = ["Allow While Using App", "Allow Once", "Allow", "Okay", "OK", "Ok",
                     "Got it", "Continue", "Not Now", "Later", "Don't Allow", "Dismiss", "Cancel"]

        for source in [springboard, app] {
            var rounds = 0
            while rounds < 4 {
                let alert = source.alerts.firstMatch
                guard alert.exists else { break }
                var tapped = false
                for label in allow {
                    let button = alert.buttons[label]
                    if button.exists, button.isHittable {
                        button.tap()
                        tapped = true
                        break
                    }
                }
                if !tapped { break }
                rounds += 1
                settle(1)
            }
        }

        _ = tap(app.buttons, contains: ["skip", "maybe later", "no thanks"],
                excluding: ["address"], timeout: 0)
    }

    /// The app's alerts use "Okay" (`.cancel("Okay")`), which is neither "OK" nor a
    /// system permission label — so it needs handling in its own right.
    private func dismissPopup(timeout: TimeInterval) -> Bool {
        let preferred = ["Okay", "OK", "Ok", "Got it", "Continue", "Done", "Dismiss", "Close"]
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let alert = app.alerts.firstMatch
            if alert.exists {
                for label in preferred {
                    let button = alert.buttons[label]
                    if button.exists, button.isHittable {
                        button.tap()
                        settle(1.5)
                        return true
                    }
                }
                let onlyButton = alert.buttons.element(boundBy: 0)
                if onlyButton.exists, onlyButton.isHittable {
                    onlyButton.tap()
                    settle(1.5)
                    return true
                }
            }

            // Polled from waitForContent — stop at the cheap alert check there.
            if timeout <= 0 { return false }

            if tap(app.buttons, contains: ["okay", "got it"], excluding: ["address"], timeout: 0) {
                settle(1.5)
                return true
            }
            settle(1)
        } while Date() < deadline

        return false
    }

    /// Strictly the address selector — never "there is a text field on screen".
    /// Every listing has a Search box, and treating that as an open sheet had the
    /// test closing imaginary sheets on ordinary screens.
    private func addressSheetIsOpen() -> Bool {
        if exists(app.buttons, contains: ["use my current location"]) { return true }
        var parts: [NSPredicate] = []
        for placeholder in addressPlaceholders {
            parts.append(NSPredicate(format: "placeholderValue == %@", placeholder))
            parts.append(NSPredicate(format: "label CONTAINS[c] %@", placeholder))
        }
        return app.textFields
            .matching(NSCompoundPredicate(orPredicateWithSubpredicates: parts))
            .firstMatch.exists
    }

    /// A leftover address sheet covers the tab bar and blocks everything after it.
    private func closeSheetIfOpen() {
        guard addressSheetIsOpen() else { return }
        stage("closing a leftover address sheet")
        if tap(app.buttons, contains: ["cancel", "close", "cross"], timeout: 1) {
            settle(2)
            if !addressSheetIsOpen() { return }
        }
        let backish = filtered(app.navigationBars.buttons, contains: ["back", "chevron", "arrow"])
        if backish.firstMatch.exists, tapElement(backish.firstMatch) {
            settle(2)
            if !addressSheetIsOpen() { return }
        }
        // Drag the sheet down.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        settle(2)
    }

    /// NoHomeScreenView — "Something went wrong..." over a full-width Retry.
    private func showsErrorScreen() -> Bool {
        if exists(app.staticTexts, contains: ["something went wrong", "no internet",
                                              "unable to connect", "check your connection"]) {
            return true
        }
        return exists(app.buttons, contains: ["retry"]) && app.buttons.count <= 3
    }

    private func retryAfterError() -> Bool {
        guard showsErrorScreen() else { return false }
        stage("app is on the error screen — tapping Retry")
        guard tap(app.buttons, contains: ["retry"], timeout: 3) else { return false }
        settle(6)
        return true
    }

    // MARK: - Waiting for content

    /// Nothing is captured mid-load. Returns false when the screen never became
    /// usable — an error screen, or still moving when the budget ran out — so the
    /// caller can skip the shot rather than ship a spinner or a "Retry" button.
    private func waitForContent(_ label: String, maxSeconds: TimeInterval = 45) -> Bool {
        let started = Date()
        let deadline = started.addingTimeInterval(maxSeconds)
        var lastBytes = -1
        var lastCounts = (-1, -1, -1)
        var stableRounds = 0
        var retries = 0
        stage("waiting for \(label) to load")

        while Date() < deadline {
            if returnToAppIfLeft() { stableRounds = 0 }
            if app.alerts.firstMatch.exists { _ = dismissPopup(timeout: 0) }

            if showsErrorScreen() {
                stableRounds = 0
                if retries < 3, retryAfterError() {
                    retries += 1
                    continue
                }
                notes.append("\(label): app is showing 'Something went wrong'")
                stage("\(label): stuck on the error screen")
                return false
            }

            if loadersVisible() {
                stableRounds = 0
                settle(1.2)
                continue
            }

            let bytes = XCUIScreen.main.screenshot().pngRepresentation.count
            let counts = (app.images.count, app.staticTexts.count, placeholderCount())

            // Within 0.5% of the previous frame.
            let sizeSteady = lastBytes > 0 && abs(bytes - lastBytes) * 200 < lastBytes
            let countsSteady = counts == lastCounts

            if sizeSteady && countsSteady {
                stableRounds += 1
                if stableRounds >= 2 {
                    settle(0.6)
                    stage("\(label) loaded in \(Int(Date().timeIntervalSince(started)))s")
                    return true
                }
            } else {
                stableRounds = 0
            }

            lastBytes = bytes
            lastCounts = counts
            settle(1.2)
        }

        notes.append("\(label): still loading after \(Int(maxSeconds))s — captured as-is")
        return true
    }

    private func loadersVisible() -> Bool {
        if app.activityIndicators.firstMatch.exists { return true }
        return exists(app.otherElements, contains: ["skeleton", "shimmer", "loading"])
    }

    /// The app swaps in a named "placeholder_<theme>" asset until SDWebImage has the
    /// real image. Counting them is how "assets loaded" is actually detected — but it
    /// is a *stability* signal, not a gate: products with no image keep a placeholder
    /// forever, so waiting for zero never returns.
    private func placeholderCount() -> Int {
        let window = app.windows.firstMatch.frame
        var count = 0
        for image in filtered(app.images, contains: ["placeholder"]).allElementsBoundByIndex {
            guard image.exists else { continue }
            let frame = image.frame
            if frame.width > 8, frame.height > 8, window.intersects(frame) { count += 1 }
        }
        return count
    }

    // MARK: - Address

    private let addressPlaceholders = ["Search your location", "Enter your pincode", "Enter Pincode"]

    /// The toolbar row reads "Deliver To, <full address>", so the applied pincode is
    /// verifiable rather than assumed.
    private func addressApplied() -> Bool {
        return exists(app.buttons, contains: [pincode]) || exists(app.staticTexts, contains: [pincode])
    }

    private func addressApplied(within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            _ = dismissPopup(timeout: 0)
            if addressApplied() { return true }
            settle(2)
        } while Date() < deadline
        return false
    }

    /// Stock and product availability are location-dependent, so this has to land
    /// before anything is captured.
    ///
    /// The order matters. LocationSearchView only runs its search when the field is
    /// in the `isTextPresent: false` state, so a field still holding the preset
    /// address will never produce suggestions no matter what gets typed into it.
    /// Clear it first — the trailing dismiss button both empties the text and drops
    /// the stored address — then type, then take the suggestion.
    private func setDeliveryAddress() -> Bool {
        if addressApplied() {
            stage("address is already set to \(pincode)")
            return true
        }

        for attempt in 1...3 {
            if !addressSheetIsOpen() {
                guard openAddressSelector() else {
                    settle(3)
                    continue
                }
                settle(3)
                dismissBlockers()
            }

            guard let field = addressField(timeout: 6) else {
                stage("address attempt \(attempt): no input field appeared")
                continue
            }

            if applyPincode(to: field) {
                // The toolbar label refreshes only once the home page has reloaded
                // behind the sheet, so give it a real window rather than a beat.
                if addressApplied(within: 25) { return true }
                notes.append("pincode entered but the toolbar still shows the old address")
                return true
            }
            stage("address attempt \(attempt) failed — retrying")
        }
        return false
    }

    private func openAddressSelector() -> Bool {
        let skip = ["add new", "address book", "my address"]
        let needles = ["deliver to", "delivering to", "select address", "select delivery",
                       "addressselector", "set location"]
        if tap(app.buttons, contains: needles, excluding: skip, timeout: 4) { return true }
        if tap(app.staticTexts, contains: needles, excluding: skip, timeout: 1) { return true }
        if tap(app.otherElements, contains: needles, excluding: skip, timeout: 1) { return true }
        return false
    }

    private func addressField(timeout: TimeInterval) -> XCUIElement? {
        var parts: [NSPredicate] = []
        for placeholder in addressPlaceholders {
            parts.append(NSPredicate(format: "placeholderValue == %@", placeholder))
            parts.append(NSPredicate(format: "label CONTAINS[c] %@", placeholder))
        }
        let field = app.textFields
            .matching(NSCompoundPredicate(orPredicateWithSubpredicates: parts))
            .firstMatch
        let found = timeout > 0 ? field.waitForExistence(timeout: timeout) : field.exists
        if found { return field }

        let any = app.textFields.firstMatch
        if any.exists { return any }
        return nil
    }

    private func fieldText(_ field: XCUIElement) -> String {
        let value = (field.value as? String) ?? ""
        // XCUITest reports the placeholder as the value of an empty field.
        if addressPlaceholders.contains(value) { return "" }
        return value
    }

    private func applyPincode(to field: XCUIElement) -> Bool {
        clearAddressField(field)

        let before = suggestionLabels()

        guard field.exists else { return false }
        field.tap()
        // typeText silently goes nowhere if the field never took focus.
        if !app.keyboards.element.waitForExistence(timeout: 6) {
            field.tap()
            _ = app.keyboards.element.waitForExistence(timeout: 4)
        }
        field.typeText(pincode)

        // 0.5s debounce, then an MKLocalSearch round trip.
        settle(4)

        if pickSuggestion(excluding: before, below: field) {
            settle(2)
            _ = dismissPopup(timeout: 10)
            if app.alerts.count == 0 {
                _ = tap(app.buttons, contains: ["confirm", "proceed", "save", "select this"],
                        excluding: ["address book", "add new"], timeout: 1)
                _ = dismissPopup(timeout: 6)
            }
            settle(2)
            return true
        }

        // Pincode-only mode (no maps key on the org): the trailing button commits it.
        if tap(app.buttons, contains: ["add"], excluding: ["address", "new", "added"], timeout: 2) {
            settle(3)
            _ = dismissPopup(timeout: 8)
            return true
        }

        notes.append("typed \(pincode) but neither a suggestion nor an Add button appeared")
        return false
    }

    /// The trailing dismiss button clears the text *and* the stored address, which is
    /// what re-arms the suggestion query. Falls back to backspacing the field.
    private func clearAddressField(_ field: XCUIElement) {
        if fieldText(field).isEmpty { return }

        if tap(app.buttons, contains: ["dismiss", "clear", "cross"],
               excluding: ["address book"], timeout: 2) {
            settle(2)
        }
        if fieldText(field).isEmpty { return }

        let existing = fieldText(field)
        if !existing.isEmpty {
            field.tap()
            settle(1)
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4))
            settle(1)
        }
        if !fieldText(field).isEmpty {
            notes.append("could not clear the preset address before typing the pincode")
        }
    }

    private func suggestionLabels() -> Set<String> {
        var labels: Set<String> = []
        for button in app.buttons.allElementsBoundByIndex where button.exists {
            labels.insert(button.label)
        }
        return labels
    }

    /// The suggestion dropdown is a stack of buttons under the field, labelled with
    /// the place's landmark — so it's whatever button is new, sits below the field,
    /// and isn't the current-location shortcut.
    private func pickSuggestion(excluding before: Set<String>, below field: XCUIElement) -> Bool {
        let skip = ["current location", "use my location", "dismiss", "clear", "search",
                    "cancel", "close", "delivery", "address"]
        let fieldBottom = field.exists ? field.frame.maxY : 0

        var fallback: XCUIElement?
        for button in app.buttons.allElementsBoundByIndex {
            guard button.exists else { continue }
            let label = button.label
            let lower = label.lowercased()
            guard label.count > 5 else { continue }
            guard !skip.contains(where: { lower.contains($0) }) else { continue }
            guard button.frame.minY >= fieldBottom - 1 else { continue }

            // A suggestion carrying the pincode is the best possible match.
            if label.contains(pincode) {
                return tapElement(button)
            }
            if !before.contains(label), fallback == nil {
                fallback = button
            }
        }

        if let fallback {
            return tapElement(fallback)
        }
        return false
    }

    // MARK: - Navigation

    /// What the categories tab is called varies per app — "Shop" here, "Categories"
    /// elsewhere — and some themes have no such tab at all.
    private let categoryTabNames = ["categor", "shop", "explore", "browse",
                                    "collection", "catalog", "catalogue"]

    private func openCategory() -> Bool {
        if tapTab(contains: categoryTabNames) {
            settle(2)
            if !returnToAppIfLeft() { return true }
        }

        // Themes without a categories tab expose them through the side menu.
        if tap(app.buttons, contains: ["hamburger", "menu", "sidemenu"], timeout: 2) {
            settle(3)
            if tapContentCandidate(), !returnToAppIfLeft() { return true }
            goBack()
        }

        // Last resort: a category tile on the home screen. Skip past anything that
        // turns out to be a banner pointing at the web.
        for attempt in 0..<3 {
            guard tapContentCandidate(skip: attempt) else { break }
            settle(3)
            if returnToAppIfLeft() { continue }
            return true
        }
        return false
    }

    /// A product page is the one place with a full-width add-to-cart; listings show
    /// the icon-only quantity stepper instead. "Buy now" also holds for a product
    /// already in the cart, whose add control has become a stepper.
    private func isProductPage() -> Bool {
        return exists(app.buttons, contains: ["add to cart", "add to bag", "buy now"])
    }

    /// The product page's navigation-bar title, used to avoid re-opening something
    /// already added.
    private func currentProductTitle() -> String {
        let bar = app.navigationBars.firstMatch
        guard bar.exists else { return "" }
        if !bar.identifier.isEmpty { return bar.identifier }
        let title = bar.staticTexts.firstMatch
        return title.exists ? title.label : ""
    }

    private func productCardsVisible() -> Bool {
        return exists(app.buttons, contains: ["increasequantity", "options"])
    }

    /// A product card's tap target is its image, which sits above the add control —
    /// so the add controls are used as anchors and the tap lands just above one.
    ///
    /// Targeting `app.images` directly reads better and was tried, but it regressed:
    /// the images on a listing include decorative ones whose frames don't correspond
    /// to a card, and product pages stopped being reached. The anchor is less elegant
    /// and more reliable — the add control is only ever on a real product card.
    ///
    /// The cost is that the 90pt offset is a guess: it lands inside the card in one
    /// column and can miss in another, which is why the cart usually ends up with
    /// fewer items than SCREENSHOT_CART_ITEMS asks for.
    private func tapProductCard(skip: Int = 0) -> Bool {
        let anchors = filtered(app.buttons, contains: ["increasequantity", "options"],
                               excluding: ["decrease"]).allElementsBoundByIndex
        // No add controls means this isn't a listing — bail before paying for the
        // image scan below, which is the expensive part of this function.
        guard !anchors.isEmpty else { return false }

        let window = app.windows.firstMatch.frame
        guard window.height > 0 else { return false }

        // Product photos, as candidate tap targets.
        let photos = app.images.allElementsBoundByIndex
            .filter { $0.exists && $0.frame.width >= 50 && $0.frame.height >= 50 }
            .map { $0.frame }

        var seen = 0
        for anchor in anchors {
            guard anchor.exists else { continue }
            let a = anchor.frame
            guard a.height > 1 else { continue }

            // The photo belonging to *this* card: directly above the add control and
            // horizontally spanning it. Anything else in the row is a different card.
            var target: CGPoint?
            var bestBottom = -CGFloat.greatestFiniteMagnitude
            for photo in photos {
                guard photo.maxY <= a.minY + 2 else { continue }
                guard a.midX >= photo.minX - 8, a.midX <= photo.maxX + 8 else { continue }
                guard a.minY - photo.maxY < 260 else { continue }
                if photo.maxY > bestBottom {
                    bestBottom = photo.maxY
                    target = CGPoint(x: photo.midX, y: photo.midY)
                }
            }

            // Fall back to a fixed offset above the control when the card has no
            // image of its own.
            let point = target ?? CGPoint(x: a.midX, y: a.minY - 90)
            guard window.contains(point), point.y > window.minY + window.height * 0.12 else { continue }

            if seen < skip {
                seen += 1
                continue
            }
            tapPoint(point)
            return true
        }
        return false
    }

    /// Two levels deep: the category grid leads to a listing, and the listing's cards
    /// lead to the product page. Tapping a grid tile alone never reaches a PDP.
    private func openProduct() -> Bool {
        for level in 0..<3 {
            if productCardsVisible() {
                for attempt in 0..<3 {
                    guard tapProductCard(skip: attempt) else { break }
                    settle(3)
                    if returnToAppIfLeft() { continue }
                    if showsErrorScreen() { _ = retryAfterError() }
                    if isProductPage() { return true }
                    goBack()
                    settle(2)
                }
            }
            guard level < 2, tapContentCandidate(skip: level) else { break }
            settle(3)
            if returnToAppIfLeft() { continue }
            if showsErrorScreen() { _ = retryAfterError() }
            if isProductPage() { return true }
            _ = waitForContent("listing", maxSeconds: 30)
        }
        return false
    }

    /// Only simple products carry an add control on the card. Variant products show
    /// "N options" instead, and those can only be added from the product page.
    private func addableCardsVisible() -> Bool {
        return exists(app.buttons, contains: ["increasequantity"])
    }

    /// The cart shot needs items, and items come from a screen that has cards on it.
    ///
    /// Aims for cards with an add control, not merely any product cards. A listing
    /// full of variant products ("N options") has no add control at all, and settling
    /// for it meant every item had to be added the slow way through its product page.
    /// The home rails almost always carry simple, one-tap products.
    private func ensureProductCardsVisible() -> Bool {
        if addableCardsVisible() { return true }
        stage("looking for products that can be added from the card")

        // The tab bar is hidden inside a pushed stack, so surface first.
        popToRoot()
        if tapTab(contains: ["home"]) {
            _ = waitForContent("home", maxSeconds: 30)
            if addableCardsVisible() { return true }
            // Rails further down the home page usually have them even when the
            // first screenful doesn't.
            for _ in 0..<3 {
                if addBudgetSpent { break }
                guard app.scrollViews.firstMatch.exists else { break }
                app.scrollViews.firstMatch.swipeUp()
                settle(2)
                if addableCardsVisible() { return true }
            }
        }
        if addBudgetSpent { return productCardsVisible() }
        if openCategory() {
            _ = waitForContent("listing", maxSeconds: 25)
            if addableCardsVisible() { return true }
        }
        if addBudgetSpent { return productCardsVisible() }
        if tapContentCandidate() {
            _ = waitForContent("listing", maxSeconds: 25)
        }
        // Nothing one-tap anywhere — the product-page path can still work.
        return addableCardsVisible() || productCardsVisible()
    }

    /// Surface out of a pushed stack so the tab strip is reachable again. Keyed on the
    /// Home tab rather than `app.tabBars`, which doesn't exist on iPad.
    private func popToRoot() {
        for _ in 0..<2 {
            if tabButton(matching: ["home"]) != nil { return }
            goBack()
        }
    }

    private func addProductsToCart(target: Int) -> Int {
        addDeadline = Date().addingTimeInterval(addBudgetSeconds)

        guard ensureProductCardsVisible() else {
            notes.append("no product cards on screen to add from")
            return 0
        }

        // Only worth trying the card path when a card actually has an add control;
        // on a variant-only listing it just burns a minute finding nothing.
        var added = addableCardsVisible() ? addFromCards(target: target) : 0
        if added >= target { return added }

        // Whatever is left is probably a variant product ("N options"), which has no
        // add control on the card — but its product page always has "Add To Cart".
        var attempt = 0
        var scrolls = 0
        var cursor = 0
        var addedTitles: Set<String> = []

        while added < target && attempt < target * 3 {
            if addBudgetSpent {
                notes.append("stopped adding after \(Int(addBudgetSeconds))s with \(added) of \(target)")
                break
            }
            attempt += 1
            // The cursor advances on every attempt, successful or not — keying it to
            // the number added just re-opened the same card forever. When the visible
            // cards run out, scroll and start from the top of the new ones.
            if !tapProductCard(skip: cursor) {
                if scrolls < 3, app.scrollViews.firstMatch.exists {
                    app.scrollViews.firstMatch.swipeUp()
                    settle(2)
                    scrolls += 1
                    cursor = 0
                    continue
                }
                break
            }
            cursor += 1
            settle(3)
            if returnToAppIfLeft() { continue }
            if showsErrorScreen() { _ = retryAfterError() }

            // The tap missed the card and we never left the listing. Going "back"
            // here pops out of the listing entirely, which used to unwind the whole
            // navigation and burn the budget — stay put and try the next card.
            guard isProductPage() else { continue }

            // A product already in the cart shows a stepper instead of "Add To Cart",
            // so re-opening one is a wasted attempt — skip by title.
            let title = currentProductTitle()
            if !title.isEmpty, addedTitles.contains(title) {
                goBack()
                settle(2)
                continue
            }

            if tap(app.buttons, contains: ["add to cart", "add to bag"],
                   excluding: ["added"], timeout: 5) {
                added += 1
                if !title.isEmpty { addedTitles.insert(title) }
                stage("added from the product page (\(added)/\(target))")
                settle(3)
                dismissBlockers()
            }
            goBack()
            settle(3)
        }
        return added
    }

    /// Simple products: tap the add control straight on the card.
    private func addFromCards(target: Int) -> Int {
        var added = 0
        var rounds = 0
        var usedFrames: [CGRect] = []

        while added < target && rounds < target + 3 && !addBudgetSpent {
            rounds += 1
            let adders = filtered(app.buttons, contains: ["increasequantity"],
                                  excluding: ["decrease"]).allElementsBoundByIndex

            var tapped = false
            for button in adders {
                guard button.exists else { continue }
                let frame = button.frame
                // Prefer a different product each time rather than bumping one.
                if usedFrames.contains(where: { abs($0.midX - frame.midX) < 6 && abs($0.midY - frame.midY) < 6 }) {
                    continue
                }
                if tapElement(button) {
                    usedFrames.append(frame)
                    tapped = true
                    break
                }
            }

            if !tapped {
                // Nothing addable in view — scroll once for more cards, then give up
                // and let the product-page path handle it.
                if rounds <= 2, app.scrollViews.firstMatch.exists {
                    app.scrollViews.firstMatch.swipeUp()
                    settle(2)
                    continue
                }
                break
            }

            added += 1
            stage("added from a card (\(added)/\(target))")
            settle(2)
            dismissBlockers()
        }
        return added
    }

    private func isCartPage() -> Bool {
        settle(2)
        if exists(app.staticTexts, contains: ["subtotal", "grand total", "place order",
                                              "proceed to", "your cart", "my cart",
                                              "cart is empty", "checkout", "order summary",
                                              "bill details", "coupon", "continue shopping",
                                              "delivery charge", "item total"]) {
            return true
        }
        return exists(app.buttons, contains: ["checkout", "place order", "proceed to",
                                              "continue shopping"])
    }

    /// Landing on the cart is the tab tap; the marker check is only used to annotate,
    /// because cart wording varies per theme and a failed match previously threw away
    /// a perfectly good screen.
    private func openCart() -> Bool {
        closeSheetIfOpen()
        let names = ["cart", "bag", "basket"]

        if tapTab(contains: names) {
            settle(2)
            returnToAppIfLeft()
            if !isCartPage() { notes.append("cart tab tapped but no cart wording matched") }
            return true
        }
        if tap(app.buttons, contains: names, excluding: ["add"], timeout: 3) {
            settle(2)
            returnToAppIfLeft()
            if !isCartPage() { notes.append("cart opened via toolbar but no cart wording matched") }
            return true
        }
        // The tab strip can be hidden deep in a stack — pop back out and try again.
        goBack()
        settle(2)
        if tapTab(contains: names) { return true }
        return isCartPage()
    }
}
SWIFT

# Type-check the generated test before handing it to xcodebuild — a mistake here
# would otherwise surface fifteen minutes later as a confusing build failure.
sed -e "s/__PINCODE__/$PINCODE/g" -e "s/__SLOT__/probe/g" -e "s/__CART_ITEMS__/$SCREENSHOT_CART_ITEMS/g" \
    "$WORK_DIR/UITestTemplate.swift" > "$WORK_DIR/probe.swift"

SIM_PLATFORM="$(xcrun --sdk iphonesimulator --show-sdk-platform-path 2>/dev/null || true)"
if [ -d "$SIM_PLATFORM/Developer/Library/Frameworks/XCTest.framework" ]; then
    xcrun -sdk iphonesimulator swiftc -typecheck \
        -target arm64-apple-ios17.0-simulator \
        -F "$SIM_PLATFORM/Developer/Library/Frameworks" \
        -I "$SIM_PLATFORM/Developer/usr/lib" \
        "$WORK_DIR/probe.swift" >"$WORK_DIR/parse.log" 2>&1 \
        || { grep -E "error:" "$WORK_DIR/parse.log" | head -5 >&2; die "Generated UI test does not compile."; }
    log "UI test type-checks"
else
    xcrun swiftc -parse "$WORK_DIR/probe.swift" >"$WORK_DIR/parse.log" 2>&1 \
        || { grep -E "error:" "$WORK_DIR/parse.log" | head -5 >&2; die "Generated UI test does not parse."; }
    log "UI test parses (XCTest framework not found for a full type-check)"
fi

# 6.5" slot: iPhone 14 Plus is 1284x2778. 13" slot: iPad Pro 13-inch is 2064x2752.
if [ -n "$IPHONE_UDID" ]; then
    capture_device "$IPHONE_UDID" "$SCREENSHOT_IPHONE_DEVICE" "6.5-inch" "1284x2778"
fi
if [ -n "$IPAD_UDID" ]; then
    capture_device "$IPAD_UDID" "$SCREENSHOT_IPAD_DEVICE" "13-inch" "2064x2752"
fi

# ── Step 6: revert everything ──

step "Step 6/6 · Cleaning up"

teardown

echo ""
if [ "$CAPTURED_TOTAL" -eq 0 ]; then
    die "No screenshots were captured. See the log above."
fi
echo "🎉 $CAPTURED_TOTAL screenshot(s) for $APP_NAME"
echo "   $OUT_DIR"
find "$OUT_DIR" -name "*.png" | sort | sed "s|^$OUT_DIR/|   ├─ |"
echo ""
log "$REPO is back to its committed state — config reset, sources reverted, simulators closed."
if [ "$SKIP_GIT" != true ] && [ -n "${ORIGINAL_BRANCH:-}" ] && [ "$ORIGINAL_BRANCH" != "$SCREENSHOT_BRANCH" ]; then
    log "Still on '$SCREENSHOT_BRANCH' — 'git -C \"$REPO\" checkout $ORIGINAL_BRANCH' to go back."
fi
