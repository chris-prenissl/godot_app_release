#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=""
LOG=""
LOCK_HELD=0

usage() {
  cat <<'EOF'
release.sh — export a Godot project and ship the artifact with fastlane.

USAGE
  release.sh <run.env path> [log path]
  release.sh --help

ARGUMENTS
  <run.env path>   Required. The generated environment file describing one run.
  [log path]       Optional. Where to write the log. Defaults to
                   <project>/<LOGS_DIR>/release_<TARGET_ID>_<timestamp>.log

DESCRIPTION
  Everything this script needs comes from the run.env file, so there are no
  project-specific constants in here. The App Release plugin writes that file
  into <project>/.release_tools/ each time you confirm a release in the editor,
  which means running this by hand repeats the last release the panel set up.

  The version name and build number are patched into export_presets.cfg by the
  plugin before this script starts, so editing VERSION or BUILD in run.env
  changes what fastlane reports but NOT what Godot actually exports.

BUILD MODES  (BUILD_MODE in run.env)
  GODOT_EXPORT               Godot produces the artifact.
  REGENERATE_NATIVE_PROJECT  Android: reinstall the build template, then export.
                             iOS: regenerate the Xcode project, then xcodebuild.
  PCK_ONLY                   iOS: refresh the PCK, then xcodebuild the existing
                             hand-maintained Xcode project.
                             Android: same as GODOT_EXPORT.

  Android needs no build step of its own — an Android export runs Gradle inside
  Godot and yields the finished APK or AAB. iOS does, because a Godot iOS export
  writes an .xcodeproj rather than an .ipa.

EXIT STATUS
  0   success
  1   a phase failed
  2   bad invocation, or another release already holds the lock

  The status is also written to "<log path>.exit" on every exit path; the
  editor panel polls for that file to decide when the run is over.

FILES
  <project>/.release_tools/run.env   this script's only input
  <project>/<LOGS_DIR>/              logs, plus the .release.lock directory
  <project>/fastlane/                Gemfile and lanes used by the upload step

EXAMPLE
  addons/app_release/scripts/release.sh .release_tools/run.env logs/manual.log
EOF
}

die() {
  echo "ERROR: $1" >&2
  shift
  if [ $# -gt 0 ]; then printf '       %s\n' "$@" >&2; fi
  exit 1
}

die_usage() {
  echo "ERROR: $1" >&2
  shift
  if [ $# -gt 0 ]; then printf '       %s\n' "$@" >&2; fi
  exit 2
}

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    die "$name is not set in $ENV_FILE." \
        "Check the target's configuration in release_config.tres."
  fi
}

require_macos() {
  [ "$(uname -s)" = "Darwin" ] || \
    die "iOS releases require macOS with Xcode installed." \
        "Android targets do run on this machine."
}

wants_help() {
  [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]
}


# Installs on_exit as the cleanup handler for every way this script can end.
#
# EXIT covers finishing and failing; INT and TERM cover the panel's Stop button.
arm_exit_trap() {
  trap on_exit EXIT INT TERM
}


parse_args() {
  local help_hint="Run '$(basename "$0") --help' for usage."

  if [ $# -lt 1 ]; then
    die_usage "no run.env given." "$help_hint"
  fi
  if [ $# -gt 2 ]; then
    die_usage "expected at most 2 arguments, got $#." "$help_hint"
  fi

  ENV_FILE="$1"
  LOG="${2:-}"

  if [ ! -f "$ENV_FILE" ]; then
    die_usage "run.env not found: $ENV_FILE"
  fi
}

load_environment() {
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a

  require_var PROJECT_ROOT
  require_var TARGET_ID
  require_var PLATFORM
  require_var STORE
  require_var LANE
  require_var EXPORT_PRESET
  require_var BUILD_MODE
  require_var ARTIFACT_PATH
  require_var VERSION
  require_var BUILD

  [ -n "${EXTRA_PATH:-}" ] && export PATH="$EXTRA_PATH"

  ROOT="$PROJECT_ROOT"
  LOGS_DIR="${LOGS_DIR:-logs}"
  KEEP_LOGS="${KEEP_LOGS:-20}"
  LOCK_DIR="$ROOT/$LOGS_DIR/.release.lock"
  ARTIFACT="$ROOT/$ARTIFACT_PATH"
  DEBUG_BUILD="${DEBUG_BUILD:-0}"
}

setup_logging() {
  mkdir -p "$ROOT/$LOGS_DIR"
  [ -n "$LOG" ] || LOG="$ROOT/$LOGS_DIR/release_${TARGET_ID}_$(date +%Y%m%d_%H%M%S).log"
  mkdir -p "$(dirname "$LOG")"
  rm -f "$LOG.exit"

  if [ -t 1 ]; then
    exec > >(tee -a "$LOG") 2>&1
  else
    exec >>"$LOG" 2>&1
  fi
}

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local lock_pid
    lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      die_usage "another release is already running (pid $lock_pid)." \
                "Wait for it to finish, or stop it from the Godot Release panel."
    fi
    echo "Removing stale lock from pid ${lock_pid:-unknown}"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || die "cannot create lock directory $LOCK_DIR"
  fi
  LOCK_HELD=1
  echo $$ > "$LOCK_DIR/pid"
}

on_exit() {
  local status=$?
  if [ "${LOCK_HELD:-0}" -eq 1 ]; then
    rm -rf "${LOCK_DIR:-}" || true
  fi
  local target="${TARGET_ID:-unknown}"
  if [ $status -eq 0 ]; then
    echo "=== RELEASE ${target} SUCCEEDED $(date '+%Y-%m-%d %H:%M:%S') ==="
  else
    echo "=== RELEASE ${target} FAILED (exit $status) $(date '+%Y-%m-%d %H:%M:%S') ==="
  fi
  if [ -n "${LOG:-}" ]; then
    echo "Log: $LOG"
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
    echo "$status" > "$LOG.exit"
  fi
}

rotate_logs() {
  local old_logs
  old_logs="$(ls -t "$ROOT/$LOGS_DIR"/release_*.log 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) || true)"
  if [ -n "$old_logs" ]; then
    while IFS= read -r old_log; do
      [ -n "$old_log" ] || continue
      [ "$old_log" = "$LOG" ] && continue
      echo "Removing old log: $(basename "$old_log")"
      rm -f "$old_log" "$old_log.exit"
    done <<< "$old_logs"
  fi
  local old_notes
  for old_notes in "$ROOT/.release_tools"/.release_notes_*; do
    [ -e "$old_notes" ] || continue
    [ "$old_notes" = "${RELEASE_NOTES_FILE:-}" ] && continue
    rm -f "$old_notes"
  done
}

resolve_groups() {
  RELEASE_GROUPS="$(printf '%s' "${RELEASE_GROUPS:-}" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -v '^$' \
    | paste -sd, - || true)"

  if [ -z "$RELEASE_GROUPS" ]; then
    echo "Tester groups: none (internal testers / no group assignment)"
    return
  fi
  if echo "$RELEASE_GROUPS" | grep -Eq '^[0-9,]+$'; then
    die_usage "tester groups '$RELEASE_GROUPS' look like numbers, not group aliases." \
              "Expected Firebase/TestFlight group names like 'internal-testers'."
  fi
  export RELEASE_GROUPS
  echo "Tester groups: $RELEASE_GROUPS"
}

stage_release_notes() {
  if [ -z "${RELEASE_NOTES_FILE:-}" ] || [ ! -s "${RELEASE_NOTES_FILE:-}" ]; then
    return
  fi
  export RELEASE_NOTES_FILE
  echo "Release notes ($RELEASE_NOTES_FILE):"
  sed 's/^/  | /' "$RELEASE_NOTES_FILE"
  echo

  if [ "$PLATFORM" = "android" ] && [ -n "${PLAY_CHANGELOGS_DIR:-}" ]; then
    mkdir -p "$ROOT/$PLAY_CHANGELOGS_DIR"
    cp "$RELEASE_NOTES_FILE" "$ROOT/$PLAY_CHANGELOGS_DIR/$BUILD.txt"
  fi

  if [ -n "${RELEASE_NOTES_DIR:-}" ]; then
    mkdir -p "$ROOT/$RELEASE_NOTES_DIR"
    {
      echo "# $VERSION (build $BUILD)"
      echo
      cat "$RELEASE_NOTES_FILE"
      echo
    } > "$ROOT/$RELEASE_NOTES_DIR/$VERSION-$BUILD.md"
    echo "Notes archived: $RELEASE_NOTES_DIR/$VERSION-$BUILD.md"
  fi
}

resolve_godot_bin() {
  [ -n "${GODOT_BIN:-}" ] || GODOT_BIN="$(command -v godot || true)"
  [ -n "$GODOT_BIN" ] || die "godot binary not found." \
                             "Set a Godot binary override in release_config.tres."
  [ -x "$GODOT_BIN" ] || die "godot binary is not executable: $GODOT_BIN"
  echo "Godot: $GODOT_BIN"
}

godot_export() {
  local flag="--export-release"
  [ "$DEBUG_BUILD" -eq 1 ] && flag="--export-debug"
  echo "Exporting preset \"$EXPORT_PRESET\" ($flag) -> $ARTIFACT_PATH"
  mkdir -p "$(dirname "$ARTIFACT")"
  "$GODOT_BIN" --headless --path "$ROOT" "$flag" "$EXPORT_PRESET" "$ARTIFACT"
}

godot_export_pack() {
  require_var PCK_PATH
  local pck="$ROOT/$PCK_PATH"
  echo "Exporting pack only -> $PCK_PATH"
  mkdir -p "$(dirname "$pck")"
  "$GODOT_BIN" --headless --path "$ROOT" --export-pack "$EXPORT_PRESET" "$pck"
}

install_android_build_template() {
  echo "Reinstalling the Android build template"
  "$GODOT_BIN" --headless --path "$ROOT" --install-android-build-template
}

build_ios_with_xcode() {
  require_macos
  require_var NATIVE_PROJECT_PATH
  require_var XCODE_SCHEME
  require_var IOS_EXPORT_OPTIONS

  local project="$ROOT/$NATIVE_PROJECT_PATH"
  [ -d "$project" ] || die "Xcode project not found: $project" \
                           "Run the target once in \"Regenerate native project\" mode."

  local config="Release"
  [ "$DEBUG_BUILD" -eq 1 ] && config="Debug"
  local archive="${project%.xcodeproj}.xcarchive"
  local export_dir="$ROOT/.release_tools/xcode-export"

  echo "xcodebuild archive ($config, version $VERSION build $BUILD)"
  xcodebuild archive \
    -project "$project" \
    -scheme "$XCODE_SCHEME" \
    -configuration "$config" \
    -destination "generic/platform=iOS" \
    -archivePath "$archive" \
    -allowProvisioningUpdates \
    "MARKETING_VERSION=$VERSION" \
    "CURRENT_PROJECT_VERSION=$BUILD"

  echo "xcodebuild -exportArchive"
  rm -rf "$export_dir"
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$ROOT/$IOS_EXPORT_OPTIONS" \
    -exportPath "$export_dir" \
    -allowProvisioningUpdates

  local exported_ipa
  exported_ipa="$(find "$export_dir" -maxdepth 1 -name '*.ipa' 2>/dev/null | head -n 1 || true)"
  [ -n "$exported_ipa" ] || die "xcodebuild -exportArchive produced no .ipa in $export_dir"
  mkdir -p "$(dirname "$ARTIFACT")"
  mv "$exported_ipa" "$ARTIFACT"
  rm -rf "$export_dir"
}


# Android never needs a build step of its own: `godot --export-release` on an
# Android preset with gradle_build enabled reuses the installed build template
# and runs Gradle itself, producing the finished APK or AAB.
#
# iOS does, and cannot avoid it: a Godot iOS export writes an .xcodeproj, not an
# .ipa, so xcodebuild is what actually produces the artifact.
export_project() {
  resolve_godot_bin

  case "$BUILD_MODE" in
    GODOT_EXPORT)
      [ "$PLATFORM" != "ios" ] || die \
        "BUILD_MODE=GODOT_EXPORT cannot work for iOS." \
        "A Godot iOS export produces an .xcodeproj, a .pck and an Info.plist," \
        "never an .ipa. Pick a build mode that runs xcodebuild."
      godot_export
      ;;
    REGENERATE_NATIVE_PROJECT)
      if [ "$PLATFORM" = "android" ]; then
        install_android_build_template
        godot_export
      else
        require_macos
        godot_export
        build_ios_with_xcode
      fi
      ;;
    PCK_ONLY)
      if [ "$PLATFORM" = "android" ]; then
        godot_export
      else
        godot_export_pack
        build_ios_with_xcode
      fi
      ;;
    *)
      die_usage "unknown BUILD_MODE: $BUILD_MODE"
      ;;
  esac

  [ -f "$ARTIFACT" ] || die "expected artifact missing after export: $ARTIFACT"
  echo "Export done: $ARTIFACT ($(du -h "$ARTIFACT" | cut -f1))"
}

run_fastlane() {
  export ARTIFACT_PATH_ABS="$ARTIFACT"
  case "${ARTIFACT##*.}" in
    ipa) export IPA_PATH="$ARTIFACT" ;;
    apk) export APK_PATH="$ARTIFACT" ;;
    aab) export AAB_PATH="$ARTIFACT" ;;
  esac

  cd "$ROOT"
  [ -f Gemfile ] || die "no Gemfile in $ROOT." \
                        "Press \"Install release scripts\" in the Release panel's Setup tab."
  if ! bundle check >/dev/null 2>&1; then
    echo "Installing ruby gems (bundle install)..."
    bundle install
  fi
  echo "Running fastlane $PLATFORM $LANE"
  bundle exec fastlane "$PLATFORM" "$LANE"
}

main() {
  if wants_help "$@"; then
    usage
    exit 0
  fi

  arm_exit_trap
  parse_args "$@"
  load_environment
  setup_logging
  acquire_lock

  echo "=== RELEASE ${TARGET_ID} STARTED $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "Project:    $ROOT"
  echo "Target:     ${TARGET_LABEL:-$TARGET_ID} ($STORE)"
  echo "Preset:     $EXPORT_PRESET [$PLATFORM]"
  echo "Build mode: $BUILD_MODE"
  echo "Version:    ${VERSION:-?} (build ${BUILD:-?})"
  [ "$DEBUG_BUILD" -eq 1 ] && echo "Build type: debug" || echo "Build type: release"

  rotate_logs
  resolve_groups
  stage_release_notes
  export_project
  run_fastlane
}

main "$@"
