#!/usr/bin/env bash
# Content pipeline gate (Phase 11, spec Section 13).
# Proves an external agent with FILE WRITES ALONE can add every extensible
# content type: add files → import (the "next build" step) → verify in-game
# → cleanup. Exits non-zero on any failure.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SCENE="res://scenes/dev/content_smoke_test.tscn"

echo "== 1/4 add throwaway content (pure file writes)"
timeout 120 "$GODOT" --headless "$SCENE" -- add 2>/dev/null | grep "CONTENT ADD" || { echo "ADD FAILED"; exit 1; }

echo "== 2/4 import (the 'next build/load' step — no editor interaction)"
timeout 300 "$GODOT" --headless --import >/dev/null 2>&1 || true

echo "== 3/4 verify everything appears through normal loaders"
set +e
timeout 200 "$GODOT" --headless "$SCENE" -- verify 2>&1 | grep -E "CONTENT TEST|FAIL:"
VERIFY=${PIPESTATUS[0]}
set -e

echo "== 4/4 cleanup"
timeout 120 "$GODOT" --headless "$SCENE" -- cleanup 2>/dev/null | grep "CONTENT CLEANUP" || { echo "CLEANUP FAILED"; exit 1; }
timeout 300 "$GODOT" --headless --import >/dev/null 2>&1 || true

exit "$VERIFY"
