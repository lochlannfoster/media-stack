#!/usr/bin/env bash
# The validation pipeline for media-stack. One command, deterministic stages, concise output: each stage's
# full log goes to $LOG_DIR/<stage>.log and only the verdict — plus the failing lines on a failure — reaches
# the terminal. The control panel has its own suite in its own repository.
#
#   tests/run.sh lint       shell + python syntax, ruff, Markdown links
#   tests/run.sh unit       tests/unit: the config loader and the shared settings writer
#   tests/run.sh compose    docker compose config + the invariants in tests/check_compose.py
#   tests/run.sh all        lint + unit + compose
#
# Exit codes: 0 pass, 1 fail, 2 usage.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$R/tests"
STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/media-stack-tests"
LOG_DIR="$STATE_BASE/logs"; mkdir -p "$LOG_DIR"
export PYTHONWARNINGS=ignore::ResourceWarning PYTHONDONTWRITEBYTECODE=1
cd /tmp || exit 2   # never run python from the repo root

failed=()
t_start() { _t0=$(date +%s); }
t_end() { echo $(( $(date +%s) - _t0 )); }

run() {
  local stage="$1"; shift; local log="$LOG_DIR/$stage.log"; t_start
  "$@" > "$log" 2>&1; local rc=$?
  if [ $rc -eq 0 ]; then printf '  %-8s PASS  (%ss)\n' "$stage" "$(t_end)"; return 0; fi
  printf '  %-8s FAIL  rc=%s (%ss)  log: %s\n' "$stage" "$rc" "$(t_end)" "$log"
  failed+=("$stage")
  grep -vE '^\s*$' "$log" | tail -${TAIL:-25} | cut -c1-220 | sed 's/^/           /'
  return $rc
}

stage_lint() {
  local rc=0
  echo "== bash -n"; bash -n "$R"/install.sh "$R"/uninstall.sh "$R"/lib/*.sh "$R"/scripts/*.sh "$R"/scripts/*.tmpl "$T"/run.sh || rc=1
  if command -v shellcheck >/dev/null; then echo "== shellcheck"; shellcheck -S warning "$R"/install.sh "$R"/uninstall.sh "$R"/lib/*.sh "$R"/scripts/*.sh || rc=1
  else echo "== shellcheck: not installed — skipped"; fi
  echo "== ast.parse"; python3 -I -c 'import ast,sys
for p in sys.argv[1:]:
    ast.parse(open(p, encoding="utf-8").read(), p)' "$R"/lib/*.py "$R"/scripts/*.py "$T"/*.py "$T"/lib/*.py "$T"/unit/*.py || rc=1
  local ruff=""
  if command -v ruff >/dev/null; then ruff="ruff"; elif command -v uvx >/dev/null; then ruff="uvx ruff"; fi
  if [ -n "$ruff" ]; then echo "== $ruff check"; (cd "$R" && $ruff check --quiet --config ruff.toml lib scripts tests) || rc=1
  else echo "== ruff: not installed — skipped"; fi
  echo "== markdown links"; for f in "$R"/README.md "$R"/docs/*.md "$R"/docs/services/*.md; do [ -f "$f" ] && { python3 -I "$T/lib/md-links.py" "$f" || rc=1; }; done
  return $rc
}
stage_unit() { (cd "$T" && python3 -I -m unittest discover -s unit -t . -v 2>&1); }
stage_compose() {
  (cd "$R" && docker compose --env-file .env.example -f docker-compose.yml --profile '*' config -q) && python3 -I "$T/check_compose.py"
}

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in
  lint|unit|compose) stages=("$cmd") ;;
  all)               stages=(lint unit compose) ;;
  *) usage ;;
esac
echo "validation: ${stages[*]}   (logs: $LOG_DIR)"
for s in "${stages[@]}"; do run "$s" "stage_$s"; done
if [ ${#failed[@]} -eq 0 ]; then echo "RESULT: PASS (${stages[*]})"; exit 0; fi
echo "RESULT: FAIL — ${failed[*]}"; exit 1
