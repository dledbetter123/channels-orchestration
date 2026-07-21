# Architecture: a git repo as a message bus

## Layout

The bus is a single git repository (`~/channels` on the host machine). Everything in it is
either mail, memory, or delivery state:

```
<project>/<channel>/HANDOFF.md                       # agent -> its OWN next session (mutable)
<project>/<channel>/<YYYY-MM-DD>-<slug>/MESSAGE.md   # agent -> the OTHER agents (append-only)
<project>/<channel>/<YYYY-MM-DD>-<slug>/*            # attachments (specs, tables, figures)
<project>/<channel>/handoffs/                        # dated archive of every handoff version
<project>/ops/                                       # operator broadcast lane
.subs/                                               # subscription state (who listens to what)
.mail/<agent>/inbox                                  # per-agent mailbox (delivery is a write)
.watch/<agent>.pid|.sid|.joining                     # live-session watch slots
bin/ch                                               # the CLI that wraps all of it
```

`<project>` is a research effort (there can be several on one bus). `<channel>` is a role.
An agent publishes only to its own channel and never reads its own channel for
instructions: your channel is your outbox.

## Two artifacts, opposite lifecycles

| | `HANDOFF.md` | `MESSAGE.md` |
|---|---|---|
| Audience | your own next session | the other agents |
| Lifecycle | mutable, rewritten constantly | append-only, never edited once sent |
| Count | one per agent per project | one per result, claim, verdict, or ask |
| Staleness | a stale handoff actively lies | never; it is a dated record |

This split is the core design decision. Mail must be immutable because the audit trail is
the point. Memory must be mutable because sessions get renewed constantly and the handoff
is the only thing carrying an agent's context across that boundary. Git versions the
handoff anyway, so the dated history comes free, and the CLI archives every outgoing
version to `handoffs/` before a rewrite, so pruning the working file never loses history.

## Delivery: subscription is an event, delivery is a write

- **A channel reaches you because you subscribed to it**, and that subscription is itself
  a commit you can point at. Nothing else grants delivery: not being named in a message,
  not being a known agent.
- When someone sends a message naming you, it lands in `.mail/<you>/inbox` **in the same
  commit**. It queues whether or not you were awake. Mailboxes are never backfilled: mail
  sent before you subscribed was never yours (a separate read-only `catchup` command reads
  the archive).
- Three mailbox states, forward-only:

| State | Means | Set by |
|---|---|---|
| UNREAD | delivered, never surfaced to you | the sender's `ch send` |
| read | you have SEEN it (not acted on it) | `ch poll` / `ch inbox` surfacing it |
| acked | you ACTED on it; it leaves your mailbox | you, explicitly, per message |

Seeing is not handling, which is why read and acked differ. A surfaced-but-never-acked
message stays in the inbox forever, deliberately: the bus would rather nag than lose work.
(An earlier bulk "mark all read" cursor silently dropped unhandled work and was removed.)

- **Addressing someone who is not subscribed does not reach them**, and the send command
  says so loudly (`UNDELIVERABLE`). This is enforced because a blocking ask once sat
  undelivered for a day, aimed at an agent that could not receive it.

## Waking: no daemon, three regimes

An agent only exists while its session is running, so nothing holds a socket open. Being
"subscribed" means something wakes you:

| Situation | Mechanism |
|---|---|
| Mid-session, want to hear channel traffic | a persistent shell watcher (`ch watch <you>`) armed as a background monitor; a new message addressed to you becomes a notification, and the model idles for free between them |
| Mid-session, blocked on one specific ask | `ch await <sha>`: a background process that exits exactly once, when the reply lands |
| Across session renewal (you don't exist) | nothing can wake you; the handoff plus the queued mailbox are the safety net, replayed by `ch resume` |

The rule behind all three: **never poll in a model loop.** Polling burns tokens per
iteration and still misses things between turns. A shell loop watches; the model sleeps.

The watch slot doubles as the liveness token: `.watch/<agent>.pid` records the live
watcher, and `.watch/<agent>.sid` records which session armed it (used by the takeover
guard, see [multi-instance.md](multi-instance.md)).

## Hooks: the safety net for context loss

Agent sessions have finite context windows and can be summarized ("compacted") mid-task.
Three lifecycle hooks back up the discipline:

| Hook | Fires | Does |
|---|---|---|
| save-handoffs | before compaction, at session end | commits any dirty `HANDOFF.md` that was written but never committed |
| session-context | at session start | re-briefs a fresh or compacted agent: reload the protocol skill, `ch resume`, re-arm the watch, print the board |
| staleness | called by both | publicly flags any agent whose published messages are newer than its own handoff |

The autosave hook is deliberately described as "dangerously reassuring": it can commit a
forgotten write, but it cannot author a handoff. The far more common failure is publishing
all session and never touching the handoff, which leaves a clean (and confidently
out-of-date) file. That is what the staleness flag exists to catch, by name.

## Append-only rules

1. Never amend, rebase, force-push, or delete a published message. Retract by publishing a
   new message with `status: withdrawn` and the reason.
2. Stage only your own paths. All sessions share one worktree; `git add -A` is forbidden,
   and the CLI stages for you.
3. Cite by SHA. Prose claims about other agents' findings must carry the message id.
4. Numbers carry their eval protocol, or a path to the artifact that has it.
5. Secrets never enter the repo. Git is permanent; tokens are read from the OS keychain at
   runtime by the tools that need them and never committed or pasted into messages.
