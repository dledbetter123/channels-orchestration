---
name: channels-join
description: Join the ~/channels agent bus as an ADDITIONAL or REPLACEMENT worker on a role (builder, researcher, writer, auditor, tech-support), briefing LIVE off the session already running that role. Use when the user says any of "join the channels as a builder", "start as another builder / researcher / ...", "help the current builder", "assist the builder as another builder", "replace / take over the builder", "spin up a second worker", "join and get a handoff from the current <role>". The first live instance of a role is the LEADER/manager; extra instances are WORKERS the leader distributes work to. This skill runs `ch join`, then conducts the live briefing conversation with the incumbent.
---

# Joining the channels bus as another worker

You are a fresh Claude Code session being asked to come online on the `~/channels` git bus as an
**additional or replacement worker** for one of the roles, and to **talk to the session already
running that role** to get briefed — not just read its log.

Read `~/.claude/skills/channels/SKILL.md` first if you have not: it is the full bus protocol
(messages = commits, `ch` helper, HANDOFF vs MESSAGE, ask→await→reply). This skill is the join
flow layered on top.

## The model: LEADER + WORKERS

- The **first** live instance of a role is the **LEADER** (identity `builder`). It owns all
  role-addressed work and **intelligently distributes** it across the workers, balancing load.
- **Additional** instances are **WORKERS** (identities `builder#2`, `builder#3`, …). A worker takes
  delegated slices from the leader and **reports back** to the leader.
- Role-addressed mail (`subscribers: [builder]`) lands on the **leader only** — never fanned out.
  The leader delegates to a worker by naming it (`subscribers: [builder#2]`); the worker replies on
  the role channel (`subscribers: [builder]`). Coexisting instances all subscribe to the role
  channel, which `ch join` wires for you.

## Step 0 — figure out role, project, and intent

From the user's instruction determine:
- **role**: builder | researcher | writer | auditor | tech-support.
- **project**: default **hids-research** unless they say otherwise.
- **intent — ASSIST or REPLACE:**
  - "help / assist / another / second / spin up a worker" → **ASSIST** (coexist as a worker).
  - "replace / take over / swap out / the old one is stuck" → **REPLACE** (become the leader).
  - **If it is genuinely ambiguous, ASK the user** (assist or replace?) before proceeding — do not
    guess. This is the one decision you must get right.

## Step 1 — run the join engine

```sh
~/channels/bin/ch join <role> <project>
```

Read its output. One of two cases:

**A) It says you ARE the leader (no live incumbent).** Nothing to brief off. Arm your watch and run
as the role:
```
Monitor(command:"~/channels/bin/ch watch <role> <project>", persistent:true)
~/channels/bin/ch resume <role> <project>
```
You are done joining — you lead this role. If workers join later, you brief and distribute to them
(see "If you are the LEADER" below). Stop here.

**B) It says you join as a WORKER `<role>#N` and prints the leader's handoff + a PLAYBOOK.** The
handoff is a **first read, not a substitute for talking to them.** Continue to Step 2.

> **Automatic:** when you join as a worker, `ch join` drops a join-notice into **tech-support's**
> inbox (delivered on your role channel, which tech-support already subscribes to — no fan-out to
> the leader). So tech-support is notified the moment you come online and watches your handshake to
> completion by default; you do not need to ping it. (Skipped when *you* are a tech-support worker —
> the tech-support leader already gets your brief-request directly.)

**Landscape check (operator directive 2026-07-19 — default for every join, leader or worker):**
your role's incumbent briefs you on the *work*; only **tech-support** holds the *landscape* — who
is live in every role, recent kills/replacements, pending onboarding handshakes. Alongside your
briefing (or immediately, if you joined as leader with nobody to brief off), open a 1:1 landscape
request: `ch new <project> <you> landscape-request "..."` with `asks: tech-support`,
`subscribers: [tech-support]`, then `ch send` + `ch await`. Do not join blind — a peer role may
have been killed or replaced minutes ago and nothing else will tell you. (Skipped when you ARE
tech-support — you hold the picture.) Addressing note: name specific workers by **instance id**
(`builder#2`) in `subscribers:`/`asks:`; the bare role reaches the leader.

## Step 2 — brief LIVE off the incumbent (a real conversation, not a log read)

Open a briefing request as your worker identity and **wait** for the incumbent to answer from their
*current* context:

```sh
f=$(~/channels/bin/ch new <project> <role>#N brief-request \
     "<role>#N joining; requesting a live handoff + my slice")
# edit $f frontmatter:   subscribers: [<role>]    asks: <role>
# body — ask what a static handoff can't tell you:
#   • what are you mid-flight on RIGHT NOW?
#   • what is my slice vs yours? what should I take?
#   • what must I NOT touch (in-flight edits, a pod, a claim mid-verification)?
#   • landmines / dead-ends you've already hit?
~/channels/bin/ch send <project> <role>#N brief-request "<role>#N joining — requesting live briefing"
```

Then block cheaply on the reply (one wake, no token spin) — run via Bash `run_in_background`:
```sh
~/channels/bin/ch await <sha-of-your-brief-request>
```

When it answers, **read the MESSAGE**, and **iterate**: ask follow-ups (`re:` their sha,
`asks: <role>`, `subscribers: [<role>]`) until you genuinely have your slice and the landmines.
This is a back-and-forth — keep going until you can say "briefed, taking X." Do not start real work
before you are briefed; a worker guessing its slice collides with the leader.

## Step 3 — take your disposition

**ASSIST (stay a worker):**
```
Monitor(command:"~/channels/bin/ch watch <role>#N <project>", persistent:true)
```
Scaffold your own handoff (`ch handoff <project> <role>#N`), work your slice, and **report results
to the leader** (`subscribers: [<role>]`). Check who else is live with `ch instances <role>`.

**REPLACE (become the leader):** once briefed, ask the leader to stand down:
- The leader runs `~/channels/bin/ch standdown <role> <project>` (saves its handoff — that becomes
  your inherited context — and frees the watch slot), then TaskStops its watch and ends.
- Then you **promote**: `~/channels/bin/ch resume <role> <project>` (reads the leader's final
  handoff) and arm the leader watch:
  `Monitor(command:"~/channels/bin/ch watch <role> <project>", persistent:true)`.
  You are now the leader.

## If you are the LEADER and a worker joins you

You will receive a `brief-request` as an **ASKS-YOU**. Answer it **live from your current context**
(not by pointing at your handoff): say what is in flight, hand the worker a concrete **slice** that
does not overlap yours, and name what they must not touch. Then **distribute and balance**: track
which worker has which slice (in your handoff/ledger), delegate by naming them
(`subscribers: [<role>#2]`), and keep role-addressed work flowing to whichever worker is free.
`ch instances <role>` shows your live workers. When a worker reports done, give it the next slice.

## Quick reference

| Command | What |
|---|---|
| `ch join <role> <project>` | onboard this session; leader if none live, else next worker + playbook |
| `ch instances <role>` | list live instances (leader first) |
| `ch standdown <instance> <project>` | graceful exit: save handoff, free the watch slot |

Everything else is the normal bus (`ch new/send/await/ack/save`, `ch watch`, HANDOFF discipline) —
see the `channels` skill.
