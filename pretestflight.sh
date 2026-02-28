#!/usr/bin/env bash
#
# PreTestflight - Capture code state, compare saves/repos, generate LLM prompt templates
# and XCTest stubs to speed Apple TestFlight reviews.
# Product: PreTestflight
# Author: Kamil Bourouiba
#
# Usage: pretestflight.sh [global-flags] <subcommand> [options]
# No network pushes or irreversible repository operations.
#

set -e

# --- Product and version ---
readonly PRODUCT_NAME="PreTestflight"
readonly SCRIPT_VERSION="1.0.0"

# --- Global state (overridden by flags) ---
VERBOSE=0
KEEP_TEMP=0
OUTPUT_BASE_DIR="${PWD}"
CUSTOM_TEMP_DIR=""
TEMP_DIRS=()
# Optional LLM (e.g. LM Studio); for convenience only — change URL/model for your provider
USE_LLM=0
LM_URL="http://localhost:1234/api/v1/chat"
LM_MODEL="deepseek/deepseek-r1-0528-qwen3-8b"

# --- Script directory for resolving prompts path ---
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi
PROMPTS_DIR="${SCRIPT_DIR}/prompts"

# --- Dependency check: required commands ---
check_deps() {
  local missing=""
  for cmd in git zip unzip diff mktemp sed awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing="${missing} $cmd"
    fi
  done
  if [[ -n "$missing" ]]; then
    echo "Error: missing required tools:${missing}" >&2
    echo "Install them (e.g. via Xcode Command Line Tools or Homebrew) and retry." >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "Warning: 'jq' not found. JSON will be built with printf/awk; install jq for robust JSON." >&2
  fi
}

# --- Optional: jq available? ---
has_jq() {
  command -v jq >/dev/null 2>&1
}

# --- Logging ---
log_verbose() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "$@" >&2
  fi
}

# --- JSON helpers: write a simple JSON value (no jq) ---
json_escape() {
  sed "s/\\\/\\\\/g; s/\"/\\\\\"/g; s/$(printf '\t')/\\\\t/g; s/$(printf '\n')/\\\\n/g" <<< "$1"
}
json_str() {
  printf '"%s"' "$(json_escape "$1")"
}
# Build small JSON objects with key/value pairs; values must be pre-escaped or numeric.
json_obj() {
  local out=""
  while [[ $# -ge 2 ]]; do
    local k="$1" v="$2"
    shift 2
    [[ -n "$out" ]] && out="${out},"
    out="${out}$(json_str "$k"):${v}"
  done
  printf '{%s}' "$out"
}

# --- Cleanup temp dirs on exit (unless --keep-temp) ---
cleanup_temp_dirs() {
  if [[ "$KEEP_TEMP" -eq 0 ]]; then
    for d in "${TEMP_DIRS[@]}"; do
      if [[ -d "$d" ]]; then
        log_verbose "Removing temp dir: $d"
        rm -rf "$d"
      fi
    done
    TEMP_DIRS=()
  fi
}

# --- Register temp dir for cleanup ---
register_temp() {
  TEMP_DIRS+=("$1")
}

# --- Get a temp directory ---
get_temp_dir() {
  local parent="${CUSTOM_TEMP_DIR:-$TMPDIR}"
  [[ -z "$parent" ]] && parent="/tmp"
  local d
  d="$(mktemp -d "${parent}/PreTestflight.XXXXXXXX")"
  register_temp "$d"
  echo "$d"
}

# --- Optional LLM call (LM Studio–compatible API: model, system_prompt, input) ---
# Response: JSON with "output" array of { "type": "message", "content": "..." }
# You can change this function to support another provider (OpenAI, Ollama, etc.).
call_lm() {
  local system_prompt="$1"
  local input_content="$2"
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: --use-llm requires 'curl'. Install it or run without --use-llm." >&2
    return 1
  fi
  if ! has_jq; then
    echo "Error: --use-llm requires 'jq' to parse the API response. Install jq or run without --use-llm." >&2
    return 1
  fi
  local req_file resp_file
  req_file="$(mktemp)"
  resp_file="$(mktemp)"
  # Build request JSON (LM Studio native: model, system_prompt, input)
  jq -n \
    --arg model "$LM_MODEL" \
    --arg system "$system_prompt" \
    --arg input "$input_content" \
    '{ model: $model, system_prompt: $system, input: $input }' > "$req_file"
  log_verbose "Calling LLM at $LM_URL (model: $LM_MODEL)"
  if ! curl -s -S -X POST "$LM_URL" \
    --connect-timeout 5 --max-time 120 \
    -H "Content-Type: application/json" \
    -d @"$req_file" \
    -o "$resp_file" 2>&1; then
    echo "Error: LLM request failed. Is the server running at $LM_URL?" >&2
    rm -f "$req_file" "$resp_file"
    return 1
  fi
  # LM Studio: .output[] | select(.type=="message") | .content
  jq -r '[ .output[]? | select(.type == "message") | .content ] | join("")' "$resp_file" 2>/dev/null || true
  local ret=$?
  rm -f "$req_file" "$resp_file"
  return $ret
}

# --- Usage ---
usage() {
  cat << 'USAGE'
Usage: pretestflight.sh [global-flags] <subcommand> [options]

Global flags:
  --verbose         More logging to stderr
  --temp-dir DIR    Use DIR for temporary files
  --keep-temp       Do not remove temp dirs on exit (debug)
  --use-llm         Call local LLM (e.g. LM Studio) to generate content; optional, for convenience
  --lm-url URL      LLM API URL (default: http://localhost:1234/api/v1/chat)
  --lm-model MODEL  Model name (default: deepseek/deepseek-r1-0528-qwen3-8b)
  --help            Show this usage

Subcommands:

  --save [-o DIR] [--message "text"]
    Create a timestamped save (git archive + uncommitted patch + metadata)
    and package as PreTestflight_<timestamp>.zip. No commit/push.

  --compare-saves fileA.zip fileB.zip
    Compare two save zips; output summary, unified diff, and JSON.
    Exit 0 if no functional changes, nonzero otherwise.

  --compare-repos repoA repoB [--refA ref] [--refB ref]
    Compare two repo trees (shallow clone); list changes by impact and output JSON.

  --generate-ui-tests [--screen-map FILE] [--output FILE]
    Save UI test prompt to prompts/ui_test_prompt.txt and write UI test stubs
    (default: ./generated/ui_tests.swift).

  --generate-xctests [--module MODULE] [--output FILE]
    Save unit test prompt to prompts/xctest_prompt.txt and write unit test stubs.

  --suggest [--context FILE] [--output FILE]
    Save suggestion prompt to prompts/suggestion_prompt.txt and write
    prioritized review suggestions (text + JSON).
USAGE
}

# ---------- Subcommand: --save ----------
cmd_save() {
  local out_dir="$OUTPUT_BASE_DIR"
  local message=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o) out_dir="$2"; shift 2 ;;
      --message) message="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: not inside a git repository." >&2
    exit 1
  fi

  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  local save_name="PreTestflight_${timestamp}"
  local save_dir="${out_dir}/${save_name}"
  mkdir -p "$save_dir"

  # Git archive of current HEAD (zip)
  local archive_zip="${save_dir}/archive.zip"
  git archive --format=zip --output="$archive_zip" HEAD
  log_verbose "Created $archive_zip"

  # Uncommitted changes as patch
  local patch_file="${save_dir}/save.patch"
  if git diff --quiet && git diff --cached --quiet 2>/dev/null; then
    printf '# No uncommitted changes\n' > "$patch_file"
  else
    git diff > "$patch_file" 2>/dev/null || true
    git diff --cached >> "$patch_file" 2>/dev/null || true
  fi
  log_verbose "Created $patch_file"

  # Ignored files list (for metadata)
  local ignored_list=""
  while IFS= read -r line; do
    ignored_list="${ignored_list}${line}\n"
  done < <(git status --ignored --porcelain 2>/dev/null | awk '/^!!/ {print $2}' || true)

  # metadata.json: branch, commit, author, timestamp, message, ignored
  local branch commit_hash author
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")"
  commit_hash="$(git rev-parse HEAD 2>/dev/null)"
  author="$(git config user.name 2>/dev/null || echo "unknown")"
  local meta_file="${save_dir}/metadata.json"
  if has_jq; then
    jq -n \
      --arg b "$branch" \
      --arg c "$commit_hash" \
      --arg a "$author" \
      --arg t "$timestamp" \
      --arg m "$message" \
      --argjson clean "$(git diff --quiet 2>/dev/null && echo true || echo false)" \
      '{ branch: $b, commit: $c, author: $a, timestamp: $t, message: $m, working_tree_clean: $clean }' > "$meta_file"
  else
    local clean_val="false"
    git diff --quiet 2>/dev/null && clean_val="true"
    printf '%s\n' "$(json_obj "branch" "$(json_str "$branch")" "commit" "$(json_str "$commit_hash")" "author" "$(json_str "$author")" "timestamp" "$(json_str "$timestamp")" "message" "$(json_str "$message")" "working_tree_clean" "$clean_val")" > "$meta_file"
  fi

  # Summary JSON: file count, total size, working tree clean
  local file_count total_size
  file_count="$(find "$save_dir" -type f | wc -l | tr -d ' ')"
  total_size="$(find "$save_dir" -type f -exec stat -f %z {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')"
  local summary_file="${save_dir}/summary.json"
  local clean_summary="false"
  git diff --quiet 2>/dev/null && clean_summary="true"
  if has_jq; then
    jq -n \
      --argjson n "$file_count" \
      --argjson s "$total_size" \
      --argjson clean "$clean_summary" \
      '{ file_count: $n, total_size_bytes: $s, working_tree_clean: $clean }' > "$summary_file"
  else
    printf '{"file_count":%s,"total_size_bytes":%s,"working_tree_clean":%s}\n' \
      "$file_count" "$total_size" "$clean_summary" > "$summary_file"
  fi

  # Package into PreTestflight_<timestamp>.zip in output dir
  local zip_out="${out_dir}/${save_name}.zip"
  (cd "$out_dir" && zip -r "${save_name}.zip" "$save_name" -x "*.DS_Store")
  echo "Created: $zip_out"
  log_verbose "Save directory: $save_dir"
  exit 0
}

# ---------- Subcommand: --compare-saves ----------
cmd_compare_saves() {
  local zip_a="$1"
  local zip_b="$2"
  if [[ -z "$zip_a" || -z "$zip_b" ]]; then
    echo "Error: --compare-saves requires two zip files." >&2
    usage
    exit 1
  fi
  if [[ ! -f "$zip_a" ]]; then
    echo "Error: not a file: $zip_a" >&2
    exit 1
  fi
  if [[ ! -f "$zip_b" ]]; then
    echo "Error: not a file: $zip_b" >&2
    exit 1
  fi

  local tmp
  tmp="$(get_temp_dir)"
  local dir_a="${tmp}/A" dir_b="${tmp}/B"
  mkdir -p "$dir_a" "$dir_b"
  unzip -q -o "$zip_a" -d "$dir_a"
  unzip -q -o "$zip_b" -d "$dir_b"

  # Find the single top-level dir inside each zip (PreTestflight_*)
  local inner_a inner_b
  inner_a="$(find "$dir_a" -mindepth 1 -maxdepth 1 -type d | head -1)"
  inner_b="$(find "$dir_b" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [[ -z "$inner_a" ]] && inner_a="$dir_a"
  [[ -z "$inner_b" ]] && inner_b="$dir_b"

  local out_dir="${OUTPUT_BASE_DIR}"
  local summary_txt="${out_dir}/compare_saves_summary.txt"
  local diff_out="${out_dir}/compare_saves_diff.txt"
  local summary_json="${out_dir}/compare_saves_summary.json"

  # List files in each tree (relative to inner dir)
  local list_a="${tmp}/list_a.txt" list_b="${tmp}/list_b.txt"
  (cd "$inner_a" && find . -type f | sort) > "$list_a"
  (cd "$inner_b" && find . -type f | sort) > "$list_b"

  # Added = in B not in A; Removed = in A not in B; Modified = in both
  local added removed modified
  added="$(comm -23 "$list_b" "$list_a")"
  removed="$(comm -13 "$list_b" "$list_a")"
  modified=""
  while IFS= read -r f; do
    if [[ -f "${inner_b}/${f}" && -f "${inner_a}/${f}" ]]; then
      if ! diff -q "${inner_a}/${f}" "${inner_b}/${f}" >/dev/null 2>&1; then
        modified="${modified}${f}"$'\n'
      fi
    fi
  done < <(comm -12 "$list_a" "$list_b")
  modified="${modified% }"

  # Human-readable summary
  {
    echo "=== Compare Saves Summary ==="
    echo "A: $zip_a"
    echo "B: $zip_b"
    echo ""
    echo "--- Added ---"
    [[ -n "$added" ]] && echo "$added" || echo "(none)"
    echo ""
    echo "--- Removed ---"
    [[ -n "$removed" ]] && echo "$removed" || echo "(none)"
    echo ""
    echo "--- Modified ---"
    [[ -n "$modified" ]] && echo "$modified" || echo "(none)"
  } > "$summary_txt"
  cat "$summary_txt"

  # Unified diff for text files (skip binary)
  {
    echo "=== Unified diff (text files) ==="
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      local fa="${inner_a}/${f}" fb="${inner_b}/${f}"
      if [[ -f "$fa" && -f "$fb" ]]; then
        if file "$fa" | grep -q text 2>/dev/null; then
          diff -u "$fa" "$fb" || true
        fi
      fi
    done < <(comm -12 "$list_a" "$list_b")
  } > "$diff_out"
  log_verbose "Diff written to $diff_out"

  # Functional changes: we consider added/removed/modified as functional
  local add_count rem_count mod_count
  add_count="$(echo "$added" | grep -c . || true)"
  rem_count="$(echo "$removed" | grep -c . || true)"
  mod_count="$(echo "$modified" | grep -c . || true)"
  local functional_changes="false"
  [[ $add_count -gt 0 || $rem_count -gt 0 || $mod_count -gt 0 ]] && functional_changes="true"

  if has_jq; then
    jq -n \
      --argjson added "$add_count" \
      --argjson removed "$rem_count" \
      --argjson modified "$mod_count" \
      --argjson functional_changes "$functional_changes" \
      '{ added_count: $added, removed_count: $removed, modified_count: $modified, functional_changes: $functional_changes }' > "$summary_json"
  else
    # Build JSON by hand so functional_changes is boolean, not string
    printf '{"added_count":%s,"removed_count":%s,"modified_count":%s,"functional_changes":%s}\n' \
      "$add_count" "$rem_count" "$mod_count" "$functional_changes" > "$summary_json"
  fi
  echo ""
  echo "JSON summary: $summary_json"

  if [[ "$functional_changes" == "true" ]]; then
    exit 2
  fi
  exit 0
}

# ---------- Subcommand: --compare-repos ----------
cmd_compare_repos() {
  local repo_a="$1"
  local repo_b="$2"
  local ref_a="HEAD" ref_b="HEAD"
  shift 2 || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --refA) ref_a="$2"; shift 2 ;;
      --refB) ref_b="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$repo_a" || -z "$repo_b" ]]; then
    echo "Error: --compare-repos requires two repo paths." >&2
    usage
    exit 1
  fi

  local tmp
  tmp="$(get_temp_dir)"
  local dir_a="${tmp}/repoA" dir_b="${tmp}/repoB"
  mkdir -p "$dir_a" "$dir_b"

  # Shallow clone or copy; if path is local dir, copy to temp to avoid modifying
  if [[ -d "$repo_a" ]]; then
    cp -R "$repo_a" "$dir_a/repo"
  else
    git clone --depth 1 "$repo_a" "$dir_a/repo" 2>/dev/null || git clone "$repo_a" "$dir_a/repo"
  fi
  if [[ -d "$repo_b" ]]; then
    cp -R "$repo_b" "$dir_b/repo"
  else
    git clone --depth 1 "$repo_b" "$dir_b/repo" 2>/dev/null || git clone "$repo_b" "$dir_b/repo"
  fi

  local tree_a="${dir_a}/repo" tree_b="${dir_b}/repo"
  (cd "$tree_a" && git fetch --depth 1 origin "$ref_a" 2>/dev/null; git checkout "$ref_a" 2>/dev/null) || true
  (cd "$tree_b" && git fetch --depth 1 origin "$ref_b" 2>/dev/null; git checkout "$ref_b" 2>/dev/null) || true

  local list_a="${tmp}/listA.txt" list_b="${tmp}/listB.txt"
  (cd "$tree_a" && git ls-tree -r --name-only "$ref_a" 2>/dev/null) | sort > "$list_a"
  (cd "$tree_b" && git ls-tree -r --name-only "$ref_b" 2>/dev/null) | sort > "$list_b"

  local added removed modified
  added="$(comm -23 "$list_b" "$list_a")"
  removed="$(comm -13 "$list_b" "$list_a")"
  modified="$(comm -12 "$list_a" "$list_b")"

  # Group by likely impact
  local ui_files network_files entitlements plist resources localize test_files other
  ui_files=""; network_files=""; entitlements=""; plist=""; resources=""; localize=""; test_files=""; other=""
  for f in $removed $added; do
    case "$f" in
      *.storyboard|*.xib|*ViewController*) ui_files="${ui_files}${f}"$'\n' ;;
      *Network*|*API*|*URL*|*.plist) if [[ "$f" == *Info.plist ]] || [[ "$f" == *.plist ]]; then plist="${plist}${f}"$'\n'; else network_files="${network_files}${f}"$'\n'; fi ;;
      *.entitlements) entitlements="${entitlements}${f}"$'\n' ;;
      *Info.plist|*.plist) plist="${plist}${f}"$'\n' ;;
      *.xcassets|*.imageset|*.pdf) resources="${resources}${f}"$'\n' ;;
      *.lproj/*|*.strings) localize="${localize}${f}"$'\n' ;;
      *Test*|*Tests*|*Spec*) test_files="${test_files}${f}"$'\n' ;;
      *) other="${other}${f}"$'\n' ;;
    esac
  done
  for f in $modified; do
    case "$f" in
      *.storyboard|*.xib|*ViewController*) ui_files="${ui_files}${f}"$'\n' ;;
      *Network*|*API*) network_files="${network_files}${f}"$'\n' ;;
      *.entitlements) entitlements="${entitlements}${f}"$'\n' ;;
      *Info.plist|*.plist) plist="${plist}${f}"$'\n' ;;
      *.xcassets|*.imageset) resources="${resources}${f}"$'\n' ;;
      *.lproj/*|*.strings) localize="${localize}${f}"$'\n' ;;
      *Test*|*Tests*) test_files="${test_files}${f}"$'\n' ;;
      *) other="${other}${f}"$'\n' ;;
    esac
  done

  local out_dir="${OUTPUT_BASE_DIR}"
  local report_txt="${out_dir}/compare_repos_report.txt"
  local report_json="${out_dir}/compare_repos_summary.json"

  {
    echo "=== Compare Repos ==="
    echo "Repo A: $repo_a ($ref_a)"
    echo "Repo B: $repo_b ($ref_b)"
    echo ""
    echo "--- UI / View ---"
    echo "${ui_files:- (none)}"
    echo "--- Network / API ---"
    echo "${network_files:- (none)}"
    echo "--- Entitlements ---"
    echo "${entitlements:- (none)}"
    echo "--- Info.plist / Config ---"
    echo "${plist:- (none)}"
    echo "--- Resources ---"
    echo "${resources:- (none)}"
    echo "--- Localization ---"
    echo "${localize:- (none)}"
    echo "--- Tests ---"
    echo "${test_files:- (none)}"
    echo "--- Other ---"
    echo "${other:- (none)}"
  } > "$report_txt"
  cat "$report_txt"

  local add_c rem_c mod_c
  add_c="$(echo "$added" | grep -c . || true)"
  rem_c="$(echo "$removed" | grep -c . || true)"
  mod_c="$(echo "$modified" | grep -c . || true)"
  if has_jq; then
    jq -n \
      --argjson added "$add_c" \
      --argjson removed "$rem_c" \
      --argjson modified "$mod_c" \
      '{ added_count: $added, removed_count: $removed, modified_count: $modified }' > "$report_json"
  else
    printf '%s\n' "$(json_obj "added_count" "$add_c" "removed_count" "$rem_c" "modified_count" "$mod_c")" > "$report_json"
  fi
  echo "JSON: $report_json"
  exit 0
}

# ---------- Subcommand: --generate-ui-tests ----------
cmd_generate_ui_tests() {
  local screen_map="" out_file="${OUTPUT_BASE_DIR}/generated/ui_tests.swift"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --screen-map) screen_map="$2"; shift 2 ;;
      --output) out_file="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  mkdir -p "$(dirname "$out_file")"
  if [[ -f "${PROMPTS_DIR}/ui_test_prompt.txt" ]]; then
    log_verbose "UI test prompt is at prompts/ui_test_prompt.txt"
  fi

  if [[ "$USE_LLM" -eq 1 ]]; then
    local prompt_content
    prompt_content="$(< "${PROMPTS_DIR}/ui_test_prompt.txt")"
    if [[ -n "$screen_map" && -f "$screen_map" ]]; then
      prompt_content="${prompt_content}"$'\n\n'"Screen map (use for accessibility IDs and flows):"$'\n'"$(< "$screen_map")"
    fi
    if call_lm "You generate runnable Swift XCTest UI test code. Follow Apple HIG. Output only valid Swift code, no markdown." "$prompt_content" > "$out_file" && [[ -s "$out_file" ]]; then
      echo "UI tests (LLM) written to: $out_file"
    else
      echo "LLM call failed or empty response; writing stub instead." >&2
      write_ui_test_stub "$out_file"
    fi
  else
    write_ui_test_stub "$out_file"
    echo "UI test stubs written to: $out_file"
  fi
  exit 0
}

write_ui_test_stub() {
  local out_file="$1"
  cat > "$out_file" << 'STUB'
// Generated by PreTestflight - UI test stubs (fill using prompts/ui_test_prompt.txt)
// Product: PreTestflight, Author: Kamil Bourouiba

import XCTest

class PreTestflightUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = []
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func test_appLaunches() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func test_firstScreenVisible() throws {
        // Replace with your first screen accessibility identifier
        let firstScreen = app.otherElements["mainScreen"]
        XCTAssertTrue(firstScreen.waitForExistence(timeout: 5), "First screen should be visible")
    }

    func test_exampleFlow() throws {
        // Add flows using accessibility identifiers, e.g.:
        // app.buttons["loginButton"].tap()
        // XCTAssertTrue(app.staticTexts["welcomeLabel"].waitForExistence(timeout: 3))
    }
}
STUB
}

# ---------- Subcommand: --generate-xctests ----------
cmd_generate_xctests() {
  local module="" out_file="${OUTPUT_BASE_DIR}/generated/xctest_unit_tests.swift"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --module) module="$2"; shift 2 ;;
      --output) out_file="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -z "$module" ]] && module="YourModule"

  mkdir -p "$(dirname "$out_file")"
  if [[ -d "$PROMPTS_DIR" ]] && [[ -f "${PROMPTS_DIR}/xctest_prompt.txt" ]]; then
    log_verbose "Unit test prompt is at prompts/xctest_prompt.txt"
  fi

  if [[ "$USE_LLM" -eq 1 ]]; then
    local prompt_content
    prompt_content="$(< "${PROMPTS_DIR}/xctest_prompt.txt")"
    prompt_content="${prompt_content}"$'\n\n'"Module name: ${module}. Generate unit tests for this module."
    if call_lm "You generate Swift XCTest unit test code. Output only valid Swift code, no markdown. Use @testable import for the module under test." "$prompt_content" > "$out_file" && [[ -s "$out_file" ]]; then
      echo "Unit tests (LLM) written to: $out_file"
    else
      echo "LLM call failed or empty response; writing stub instead." >&2
      write_xctest_stub "$out_file" "$module"
    fi
  else
    write_xctest_stub "$out_file" "$module"
    echo "Unit test stubs written to: $out_file"
  fi
  exit 0
}

write_xctest_stub() {
  local out_file="$1" module="$2"
  cat > "$out_file" << STUB
// Generated by PreTestflight - Unit test stubs (fill using prompts/xctest_prompt.txt)
// Product: PreTestflight, Author: Kamil Bourouiba

import XCTest
@testable import $module

class PreTestflightUnitTests: XCTestCase {

    override func setUpWithError() throws { }

    override func tearDownWithError() throws { }

    func test_example() throws {
        XCTAssertTrue(true, "Replace with real assertions for your module")
    }
}
STUB
}

# ---------- Subcommand: --suggest ----------
cmd_suggest() {
  local context_file="" out_base="${OUTPUT_BASE_DIR}/generated/suggestions"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context) context_file="$2"; shift 2 ;;
      --output) out_base="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  mkdir -p "$(dirname "$out_base")"
  if [[ -d "$PROMPTS_DIR" ]] && [[ -f "${PROMPTS_DIR}/suggestion_prompt.txt" ]]; then
    log_verbose "Suggestion prompt is at prompts/suggestion_prompt.txt"
  fi

  local txt_out="${out_base}.txt"
  local json_out="${out_base}.json"

  if [[ "$USE_LLM" -eq 1 ]]; then
    local prompt_content
    prompt_content="$(< "${PROMPTS_DIR}/suggestion_prompt.txt")"
    if [[ -n "$context_file" && -f "$context_file" ]]; then
      prompt_content="${prompt_content}"$'\n\n'"Context (changed files / Info.plist):"$'\n'"$(< "$context_file")"
    fi
    if call_lm "You produce prioritized, actionable suggestions to reduce Apple TestFlight review time. Output both human-readable text and a JSON array of suggestions with title, affected_files, priority, patch_snippet, rationale." "$prompt_content" > "$txt_out" && [[ -s "$txt_out" ]]; then
      echo "Suggestions (LLM) written to: $txt_out"
      # Try to extract JSON block from LLM output into .json (optional)
      if has_jq; then
        sed -n '/\[{/,/}\]/p' "$txt_out" | jq -c '.' 2>/dev/null > "$json_out" || true
        [[ -s "$json_out" ]] && echo "JSON suggestions: $json_out"
      fi
    else
      echo "LLM call failed; writing default suggestions." >&2
      write_suggestions_default "$txt_out" "$json_out"
    fi
  else
    write_suggestions_default "$txt_out" "$json_out"
    echo "Suggestions written to: $txt_out and $json_out"
  fi
  exit 0
}

write_suggestions_default() {
  local txt_out="$1" json_out="$2"
  {
    echo "PreTestflight – Prioritized suggestions to speed Apple TestFlight review"
    echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "1. Privacy and permissions: Add all required Info.plist usage keys (e.g. NSCameraUsageDescription)."
    echo "2. Deterministic launch: Ensure first launch is review-friendly (skip or shorten onboarding if needed)."
    echo "3. Remove demo content: Strip test accounts and debug menus in release builds."
    echo "4. Accessibility: Add accessibilityIdentifier/labels and ensure 44pt touch targets."
    echo "5. Review hotspots: Document entitlements and network usage in privacy manifest if needed."
    echo ""
    echo "Use prompts/suggestion_prompt.txt with your context file for full LLM-generated suggestions. Use --use-llm to call your local LLM (e.g. LM Studio)."
  } > "$txt_out"
  if has_jq; then
    jq -n '[{"title":"Privacy keys","priority":"High","affected_files":["Info.plist"]},{"title":"Deterministic launch","priority":"High","affected_files":[]},{"title":"Remove demo content","priority":"Medium","affected_files":[]},{"title":"Accessibility","priority":"Medium","affected_files":[]}]' > "$json_out"
  else
    printf '%s\n' '[{"title":"Privacy keys","priority":"High"},{"title":"Deterministic launch","priority":"High"},{"title":"Remove demo content","priority":"Medium"},{"title":"Accessibility","priority":"Medium"}]' > "$json_out"
  fi
}

# ---------- Main ----------
main() {
  check_deps
  trap cleanup_temp_dirs EXIT

  # Parse global flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose) VERBOSE=1; shift ;;
      --temp-dir) CUSTOM_TEMP_DIR="$2"; shift 2 ;;
      --keep-temp) KEEP_TEMP=1; shift ;;
      --use-llm) USE_LLM=1; shift ;;
      --lm-url) LM_URL="$2"; shift 2 ;;
      --lm-model) LM_MODEL="$2"; shift 2 ;;
      --help) usage; exit 0 ;;
      --save)
        shift
        cmd_save "$@"
        return
        ;;
      --compare-saves)
        shift
        cmd_compare_saves "$@"
        return
        ;;
      --compare-repos)
        shift
        cmd_compare_repos "$@"
        return
        ;;
      --generate-ui-tests)
        shift
        cmd_generate_ui_tests "$@"
        return
        ;;
      --generate-xctests)
        shift
        cmd_generate_xctests "$@"
        return
        ;;
      --suggest)
        shift
        cmd_suggest "$@"
        return
        ;;
      *)
        echo "Error: unknown option or subcommand: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  usage
  exit 1
}

main "$@"
