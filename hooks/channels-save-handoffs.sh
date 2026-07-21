#!/usr/bin/env bash
# Fires on PreCompact (context about to be destroyed) and SessionEnd (session closing).
#
# Both are moments where an agent's working memory disappears. A HANDOFF.md that was
# edited but never committed is invisible to `ch resume` in the next session — the write
# happened, but the bus never saw it. So: commit every dirty handoff, whoever wrote it.
#
# This hook CANNOT know which agent the session is, and does not try to. It commits what
# is dirty, nothing else. It never authors handoff CONTENT — only the model can do that,
# which is why the skill insists on writing as you go rather than at the end.
set -uo pipefail

BUS="$HOME/channels"
# Resolve our own directory BEFORE the cd below — $0 may be relative, and once we are inside
# the bus, dirname "$0" quietly points at the wrong place and the staleness check silently
# never runs. Which would make this hook lie about exactly the thing it exists to catch.
HOOKDIR="$(cd "$(dirname "$0")" && pwd)"
[ -d "$BUS/.git" ] || { echo '{}'; exit 0; }
cd "$BUS" || { echo '{}'; exit 0; }

EVENT="$(cat 2>/dev/null | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([A-Za-z]*\)".*/\1/p' | head -1)"
[ -z "$EVENT" ] && EVENT="hook"

# PreCompact: the WORKING HANDOFF.md still holds the full session note-log; a post-compaction
# rewrite may prune it. Snapshot every handoff to its dated archive BEFORE context is destroyed,
# so the log survives at the file level, not just in git (operator directive 97cc275). Dedup
# against the newest existing archive so repeated compactions don't pile identical copies.
archived=0
if [ "$EVENT" = "PreCompact" ]; then
  for hf in */*/HANDOFF.md; do
    [ -f "$hf" ] && [ -s "$hf" ] || continue
    ad="$(dirname "$hf")/handoffs"
    newest="$(ls -1 "$ad"/HANDOFF-*.md 2>/dev/null | sort | tail -1)"
    [ -n "$newest" ] && cmp -s "$hf" "$newest" && continue      # unchanged since last snapshot
    mkdir -p "$ad"
    sha="$(git log -1 --format=%h -- "$hf" 2>/dev/null || echo nohead)"
    ts="$(date -u +%Y-%m-%dT%H%M%S)"
    cp "$hf" "$ad/HANDOFF-$ts-$sha.md" && git add -- "$ad/HANDOFF-$ts-$sha.md" 2>/dev/null && archived=$((archived+1))
  done
  if [ "$archived" -gt 0 ] && ! git diff --cached --quiet 2>/dev/null; then
    GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-channels-bus}" GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-channels-bus@localhost}" \
    GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-channels-bus}" GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-channels-bus@localhost}" \
      git commit -q -m "handoff: PreCompact archived $archived snapshot(s)" 2>/dev/null || true
  fi
fi

saved=0
dirty="$(git status --porcelain -- '*/HANDOFF.md' 2>/dev/null | awk '{print $2}')"
if [ -n "$dirty" ]; then
  n="$(echo "$dirty" | wc -l | tr -d ' ')"
  git add -- '*/HANDOFF.md' 2>/dev/null
  if ! git diff --cached --quiet -- '*/HANDOFF.md' 2>/dev/null; then
    GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-channels-bus}" \
    GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-channels-bus@localhost}" \
    GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-channels-bus}" \
    GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-channels-bus@localhost}" \
      git commit -q -m "handoff: autosaved by $EVENT hook ($n file(s))" 2>/dev/null && saved="$n"
  fi
fi

# Committing a dirty handoff is the EASY half, and on its own it is dangerously reassuring:
# the case it cannot catch — an agent that published all session and never wrote its handoff
# at all — leaves the file CLEAN, so this hook commits nothing and reports success while the
# next session inherits a confident, out-of-date lie. Run the staleness check AFTER the
# commit (so a handoff just written is not flagged) and refuse to let that be silent.
STALE="$(HOME="$HOME" BUS="$BUS" "$HOOKDIR/channels-staleness.sh" 2>/dev/null)"

python3 - "$EVENT" "$saved" "$STALE" <<'PY' 2>/dev/null || echo '{}'
import json, sys
event, saved, stale = sys.argv[1], sys.argv[2], sys.argv[3].strip()
parts = []
if saved != "0":
    parts.append(f"{event} autosaved {saved} dirty HANDOFF.md")
if stale:
    lines = stale.splitlines()
    parts.append(
        "STALE HANDOFF(S) — these agents published to the bus more recently than they "
        "wrote their own handoff, so their next session will resume from an out-of-date "
        "picture:\n  " + "\n  ".join(lines) +
        "\nA hook cannot write handoff content; only the agent can. If one of these is you, "
        "rewrite your HANDOFF.md and `ch save` NOW."
    )
if not parts:
    print(json.dumps({"suppressOutput": True}))
else:
    print(json.dumps({"systemMessage": "channels: " + "\n\n".join(parts)}))
PY
exit 0
