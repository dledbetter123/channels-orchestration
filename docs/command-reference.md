# `ch` command reference

The bus CLI is a single shell script (`bin/ch`, about 2000 lines) living inside the bus
repo. Run it from anywhere; it resolves its own root. This is the full surface as of
2026-07-21.

## Session start / end (talking to your own next session)

| Command | What |
|---|---|
| `ch resume <agent> <project>` | FIRST thing every session: handoff + unread mail + open promises. Refuses when another live session provably holds the role (see [multi-instance.md](multi-instance.md)); `CH_RESUME_FORCE=1` overrides for operator-directed takeovers |
| `ch handoff <project> <channel>` | path to my `HANDOFF.md` (scaffolds if absent) |
| `ch save <project> <channel> [note]` | LAST thing: commit my handoff plus every changed file in my lane dir; archives the outgoing handoff version first |

## Mail

| Command | What |
|---|---|
| `ch new <project> <channel> <slug> <expect>` | scaffold a `MESSAGE.md`; the one-line expectation is REQUIRED and committed before composition |
| `ch intend <project> <agent> <one-line>` | write-ahead: what I am ABOUT to write |
| `ch note <project> <agent> <one-line>` | append to my running log (do this often) |
| `ch send <project> <channel> <slug> <subject>` | commit the message; auto-tags asks/re/promises/resolves; refuses empty subscribers and replies that don't address the asker |
| `ch inbox <agent> [project]` | my mailbox: unread / read / waiting-on-me |
| `ch poll <agent> [project]` | unacked mail (surfacing marks it read) |
| `ch ack <agent> <sha>...` | read receipt, AFTER acting; per message, never bulk |
| `ch acks <sha>` | who has actually received a message |
| `ch read <sha>` | show a message |
| `ch open [project]` | asks awaiting a reply + undelivered promises |
| `ch promises [project]` | undelivered promises only |
| `ch catchup [agent/project]` | read-only history from before I subscribed; not my inbox |

## Subscriptions

| Command | What |
|---|---|
| `ch subscribe <agent> <channel>` | start receiving that channel (delivery begins NOW, no backfill) |
| `ch unsubscribe <agent> <channel>` | stop |
| `ch subs [agent]` | who listens to what |

## Waking

| Command | What |
|---|---|
| `ch watch <agent> [project]` | stream new messages addressed to me; run under a persistent background monitor. Also the role's liveness token: the watch slot records pid + session id |
| `ch await <sha>` | block until my message is answered; run in a background shell, one wake |

## Flow, board, and pods

| Command | What |
|---|---|
| `ch board [project]` | per-lane view: asks-waiting/oldest, unacked, pods, joining state, quiet time; flags BOTTLENECK / DROWNING / ABANDONED POD / OVER-ETA / STALLED joins; cached spend line |
| `ch pods` | who has a pod up right now (monitor id shown; BARE if none) |
| `ch pod-up <agent> <podId> [--monitor <taskid>] [--eta <hours>] [note]` | register a running pod |
| `ch pod-down <agent> <podId>` | deregister the instant it stops |
| `ch pod-request <project> <lane> <slug>` | scaffold the full preflight bundle as an ask to tech-support |
| `ch spend` | per-pod spend + aggregate burn from the billing API; flags unregistered and over-budget pods; emails the operator on a burn-ceiling breach |
| `ch notify [--key k] [--throttle min] <subj> [body]` | email the operator directly (throttled per key); works with no session watching |
| `ch stuck [--reap]` | find orphaned watch loops and pods registered-but-not-running; `--reap` kills the orphaned loops |

## Multi-instance

| Command | What |
|---|---|
| `ch join <role> <project>` | onboard this session: leader if none live, else next worker plus a live-briefing playbook; drops a JOINING marker; auto-notifies tech-support |
| `ch instances <role>` | list live instances, leader first, including mid-handshake joiners |
| `ch standdown <instance> <project>` | graceful exit: save handoff, free the watch slot and session id |

## Protocol versioning

| Command | What |
|---|---|
| `ch skill-bump [--minor] "<changelog>"` | tech-support only; MAJOR re-stales every lane and fires the mandatory reload event, `--minor` records without re-staling |
| `ch skill-ack <agent>` | a lane confirms "I reloaded"; clears its stale flag without a full resume |

## Frontmatter that does something

```
subscribers: [a, b]   # who must act. Empty is refused; 3+ warns. Address narrowly.
asks: <channel>       # I need a reply; shows in their poll as ASKS-YOU
re: <sha>             # this IS the reply (must address the asker back, or send refuses)
promises: <text>      # I owe a future result
resolves: <sha>       # here it is
refs: [<sha>, ...]    # builds on (does NOT close asks)
status: open | resolved | withdrawn
```

## Tunables (environment variables)

| Variable | Default | Governs |
|---|---|---|
| `CHANNELS_POD_STALE_MIN` | 90 | minutes of lane silence before ABANDONED POD |
| `CHANNELS_SPEND_CAP` | 25 | per-pod dollar cap before `ch spend` flags it |
| `CHANNELS_BURN_CAP` | 2 | aggregate $/hr burn ceiling alarm |
| `CHANNELS_JOIN_STALL_MIN` | 45 | minutes before a mid-handshake join shows STALLED |
| `CH_RESUME_FORCE` | unset | set to 1 for a deliberate cross-session role takeover |
