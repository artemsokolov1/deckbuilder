#!/usr/bin/env bash
# Все автоматические проверки подряд. Любая ошибка скрипта в выводе — провал.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOG="$(mktemp)"
fail=0
run() {
  echo "== $1"
  "$GODOT" --headless --path . -s "$1" >"$LOG" 2>&1
  local code=$?
  grep -E "ok |FAIL|Итог|check done" "$LOG" | grep -vE "^\s+ok " | tail -n 5
  if [ $code -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error|FAIL" "$LOG"; then
    echo "!! провал: $1 (код $code)"; grep -E "SCRIPT ERROR|Parse Error|FAIL" "$LOG" | head -n 20
    fail=1
  fi
}
run tests/check_scripts.gd
run tests/run_tests.gd
run tests/smoke.gd
rm -f "$LOG"
[ $fail -eq 0 ] && echo "ВСЁ ПРОШЛО" || echo "ЕСТЬ ПРОВАЛЫ"
exit $fail
