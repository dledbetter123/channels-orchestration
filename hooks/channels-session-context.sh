#!/usr/bin/env bash
# SessionStart — injects context into a fresh (or just-compacted) session.
#
# After a compaction the model's working memory is gone. This is the one reliable moment
# to tell it: you are on the channels bus, go re-read your own handoff and re-arm your
# watch. stdout must be JSON with hookSpecificOutput.additionalContext.
set -uo pipefail

BUS="$HOME/channels"
[ -x "$BUS/bin/ch" ] || { echo '{}'; exit 0; }

SOURCE="$(cat 2>/dev/null | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' | head -1)"
[ -z "$SOURCE" ] && SOURCE="startup"

OPEN="$(cd "$BUS" && ./bin/ch open 2>/dev/null | head -12)"
STALE="$(BUS="$BUS" "$(cd "$(dirname "$0")" && pwd)/channels-staleness.sh" 2>/dev/null)"
# The bottleneck view: which lane is ASKED but SILENT, or drowning in unread. A stalled lane
# is the whole research idling behind one agent, and the writer just did exactly that unseen.
BOARD="$(cd "$BUS" && ./bin/ch board 2>/dev/null | grep -E 'BOTTLENECK|DROWNING|ABANDONED POD' || true)"
if [ -n "$BOARD" ]; then
  BOARD_BLOCK="
⛔ BOARD ALERT — a lane is a choke point, drowning, or has a pod running unwatched:

$(echo "$BOARD" | sed 's/^/  /')

If that lane is YOU: 🔥 ABANDONED POD is most urgent — a pod is billing and unwatched; go check it
or 'ch pod-down' it NOW. Otherwise clear the asks aimed at you before anything else.
If it is NOT you but you are waiting on it: it may be offline — tell the operator, do not idle."
else
  BOARD_BLOCK=""
fi

# A stale handoff is worse than a missing one: it reads as authoritative. If the agent
# resuming here is one of the stale ones, say so BEFORE it trusts what it is about to read.
if [ -n "$STALE" ]; then
  STALE_BLOCK="
⚠️  STALE HANDOFF WARNING — these agents published to the bus AFTER they last wrote their
own handoff, so those handoffs are missing their most recent work:

$(echo "$STALE" | sed 's/^/  /')

If one of these is YOU: your HANDOFF.md is not a trustworthy summary of where you are.
Reconstruct from your recent messages (\`git log --oneline -- <project>/<you>\`, then read
their MESSAGE.md), rewrite the handoff, and \`ch save\` before doing anything else."
else
  STALE_BLOCK=""
fi

if [ "$SOURCE" = "compact" ]; then
  LEAD="Your context was just COMPACTED — your working memory is gone, and anything you were holding but had not written down is lost."
else
  LEAD="New session on the channels bus."
fi

CTX="$LEAD

If you are one of the four macro-agents (auditor / researcher / writer / builder) working
out of ~/channels, do these BEFORE anything else:

  0. RELOAD THE SKILL: invoke the 'channels' skill now. The protocol was upgraded and any
     version of it you are carrying in context is STALE — it predates read receipts (ch ack),
     ask/reply (asks:/re:), and watches. Do not work from memory of the old protocol.
  1. ~/channels/bin/ch resume <you> <project>     # your HANDOFF.md + mail addressed to you
  2. Re-arm your watch (you are NOT subscribed without it):
     Monitor({command: \"~/channels/bin/ch watch <you> <project>\", persistent: true})
  3. Re-read your own HANDOFF.md at <project>/<you>/HANDOFF.md — it is the only thing that
     survived. Trust it over your reconstructed summary.

Rules that outlive a compaction: ack each message AFTER you act on it (ch ack <you> <sha>),
address messages narrowly, and rewrite your HANDOFF.md whenever the next-action changes —
not at the end of the session, because there may not be one you control.

Outstanding on the bus right now:
${OPEN:-  (nothing outstanding)}
${STALE_BLOCK}
${BOARD_BLOCK}

If you are NOT a channels agent, ignore all of the above."

python3 - "$CTX" <<'PY' 2>/dev/null || echo '{}'
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": sys.argv[1],
    }
}))
PY
exit 0
