#!/usr/bin/env bash
#
# PreTestflight showcase: run ~10 commands (local + LM) using sample_projects.
# Run from repo root: ./examples/run_showcase.sh
# For LM commands (7–10), start LM Studio on port 1234 first.
#
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
PRETESTFLIGHT="$ROOT/pretestflight.sh"
OUT="$ROOT/out"
mkdir -p "$OUT"

echo "=== PreTestflight showcase (local + LM) ==="
echo "Root: $ROOT"
echo ""

# Ensure sample projects are git repos so --save works
for proj in sample_projects/project_a sample_projects/project_b; do
  if [[ ! -d "$ROOT/$proj/.git" ]]; then
    echo "Initializing git in $proj..."
    (cd "$ROOT/$proj" && git init && git add -A && git commit -m "Initial commit")
  fi
done

echo "--- 1. LOCAL: Save project_a ---"
cd "$ROOT/sample_projects/project_a"
"$PRETESTFLIGHT" --save -o "$OUT" --message "project_a snapshot"
cd "$ROOT"
ZIP_A="$(ls -t "$OUT"/PreTestflight_*.zip 2>/dev/null | head -1)"
echo "  -> $ZIP_A"
echo ""

echo "--- 2. LOCAL: Save project_b ---"
cd "$ROOT/sample_projects/project_b"
"$PRETESTFLIGHT" --save -o "$OUT" --message "project_b snapshot"
cd "$ROOT"
ZIP_B="$(ls -t "$OUT"/PreTestflight_*.zip 2>/dev/null | head -1)"
echo "  -> $ZIP_B"
echo ""

echo "--- 3. LOCAL: Compare two saves ---"
# Oldest first, newest second for A vs B
ZIP_FIRST="$(ls -t "$OUT"/PreTestflight_*.zip 2>/dev/null | tail -1)"
ZIP_SECOND="$(ls -t "$OUT"/PreTestflight_*.zip 2>/dev/null | head -1)"
"$PRETESTFLIGHT" --compare-saves "$ZIP_FIRST" "$ZIP_SECOND" || true
echo ""

echo "--- 4. LOCAL: Compare two repos ---"
"$PRETESTFLIGHT" --compare-repos "$ROOT/sample_projects/project_a" "$ROOT/sample_projects/project_b" || true
echo ""

echo "--- 5. LOCAL: Generate UI test stubs ---"
"$PRETESTFLIGHT" --generate-ui-tests --output "$OUT/generated_ui_tests.swift"
echo ""

echo "--- 6. LOCAL: Generate unit test stubs ---"
"$PRETESTFLIGHT" --generate-xctests --module ProjectA --output "$OUT/generated_unit_tests.swift"
echo ""

echo "--- 7. LOCAL: Generate suggestions ---"
"$PRETESTFLIGHT" --suggest --output "$OUT/suggestions"
echo ""

echo "--- 8. LM: Generate UI tests (requires LM Studio on :1234) ---"
"$PRETESTFLIGHT" --use-llm --generate-ui-tests --output "$OUT/llm_ui_tests.swift" 2>&1 || echo "  (LM failed or skipped)"
echo ""

echo "--- 9. LM: Generate unit tests ---"
"$PRETESTFLIGHT" --use-llm --generate-xctests --module ProjectA --output "$OUT/llm_unit_tests.swift" 2>&1 || echo "  (LM failed or skipped)"
echo ""

echo "--- 10. LM: Generate suggestions ---"
"$PRETESTFLIGHT" --use-llm --suggest --context "$ROOT/compare_repos_report.txt" --output "$OUT/suggestions_llm" 2>&1 || echo "  (LM failed or skipped)"
echo ""

echo "=== Showcase done. Outputs in: $OUT ==="
ls -la "$OUT" 2>/dev/null || true
