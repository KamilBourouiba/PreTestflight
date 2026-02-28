# PreTestflight

**Product:** PreTestflight  
**Author:** Kamil Bourouiba

Command-line tool to capture code state, compare saves and repositories, and produce LLM prompt templates plus XCTest (UI and unit) test stubs to speed up Apple TestFlight reviews. No irreversible operations (no `git push`, no deletions outside temp/output directories).

---

## Table of contents

- [Dependencies](#dependencies)
- [File structure](#file-structure)
- [Quick start](#quick-start)
- [Global flags](#global-flags)
- [Optional LLM (LM Studio)](#optional-llm-lm-studio)
- [Subcommands & examples](#subcommands--examples)
  - [--save](#--save---create-a-timestamped-save)
  - [--compare-saves](#--compare-saves---compare-two-save-archives)
  - [--compare-repos](#--compare-repos---compare-two-repositories)
  - [--generate-ui-tests](#--generate-ui-tests---generate-ui-test-stubs)
  - [--generate-xctests](#--generate-xctests---generate-unit-test-stubs)
  - [--suggest](#--suggest---testflight-review-suggestions)
- [Full workflow example](#full-workflow-example)
- [Security and limits](#security-and-limits)

---

## Dependencies

| Type | Tools |
|------|--------|
| **Required** | `git`, `zip`, `unzip`, `diff`, `mktemp`, `sed`, `awk` (Xcode Command Line Tools or macOS) |
| **Optional** | `jq` — used for robust JSON; if missing, script uses `printf`/`awk` and warns |
| **For `--use-llm`** | `curl`, `jq` (required for local LLM calls) |

```bash
brew install jq   # recommended
```

---

## File structure

```
PreTestflight/
├── pretestflight.sh          # Main executable script
├── prompts/
│   ├── ui_test_prompt.txt    # Prompt template for UI tests
│   ├── xctest_prompt.txt     # Prompt template for unit tests
│   └── suggestion_prompt.txt # Prompt template for review suggestions
├── .gitignore
└── README.md
```

---

## Quick start

```bash
# Clone or download, then from the repo root:
chmod +x pretestflight.sh
./pretestflight.sh --help

# Create a snapshot of your current git state (run from inside your app repo):
cd /path/to/your/ios-app
/path/to/PreTestflight/pretestflight.sh --save -o ./snapshots --message "Before submission"

# Compare two snapshots:
/path/to/PreTestflight/pretestflight.sh --compare-saves ./snapshots/PreTestflight_1.zip ./snapshots/PreTestflight_2.zip

# Generate UI test stubs (no LLM):
/path/to/PreTestflight/pretestflight.sh --generate-ui-tests --output ./Tests/UITests/Stubs.swift

# With LM Studio running, generate tests via LLM:
/path/to/PreTestflight/pretestflight.sh --use-llm --generate-xctests --module MyApp
```

---

## Global flags

| Flag | Description |
|------|-------------|
| `--verbose` | More logging to stderr |
| `--temp-dir DIR` | Use DIR for temporary files |
| `--keep-temp` | Do not remove temp dirs on exit (debugging) |
| `--use-llm` | Call local LLM to generate tests/suggestions |
| `--lm-url URL` | LLM API URL (default: `http://localhost:1234/api/v1/chat`) |
| `--lm-model MODEL` | Model name (default: `deepseek/deepseek-r1-0528-qwen3-8b`) |
| `--help` | Show usage |

---

## Optional LLM (LM Studio)

The script can call a **local LLM** (e.g. [LM Studio](https://lmstudio.ai/)) for `--generate-ui-tests`, `--generate-xctests`, and `--suggest`. This is **optional and for convenience** — you can change the script for your own provider (OpenAI, Ollama, etc.) by editing `call_lm`, `LM_URL`, and `LM_MODEL` in `pretestflight.sh`.

**LM Studio setup:** Start LM Studio, load a model, and start the local server (default port 1234).

**Request format (LM Studio native API):**

```bash
curl http://localhost:1234/api/v1/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek/deepseek-r1-0528-qwen3-8b",
    "system_prompt": "You generate Swift XCTest code...",
    "input": "Prompt content (e.g. prompts/ui_test_prompt.txt)"
  }'
```

If the LLM call fails or returns empty, the script falls back to default stubs/suggestions.

---

## Subcommands & examples

### `--save` — Create a timestamped save

Creates a zip containing: git archive of HEAD, uncommitted patch, `metadata.json`, `summary.json`. **Run from inside a git repository.** No commit or push.

**Examples:**

```bash
# Save to current directory
./pretestflight.sh --save

# Save to a directory with a message (stored in metadata.json)
./pretestflight.sh --save -o ./snapshots --message "Before refactor"
```

**Output example:**

```
Created: ./PreTestflight_20250228_143022.zip
```

**Zip contents:**

| File | Description |
|------|-------------|
| `archive.zip` | Committed tree (HEAD) |
| `save.patch` | Uncommitted changes (or note if clean) |
| `metadata.json` | branch, commit, author, timestamp, message, working_tree_clean |
| `summary.json` | file_count, total_size_bytes, working_tree_clean |

**metadata.json example:**

```json
{
  "branch": "main",
  "commit": "a1b2c3d",
  "author": "Kamil Bourouiba",
  "timestamp": "20250228_143022",
  "message": "Before refactor",
  "working_tree_clean": false
}
```

---

### `--compare-saves` — Compare two save archives

Compares two PreTestflight zip files. Writes a human-readable summary, a unified diff file, and a JSON summary. Exit code **0** = no functional changes, **non-zero** = functional changes.

**Example:**

```bash
./pretestflight.sh --compare-saves ./snapshots/PreTestflight_20250227.zip ./snapshots/PreTestflight_20250228.zip
```

**Output example:**

```
=== Compare Saves Summary ===
A: ./snapshots/PreTestflight_20250227.zip
B: ./snapshots/PreTestflight_20250228.zip

--- Added ---
(new files if any)

--- Removed ---
(removed files if any)

--- Modified ---
./archive.zip
./metadata.json

JSON summary: ./compare_saves_summary.json
```

**Generated files:** `compare_saves_summary.txt`, `compare_saves_diff.txt`, `compare_saves_summary.json`

**compare_saves_summary.json example:**

```json
{
  "added_count": 0,
  "removed_count": 0,
  "modified_count": 2,
  "functional_changes": true
}
```

---

### `--compare-repos` — Compare two repositories

Compares two repo trees (local paths or clones). Optionally use `--refA` / `--refB` for specific refs. Groups changes by impact: UI, Network, Entitlements, Info.plist, Resources, Localization, Tests, Other.

**Examples:**

```bash
# Compare two local repo directories
./pretestflight.sh --compare-repos /path/to/repoA /path/to/repoB

# With specific refs
./pretestflight.sh --compare-repos /path/to/repoA /path/to/repoB --refA main --refB develop
```

**Output example:**

```
=== Compare Repos ===
Repo A: /path/to/repoA (HEAD)
Repo B: /path/to/repoB (HEAD)

--- UI / View ---
Views/LoginView.swift

--- Network / API ---
Services/APIClient.swift

--- Entitlements ---
(none)

--- Info.plist / Config ---
Info.plist

--- Resources ---
Assets.xcassets/AppIcon.appiconset/

--- Localization ---
(none)

--- Tests ---
Tests/LoginTests.swift

--- Other ---
README.md

JSON: ./compare_repos_summary.json
```

**Generated files:** `compare_repos_report.txt`, `compare_repos_summary.json`

---

### `--generate-ui-tests` — Generate UI test stubs

Writes Swift XCTest UI test stubs (or LLM-generated tests if `--use-llm`). Default output: `./generated/ui_tests.swift`. Optional: `--screen-map FILE` (JSON/YAML of screens and accessibility IDs).

**Examples:**

```bash
# Stub only (no LLM)
./pretestflight.sh --generate-ui-tests
./pretestflight.sh --generate-ui-tests --output ./Tests/UITests/Stubs.swift

# With LM Studio (generates from prompts/ui_test_prompt.txt)
./pretestflight.sh --use-llm --generate-ui-tests --screen-map screens.json
```

**Output example:**

```
UI test stubs written to: ./generated/ui_tests.swift
# or with --use-llm:
UI tests (LLM) written to: ./generated/ui_tests.swift
```

---

### `--generate-xctests` — Generate unit test stubs

Writes Swift XCTest unit test stubs (or LLM-generated if `--use-llm`). Default output: `./generated/xctest_unit_tests.swift`. Use `--module MODULE` for `@testable import`.

**Examples:**

```bash
# Stub only
./pretestflight.sh --generate-xctests --module MyApp

# With LM Studio
./pretestflight.sh --use-llm --generate-xctests --module MyApp --output ./Tests/Unit/Stubs.swift
```

**Output example:**

```
Unit test stubs written to: ./generated/xctest_unit_tests.swift
# or with --use-llm:
Unit tests (LLM) written to: ./generated/xctest_unit_tests.swift
```

---

### `--suggest` — TestFlight review suggestions

Produces prioritized suggestions (privacy keys, permissions, deterministic launch, demo content, accessibility) in text and JSON. Optional: `--context FILE` (e.g. list of changed files or Info.plist excerpt). With `--use-llm`, the LLM generates suggestions from `prompts/suggestion_prompt.txt` and context.

**Examples:**

```bash
# Default suggestions (no LLM)
./pretestflight.sh --suggest

# With LLM and context
./pretestflight.sh --use-llm --suggest --context changed_files.txt --output ./review/suggestions
```

**Output example:**

```
Suggestions written to: ./generated/suggestions.txt and ./generated/suggestions.json
# or with --use-llm:
Suggestions (LLM) written to: ./generated/suggestions.txt
```

---

## Full workflow example

End-to-end flow for an iOS app before TestFlight:

```bash
# 1. Save current state (from your app repo)
cd ~/MyApp
/path/to/PreTestflight/pretestflight.sh --save -o ./snapshots --message "v1.0 before review"

# 2. (Optional) Save again after changes to compare later
# ... make changes ...
./pretestflight.sh --save -o ./snapshots --message "v1.0 after fixes"

# 3. Compare two snapshots
/path/to/PreTestflight/pretestflight.sh --compare-saves \
  ./snapshots/PreTestflight_20250228_120000.zip \
  ./snapshots/PreTestflight_20250228_140000.zip

# 4. Generate test stubs (add to your test target)
/path/to/PreTestflight/pretestflight.sh --generate-ui-tests --output ./MyAppUITests/PreTestflightStubs.swift
/path/to/PreTestflight/pretestflight.sh --generate-xctests --module MyApp --output ./MyAppTests/PreTestflightStubs.swift

# 5. Get review suggestions (optionally with LLM)
/path/to/PreTestflight/pretestflight.sh --suggest --output ./review/suggestions
# Or with LM Studio:
/path/to/PreTestflight/pretestflight.sh --use-llm --suggest --context ./snapshots/compare_repos_report.txt --output ./review/suggestions
```

---

## Security and limits

- **No destructive ops:** No `git push`, no commits, no deletions outside temp/output dirs.
- **Temp dirs:** Created with `mktemp -d`, removed on exit unless `--keep-temp`.
- **Outputs:** All under current directory or the path given by `-o` / `--output` per subcommand.

---

## License

Use and adapt as needed. Product: PreTestflight · Author: Kamil Bourouiba.
