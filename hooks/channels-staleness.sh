#!/usr/bin/env bash
# Shared: report agents whose HANDOFF.md is STALE — i.e. they have published messages to
# the bus MORE RECENTLY than they last updated their own handoff.
#
# Why this exists: the save-handoffs hook commits a *dirty* HANDOFF.md, which makes the
# failure it cannot catch look identical to success. If an agent published four verdicts
# and never touched its handoff, the file is CLEAN, the hook commits nothing, and the next
# session resumes from a handoff that confidently describes a world two hours out of date.
# A stale handoff does not fail loudly. It LIES quietly, which is worse.
#
# A hook cannot author handoff content — only the model can. So the most a hook can do is
# refuse to let the staleness be silent. That is all this does.
#
# Prints one line per stale agent to stdout. Prints nothing if all handoffs are current.
# Never fails the caller.
set -uo pipefail

BUS="${BUS:-${CHANNELS_HOME:-$HOME/channels}}"
[ -d "$BUS/.git" ] || exit 0
cd "$BUS" || exit 0

for d in */*/; do
  d="${d%/}"
  proj="${d%%/*}"
  agent="${d##*/}"
  case "$agent" in
    auditor|researcher|writer|builder|tech-support) ;;
    *) continue ;;
  esac

  # newest commit in which this agent actually WROTE its handoff. Only commits whose subject
  # starts with "handoff" count: `ch send`/`ch note`/`ch intend` also touch HANDOFF.md (the
  # write-ahead log), committing as intend(...)/note(...). Counting those would mean the
  # handoff timestamp advances every time an agent SENDS — so a handoff could never be stale
  # again and this check would go quietly dead. Ask whether the agent wrote its handoff, not
  # whether the file moved.
  h_ts="$(git log -1 --format=%ct --grep='^handoff' -- "$d/HANDOFF.md" 2>/dev/null)"
  # newest commit that PUBLISHED A MESSAGE. Match MESSAGE.md explicitly, not the directory:
  # the bus-init commit scaffolds every <project>/<agent>/ dir at once, so "a commit touched
  # this dir" is true for empty lanes that have never said a word. Ask for the artifact, not
  # for something correlated with it.
  m_ts="$(git log -1 --format=%ct -- "$d/*/MESSAGE.md" 2>/dev/null)"

  [ -z "$m_ts" ] && continue                  # never published a message: nothing to be stale about

  # Only warn about LIVE lanes. A dormant project's missing handoff is not a risk, it is
  # history — and a warning that fires on history is one people learn to skim, which costs
  # more than it saves. Default: silent on anything with no traffic in 14 days.
  now="$(date +%s)"
  dormant_after="${CHANNELS_DORMANT_DAYS:-14}"
  [ $(( (now - m_ts) / 86400 )) -ge "$dormant_after" ] && continue

  if [ -z "$h_ts" ]; then
    if [ -f "$d/HANDOFF.md" ]; then
      # The file exists, but every commit touching it came from the write-ahead log
      # (intend/note). Auto-notes are breadcrumbs, not a handoff — the agent has never
      # actually written down where it is.
      printf '%s/%s: has published messages but has NEVER written its HANDOFF.md (only auto-notes)\n' "$proj" "$agent"
    else
      printf '%s/%s: has published messages but has NO HANDOFF.md at all\n' "$proj" "$agent"
    fi
    continue
  fi

  # ── the other direction ─────────────────────────────────────────────────────
  # "Is the handoff behind the outbox?" is only half the question. The reverse also loses
  # work, and more quietly: an agent whose handoff is FRESH but whose OUTBOX is stale has
  # been thinking in private. A corrected number sits in its running log, right and current,
  # while the other agents keep using the wrong one — and this check stays green, because it
  # was only ever asking whether the handoff had kept up. Freshness of your own memory says
  # nothing about whether the bus knows.
  #
  # Firing on any handoff-newer-than-outbox would fire on every normal session end, and a
  # warning that fires constantly is one people learn to skim. So require that real work has
  # piled up unpublished: several handoff writes AND a meaningful gap since the last message.
  if [ "$h_ts" -gt "$m_ts" ]; then
    writes="$(git log --oneline --since="@$m_ts" -- "$d/HANDOFF.md" 2>/dev/null | wc -l | tr -d ' ')"
    gap_min=$(( (h_ts - m_ts) / 60 ))
    min_writes="${CHANNELS_UNPUBLISHED_WRITES:-4}"
    min_gap="${CHANNELS_UNPUBLISHED_GAP_MIN:-90}"
    if [ "$writes" -ge "$min_writes" ] && [ "$gap_min" -ge "$min_gap" ]; then
      if [ "$gap_min" -ge 60 ]; then gage="$(( gap_min / 60 ))h$(( gap_min % 60 ))m"; else gage="${gap_min}m"; fi
      printf '%s/%s: UNPUBLISHED — %s of handoff writes (%s) since your last message. If any of that is a finding the others depend on, it is not on the bus and they are working without it.\n' \
        "$proj" "$agent" "$gage" "$writes"
    fi
    continue                                   # handoff is ahead of the outbox: not stale
  fi

  [ "$m_ts" -le "$h_ts" ] && continue          # handoff is at or ahead of the outbox: current

  # how many messages were published since the handoff was last written, and how stale
  n="$(git log --oneline --since="@$h_ts" -- "$d/*/MESSAGE.md" 2>/dev/null | wc -l | tr -d ' ')"
  mins=$(( (m_ts - h_ts) / 60 ))
  if [ "$mins" -ge 60 ]; then
    age="$(( mins / 60 ))h$(( mins % 60 ))m"
  else
    age="${mins}m"
  fi

  printf '%s/%s: HANDOFF.md is STALE — %s message(s) published since it was last written (newest is %s ahead)\n' \
    "$proj" "$agent" "$n" "$age"
done

# ── ledger drift ──────────────────────────────────────────────────────────────
# A HANDOFF is an agent's private memory; a LEDGER is the shared reconciliation of what is
# still true (auditor/CLAIMS_LEDGER.md: safe-to-print vs dead. writer/CLAIM_INVENTORY.md:
# which sentences are licensed). A stale handoff misleads one agent. A stale ledger puts a
# DEAD NUMBER in the SAFE table, and the whole point of that table is to be trusted without
# re-derivation — so nobody re-checks it. That is the most expensive silent failure here.
#
# It is not hypothetical. Within minutes of coming online the writer found a RETIRED fusion
# number sitting in SAFE, because the retraction landed after the ledger was last written and
# nothing connected the two. A fresh pair of eyes caught it. That is not a control.
#
# So: if a message whose subject RETRACTS / REFUTES / WITHDRAWS / RETIRES / CORRECTS something
# landed AFTER the ledger was last written, the ledger may now be lying. Name the shas and let
# the owner rule. This flags a QUESTION, not a verdict — a hook cannot know whether a
# retraction touches a row, only that nobody has looked since it landed.
for ledger in */*/CLAIMS_LEDGER.md */*/CLAIM_INVENTORY.md; do
  [ -f "$ledger" ] || continue
  d="$(dirname "$ledger")"
  proj="${d%%/*}"; owner="${d##*/}"; base="$(basename "$ledger")"

  l_ts="$(git log -1 --format=%ct -- "$ledger" 2>/dev/null)"
  [ -z "$l_ts" ] && continue                   # uncommitted: the save hook will get it

  # Verdict-changing traffic since the ledger was last touched, from ANY lane but the owner's
  # own edits. Match the commit subject: that is where an agent announces a retraction.
  # Exclude tech-support: the bus lane publishes delivery faults, never research verdicts, and
  # it says the word "retracted" constantly while announcing other people's retractions. A
  # warning that fires on its own maintenance chatter is one people learn to skim.
  drift="$(git log --since="@$l_ts" --format='%h %s' \
             -- "$proj/*/MESSAGE.md" ":(exclude)$proj/tech-support/*" 2>/dev/null \
             | grep -iE 'retract|refut|withdraw|retire|corrected|RULE ZERO' || true)"
  [ -z "$drift" ] && continue

  n_drift="$(echo "$drift" | wc -l | tr -d ' ')"
  printf '%s/%s: %s may be STALE — %s verdict-changing message(s) landed after it was last written:\n' \
    "$proj" "$owner" "$base" "$n_drift"
  echo "$drift" | head -4 | cut -c1-140 | sed 's/^/    /'
  [ "$n_drift" -gt 4 ] && printf '    ... and %s more\n' "$(( n_drift - 4 ))"
  printf '    → %s owns it. A retraction that landed after the ledger was written is how a DEAD number ends up in the SAFE table.\n' "$owner"
done

exit 0
