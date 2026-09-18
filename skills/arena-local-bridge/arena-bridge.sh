#!/usr/bin/env bash
# arena-bridge.sh - one-shot entry for the arena-local-bridge skill.
#
# Usage:
#   bash skills/arena-local-bridge/arena-bridge.sh status     # bridges health
#   bash skills/arena-local-bridge/arena-bridge.sh prompt FILE # send FILE as the next arena task (user must have activated the arena tab <30min ago)
#   bash skills/arena-local-bridge/arena-bridge.sh monitor    # watch the running arena agent to completion
#
# What it does: writes the task hook (borrow -> /agent -> continue-click ->
# clipboard -> send -> monitor), pushes it via the git-sync loop, waits for
# the local verdict, and pulls the evidence back.

set -u -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
cd "$REPO"

CMD="${1:-status}"
case "$CMD" in
  status)
    echo "== git-sync branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "== local bridge:"
    grep -hE 'accept 2a|auth:|watcher' results/status/check_r*_*.txt 2>/dev/null | tail -3
    echo "== artifacts: $(ls deliverable 2>/dev/null | wc -l) files in deliverable/"
    ;;
  prompt)
    FILE="${2:?usage: arena-bridge.sh prompt <file>}"
    [ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 1; }
    cp "$FILE" results/status/arena_prompt2.txt
    cp skills/arena-local-bridge/templates/agent_task_bridge.ps1 code/agent_task.ps1
    bash skills/git-sync/scripts/agent-sync.sh "feat(bridge): dispatch task from $FILE"
    bash skills/git-sync/scripts/agent-wait.sh --request "bridge: dispatch and monitor" --timeout 1800 --interval 15
    ;;
  monitor)
    bash skills/git-sync/scripts/agent-wait.sh --request "bridge: monitor the running arena agent" --timeout 1800 --interval 15
    ;;
  *)
    sed -n '2,12p' "$0"; exit 1 ;;
esac
