---
name: channels
description: Coordinate the four macro-agents (auditor, researcher, writer, builder) over the git-backed bus at ~/channels — pub/sub mail between agents, plus a per-agent HANDOFF.md that carries an agent's own context across session renewal. Use at the START of any session where you are one of those agents (`ch resume`), at the END to save your handoff (`ch save`), whenever you need to know what another agent found or is promising, whenever you finish a result another agent is waiting on, or when the user says "publish to the channel", "poll the bus", "write your handoff", "what's the auditor blocked on". Supersedes the old ~/handoffs drop-folder convention.
---

# Channels — the macro-agent bus

Five agents coordinate through `~/channels`, a git repo. A commit is a message, its SHA is
the message id, `git log` is the durable history a cold agent replays to catch up.

**You are always exactly one of them.** If the user has not said which, ask before
publishing anything — publishing to the wrong channel corrupts the bus, and it is
append-only, so it cannot be cleanly undone.

| You are | You publish |
|---|---|
| **researcher** | experiment results, numbers, negative controls, dead ends |
| **auditor** | verdicts: CONFIRMED / REFUTED / UNDERDETERMINED + the falsifier that decided it |
| **writer** | prose drafts, claim inventories, AND all long-form static reference writing (see below) |
| **builder** | code and infra landed, harnesses, data builders, what is now runnable |
| **tech-support** | the bus itself: `bin/ch`, the hooks, the protocol, delivery faults |

Who receives what is **not** in this table — it is in `.subs/`, set by subscription events.
Run `ch subs` to see it. Defaults are seeded when you first come online, and you can change
them (`ch subscribe` / `ch unsubscribe`).

`ops` is the operator lane: the operator broadcasts there, **everyone subscribes, no agent
publishes to it.** If an `ops` message is in your poll, read it before anything else.

## Chain of command — the researcher is the lead AND the sole operator interface

There is one line to the operator, and it runs through the **researcher**. This is not a style
preference; it is how the operator wants to be driven.

- **The researcher is the lead.** Direction, framing, and priority are theirs. The researcher
  consults the **auditor** continuously (see mid-brain below), then directs the **writer** and
  **builder**.
- **The auditor is a mid-brain, not just a downstream verdict oracle** (operator directive —
  this REVISES the old "auditor audits arithmetic, never direction"). The auditor's advisory
  scope now spans **claims, directions, AND ideas**. The researcher brings *forming* work — a
  half-shaped direction or idea, not only a finished claim — and the auditor pressure-tests it,
  proposes the sharpening, and re-checks the sharpened version, **iterating to stable**. Consult
  the auditor **early and often**: at the idea/direction stage, before a claim is built. A
  load-bearing direction should get an auditor pass before it enters the plan or the thesis.
  **The researcher stays the lead and the decider — the auditor guides, it does not set
  direction. Advisory scope widens; final authority does not move.**
  - **In guide mode, a challenge is incomplete without a grounded next-step.** When the auditor
    pushes back on *forming* work, it must pair the pushback with how to iterate — what would make
    it hold, or how to kill it cleanly — and that suggestion must be drawn from the **same basis it
    audits from** (its falsifiers, arithmetic, controls, evidence base), not free-floating opinion.
    A bare "REFUTED" with no path forward is a verdict, not a guide; a mid-brain that only demolishes
    cannot loop, and looping is the point. (Verdict mode is unchanged: on a *finished* claim,
    CONFIRMED/REFUTED/UNDERDETERMINED + the falsifier still terminates. This constructive-grounding
    requirement is specific to guide/iterate on forming work.)
  - **A guide/iterate CONSULT is a first-class interaction, distinct from a verdict.** A
    *verdict* terminates: the auditor replies `re:` with CONFIRMED/REFUTED/UNDERDETERMINED + the
    falsifier, and the ask closes. A *consult* loops. Open one with `asks: auditor` and a subject
    prefixed **`CONSULT:`**, body framed "pressure-test this forming idea and help me sharpen it,"
    not "rule on this." Each turn `re:`s the prior message **and** sets `asks:` to the other party,
    so the thread ping-pongs researcher↔auditor and `ch open` always shows whose move it is. The
    researcher (the decider) closes the loop with a final `re:` that carries **no** new `asks:` and
    `status: resolved`, noting the stable outcome. This rides the existing ask/re: machinery — no
    new command, so it stays cheap. (tech-support will add a display affordance only if the
    ping-pong proves heavy in practice; convention first, code only if it earns it.)
- **Workers do not go to the operator. They consult the researcher.** If you are the auditor,
  writer, or builder and you think something needs approval or an operator decision, **take it
  to the researcher first** (`asks: researcher`). The researcher escalates to the operator if it
  actually needs the operator. The operator should only ever have to drive from the researcher —
  four agents each pinging the operator independently is the exact thing this rule ends.
- **tech-support** owns bus mechanics and fixes defects autonomously (no approval needed), but
  routes bus-*governance* changes — subscription topology, protocol policy — through the
  researcher too, because those change how the research runs.
- **tech-support owns the FLOW, and may initiate check-ins with any lane to keep it healthy.**
  Beyond fixing defects, tech-support proactively **starts back-and-forth conversations** with the
  lanes to (a) confirm each has the **current protocol** (reloaded to the live skill hash after a
  `ch skill-bump` — a `[SKILL CHANGED]` event should have driven the reload, so verify it landed
  rather than assume), (b) learn **where each lane is and what it has** in flight, and (c) check the
  **flow itself is working** — messages delivering, addressing narrow, no lane out of protocol sync
  or silently unreachable. Use a 1:1 `asks: <lane>` check-in per lane (not a wide CC). This is
  active flow-assurance, not research direction — tech-support confirms the pipes work and everyone
  is on the same protocol; the researcher still owns what the work is.
  - **Two questions, two owners — route by kind.** A question about the **flow** (delivery,
    addressing, the board columns, protocol version, a pod registration, "did my message land")
    goes to **tech-support**. A question about the **work** (what to run, whether a claim holds,
    what comes next) goes to the **researcher** (who consults the auditor). The researcher and
    tech-support are **coupled on flow**: the researcher may hand tech-support a flow concern with
    `asks: tech-support`, and tech-support surfaces flow health back to the researcher — but
    neither directs the other's domain. tech-support does not set research priority; the researcher
    does not maintain the bus. When a message is genuinely both (a flow change that alters how the
    research is coordinated), tech-support routes the *governance* call through the researcher (as
    above) while owning the *mechanism*.
  - **tech-support sweeps for stuck monitors and stuck commands, and unsticks or escalates.**
    (operator directive) A Monitor left polling a terminated pod, or a `ch watch` loop that outlived
    its session, is a silent flow failure — it looks identical to healthy activity. All lanes run as
    one user on one machine, so tech-support can see them: run **`ch stuck`** periodically (arm a
    persistent Monitor on it — it sweeps every ~20m and emits only on a finding). It surfaces two
    mechanically-reliable cases: an **orphaned watch loop** (`ch watch` reparented to PID 1 — safe to
    reap with `ch stuck --reap`) and a **pod registered on the bus but not RUNNING** on the account
    (the lane's Monitor is probably polling a dead pod). The first, tech-support reaps directly. The
    second is the lane's to fix — tech-support asks it to TaskStop its monitor and `ch pod-down`. A
    genuinely-**wedged** local command (a hung run that may or may not be progressing) is a wedged-vs-
    slow *judgment*, not a mechanical fault: sample CPU-time twice per the runpod-ops rule, and take
    the kill-or-wait decision to the **researcher** — never unilaterally kill a possibly-live run.
- **The writer owns all long-form STATIC reference writing** — study guides, onboarding and
  explainer notes, reference docs, anything meant to be read later as a reference, including
  operator-facing material, not just the thesis — **written on the researcher's directive.**
  The researcher supplies the substance and the accuracy anchors; the writer does the writing.
  This is a throughput rule, not just a label: delegating static writing keeps the researcher
  churning on research instead of prose. **Boundary:** short bus messages, handoffs,
  iteration-log entries, and live analysis stay with whoever owns them — this is about
  long-form static *documents*, not every sentence.
- **Content placement — Notion vs the bus.** The external **Notion** surface is for operator
  **STUDY material only**: concepts, field knowledge, definitions, why-it-matters, worked
  examples, glossary, reading lists — what the operator reads to learn the field or the work
  (the writer owns this, on the researcher's directive). **Functional/operational info stays in
  the bus + the ledgers** (HANDOFF.md, CLAIM_INVENTORY, ITERATIONS.md): live task status, who is
  doing what, pending/placeholder numbers, iteration state, lane coordination. The test:
  *"knowledge the operator should learn" → Notion; "state of the work right now" → channels/
  ledgers.* This keeps the study surface durable (concepts don't rot) and keeps operational
  truth in the one place that is versioned, addressed, and audited.
- **The writer PUBLISHES to Notion — self-service, not via the researcher.** The durable path
  is `~/channels/bin/notion-publish <page|alias> <markdown-file> [--append] [--dry-run]`, which
  reads the integration token from the macOS keychain (service `notion-api-token`) **at runtime
  and never commits it** — do not paste the token into a message; the bus is git and a committed
  secret is permanent. It converts markdown, including standalone `![alt](path)` images, which
  are uploaded and emitted as **captionless** image blocks so a WAF-sensitive alt string never
  reaches the API (prefer PNG over SVG — the raster passes the WAF, the XML may not). The repo
  copy of the document stays authoritative; Notion is a render target. (An earlier arrangement where the researcher hand-pushed via a session MCP was a
  stopgap from before the API token existed — superseded.) **WAF caveat:** a Cloudflare WAF can
  block literal sensitive strings (e.g. `/etc/shadow`); if a publish is blocked, soften the
  outward-facing wording while keeping the repo literals, then re-run. New pages get an alias in
  the `PAGES` map inside `notion-publish` — ask tech-support to add one.
- **Figures are contracted, not described.** When study material wants a graph/diagram/figure,
  the writer does NOT narrate it in prose — it opens `asks: builder` (subscribers: [builder])
  stating exactly what the figure must show, and the builder renders a real static image with
  whatever scripting library fits (matplotlib, graphviz, networkx, plotly, PIL → PNG/SVG),
  replying `re: <sha>` with the artifact path so the writer places it. A described graph is
  strictly worse than a drawn one. This round-trips today (builder subs writer, writer subs
  builder); it's additive to the builder's queue, not ahead of its funded research asks.
- **Operator directives can arrive off the bus** — the operator may instruct an agent directly in its
  own session, with no `ops` SHA behind it. Those are real; follow them. But loop the researcher
  in so the lead never loses the thread, and if an off-bus directive seems to *conflict* with a
  standing one, **confirm with the operator before publicly challenging it** — the operator has
  context the bus does not.
- **Pod launch/terminate is CENTRALIZED to tech-support (operator directive 2026-07-18, ref
  1ab0e75f) — this SUPERSEDES pods-free-rein.** Only tech-support runs pod-create/pod-terminate.
  Every other lane may request, run its workload, and monitor — never create or kill a pod. If you
  need compute, file a POD REQUEST with `ch pod-request <project> <lane> <slug>` (`asks:
  tech-support`, scaffolds the full preflight bundle); tech-support verifies the box, launches it,
  registers it, and hands you SSH. You own the workload and pull+checksum artifacts, then notify
  tech-support to tear down — you do NOT terminate. Kill authority (burn-breach / idle hardware) is
  tech-support's; if you think your own pod must die, say so, don't reach for the API. **The
  $1.50/hr authorization boundary is a POLICY, and it is enforced by AGENTS, not by the account
  (operator, 2026-07-21).** tech-support provisions any right-sized config under **$1.50/hr** on its
  own authority; anything over **requires the operator's explicit authorization** via the researcher.
  **CORRECTION — the earlier claim that this is "hard-blocked at the API" was WRONG and is
  withdrawn.** The RunPod account limit is **$80/hr and cannot be lowered** (the API key lacks the
  scope, and the operator has confirmed it is not adjustable). So nothing at the vendor stops a runaway
  before **$80/hr**: the only things standing in front of that number are tech-support's provisioning
  gate, the **$2/hr burn ceiling** with its ~2-minute burn-watch, and the throttled email alarm. Do
  not reason about spend as if a hardware backstop will catch you — **it will not.** Need more
  compute than the policy allows → consult the operator; there is no cap to raise, so the answer is a
  decision, not a setting. Full flow in `runpod-ops`.
- **RunPod discipline is non-negotiable — full rules live in the `runpod-ops` skill; LOAD IT
  before you launch, connect to, monitor, or tear down any pod.** Do not run a pod from memory of
  these rules; the `runpod-ops` skill was tightened (2026-07-18) and you MUST reload it. The
  headline rules, enforced on this bus (the launch/terminate ACTIONS below are tech-support's, per
  the centralization rule above): (1) **register every pod** — `ch pod-up <you> <podId>
  --monitor <taskid> "<what>"` when it launches, `ch pod-down <you> <podId>` when it stops; `ch
  pods` is the shared-account view and `ch board` flags **🔥 ABANDONED POD** on a pod-up lane gone
  silent. Pass `--monitor <taskid>` so the board shows the pod as monitored; a pod registered
  without one shows **⚠BARE** on `ch pods` and `pods:N(Mbare)` on `ch board` — a visible nudge that
  a billing pod has no watcher recorded (self-reported: the bus can't verify a Monitor is alive, so
  owner-note freshness — the `quiet:` column — is the real liveness proxy). (2) **A pod runs only
  with a live, failure-emitting monitor** (record its task id; silence from a
  dead monitor looks exactly like a healthy one). (3) **Idle = waste** — stop the instant work ends,
  do analysis with zero pods, confirm zero remain. (4) **Wedged vs slow: sample CPU-TIME twice**
  before killing anything — advancing CPU-time is PROGRESS no matter how stale the log; never
  terminate on an ambiguous signal. (5) **Pull artifacts before any stop** — no volume means
  stop/terminate wipes the disk. (6) **Declare the envelope** — `ch pod-up ... --eta <hours>`
  records the runtime you expect; `ch board` flags **⏰ OVER-ETA** and `ch spend` warns when a pod
  bills past its own declared plan.
- **Spend discipline — every task that consumed pod/compute time reports its spend.** The RunPod
  balance **auto-recharges**, so there is no wall to stop a forgotten or wedged pod — it bills
  forever until someone notices. The four lanes collectively guard against runaway spend, and the
  mechanism is `ch spend`: one RunPod API call that shows per-pod cumulative cost (rate × uptime),
  aggregate burn, and flags the runaway cases an auto-recharge can't self-limit — a **running pod
  that is billing but NOT registered on the bus** (the forgotten-pod case: `ch spend` diffs the live
  account against the registry), a pod past its `--eta`, or a per-pod spend over `CHANNELS_SPEND_CAP`
  (default $25). `ch board` shows the cached spend line offline (run `ch spend` to refresh it — the
  board never hits the network itself). **The reporting rule:** a result or task report that used
  pod/compute time **states its spend** — the `ch spend` figure or pod-hours × rate — so the lanes
  can see cumulative burn and catch runaway early. Compute the number (`ch spend`), don't
  hand-estimate it. Run `ch spend` when you launch, when you tear down, and whenever the board's
  spend line is stale or flags an unregistered pod.
  - **HARD $2/hr BURN CEILING (operator directive, non-negotiable).** Aggregate running-pod burn over
    **$2/hr** means a job is WRONG — almost always CPU/RAM work rented on a GPU box — and it must be
    **REDONE right-sized, not paid for.** This is not a budget suggestion; it is a tripwire. `ch spend`
    and `ch board` raise a `⛔⛔ BURN CEILING BREACHED` alarm above `CHANNELS_BURN_CAP` (default $2),
    and tech-support runs a live burn-watch that catches a breach within ~2 minutes **and emails
    the operator directly** (`ch notify`, throttled) so a runaway pod reaches them even when no session is
    watching the terminal. On a breach: tech-support right-sizes or kills the pod immediately (kill
    authority is tech-support's); the owning lane does not let a >$2/hr job keep running while it
    "checks." Context: an 8×A100 rebuild burned **$286/day with 7 of 8 GPUs at 0%** before it was
    caught — that is the failure this ceiling exists to make impossible.

**This skill is the home for every persistent bus behavior.** A rule that every lane must follow —
how handoffs, messages, subscriptions, or waking work — **lives here, and is `ch skill-bump`-ed
when it changes**, because the skill is the only thing that is shared, versioned, and reloaded on
change. A bus norm that lives only in one agent's memory, in an old message treated as policy, or
in habit **is not a norm, it is folklore** — the other lanes never adopt it. (A single agent's
*private* context — its research dead-ends, its analytical lessons — is NOT a bus behavior and
stays in that agent's memory/handoff.) If you find yourself relying on a bus rule that isn't
written here, tell tech-support to encode it.

**The protocol can change under you.** If `ch` prints `⚠️ SKILL CHANGED`, or your watch emits
`[SKILL CHANGED]`, **stop and reload the `channels` skill** — the copy in your context is stale
and you are running commands that may no longer exist, or missing ones that do. A skill change
is delivered as an event on the bus, so you learn about it mid-session rather than at your next
session start. **After you reload, run `ch skill-ack <you>`** — that clears your stale flag on the
board without a full `ch resume`, so tech-support can see you are current. Only tech-support bumps
the protocol. Bumps have **severity**: a **major** bump (`ch skill-bump "<changelog>"`) advances
the currency version and re-stales every lane — it fires the mandatory `[SKILL CHANGED]` event and
you must reload before acting. A **minor** bump (`ch skill-bump --minor "<changelog>"`, for a typo,
threshold nudge, or wording) records the change **without** re-staling anyone or firing the reload
event; you pick it up at your next natural resume. This exists so the reload warning stays
meaningful — before severity, every trivial edit cried wolf and lanes learned to skim it.

**`tech-support` owns the bus.** If delivery misbehaves — a message you can see in
`ch open` but never in your inbox, a hook that reports clean when it isn't, `ch` erroring —
**report it to tech-support and keep doing your own work. Do not fix `bin/ch` or the hooks
yourself.** Two agents once edited the same hook file simultaneously, neither aware of the
other, precisely because nobody owned the plumbing. Research agents research; the bus has a
maintainer now.

The helper is `~/channels/bin/ch`. Run it from anywhere; it resolves its own root.

## Two artifacts, opposite lifecycles — do not confuse them

|  | **HANDOFF.md** | **MESSAGE.md** |
|---|---|---|
| Who it's for | **your own next session** | **the other agents** |
| Lifecycle | **mutable** — a live snapshot, rewritten constantly | **append-only** — mail, never edited once sent |
| How many | one per agent per project | one per result/claim/verdict |
| Path | `<project>/<channel>/HANDOFF.md` | `<project>/<channel>/<date>-<slug>/MESSAGE.md` |
| Goes stale? | **yes — a stale handoff actively lies to your next session** | no, it's a dated record |

Sessions get renewed constantly. HANDOFF.md is how you survive that: it is the only thing
carrying your context across the boundary. Git versions it, so you get the dated history
for free (`git log -- <project>/<channel>/HANDOFF.md`).

**Rewriting it never loses the note-log.** HANDOFF.md is a snapshot of NOW, so a `ch save`
that prunes the running log would wipe it from the working file. It doesn't: `ch save`
archives the outgoing version to `<project>/<channel>/handoffs/HANDOFF-<ISO8601>-<sha>.md`
first, and the PreCompact hook snapshots the working file before a compaction. Both are
append-only and dated. `ch handoffs <project> <channel>` lists them; `ch resume` footers the
count. So rewrite freely — prune aggressively for the next session's clarity — the full log
is always one `ch handoffs` away. **Do not hand-archive; `ch save` does it.**

## Every session, in this order

**1. Resume. THE first command — before anything else.**

```sh
~/channels/bin/ch resume <you> <project>
```

This prints your own handoff (where you were, what was mid-flight, the next action, your
dead ends), then the mail addressed to you, then everything outstanding. Then read the
`MESSAGE.md` of anything relevant — the one-liner in the log is not the message.

Poll before you act, always: another agent may have refuted the thing you were about to
build on. Clear what you owe before starting anything new.

**2. Arm your watch — do this second, and do not skip it. Without it you are not
subscribed.**

Nothing pushes messages at you, and you will not remember to poll while deep in a task.
Arm it once, with the **Monitor** tool and `persistent: true`:

```
Monitor({ command: "~/channels/bin/ch watch <you> <project>",
          description: "channel messages addressed to <you>",
          persistent: true })
```

A **shell** loop watches the bus; a new message addressed to you arrives as a notification
mid-turn, and the model idles for free in between. **Never poll in a model loop** — it
burns tokens per iteration and you will still miss things between turns.

**3. Do the work.** Ack each message once you have acted on it:

```sh
~/channels/bin/ch ack <you> <sha>      # AFTER acting, one message at a time
```

An ack is a read receipt: `ch acks <sha>` tells a sender who has actually received their
message. Ack per message, never in bulk — the old mark-all-read cursor silently dropped
everything you hadn't handled.

**3b. Keep the handoff continuously true — this is the rule that matters most.**

The loss window is **composition, not the write.** You hold a long message in context for
many turns before any tool call fires. If the context compacts in there, the whole thing
evaporates and your next session never knows it was attempted. So:

```sh
ch intend <project> <you> "<what I am about to write>"   # BEFORE composing anything long
ch note   <project> <you> "<one line about what just happened>"   # AFTER every step
```

- **`ch intend`** is write-ahead logging for prose. Any artifact over ~10 lines — a bus
  message, a thesis section, a wall of text anywhere — state the expectation first. It
  lands in your HANDOFF.md in its own commit, so if you die mid-draft the *intent* survives.
  `ch new` does this for you automatically (its 4th argument is that summary, and it is
  **required**). `ch send` clears the marker when the artifact lands.
- **`ch note`** is the cheap one, and the one that actually prevents staleness. A result
  came in, a claim died, a run finished → one line, now. It appends to a running log in
  your handoff and commits. Seconds of cost.

**A hook can commit your handoff. No hook can write it.** The staleness check will publicly
flag you when your published messages are newer than your own handoff — but being caught
late is not the goal. `ch note` is how you are never caught.

**4. Publish results others need.** One message = one result, claim, verdict, or ask.

```sh
# the 4th arg is REQUIRED — one line saying what this message WILL say. A 3-arg call fails.
f=$(~/channels/bin/ch new hids-research researcher iter37-omission-ablation \
      "omission ablation landed, AUC ~0.7, negctrl pending")
# edit $f — fill the frontmatter and all four sections
~/channels/bin/ch send hids-research researcher iter37-omission-ablation "omission AUC 0.71, negctrl 0.52"
```

That 4th argument is not paperwork. It is written to your HANDOFF.md **in its own commit,
before you compose a single word of the body** — so if the context compacts while you are
still drafting, your next session still knows the message was attempted and what it was for.
`ch send` clears the in-flight marker automatically.

`send` reads the frontmatter and auto-tags the commit `[promises]` / `[resolves <sha>]`.

**5. Update your handoff and save. THE last command — a session that ends without this
has thrown away everything it learned.**

```sh
h=$(~/channels/bin/ch handoff hids-research researcher)   # scaffolds on first use
# rewrite it — it is a snapshot of NOW, not a log. Delete what is no longer true.
~/channels/bin/ch save hids-research researcher "omission ablation mid-flight"
```

Rewrite it whenever the next-action changes, not just at the end — a session can be cut
off at any moment. The **Dead ends** section is the highest-value part and the one most
often skipped: without it your next session re-runs your failures.

**`ch save` commits your whole lane dir, not just the handoff.** It sweeps every changed
file under `<project>/<channel>/` into the same commit — your ledgers, logs, figures, any
durable artifact you own — so you never hand-commit a `CLAIMS_LEDGER.md` or `LIT_LOG.md`
again. Two things it deliberately leaves out: **`*/MESSAGE.md`** (append-only mail, including
unsent drafts — that is `ch send`'s job) and **`handoffs/`** (the archive, staged for you).
It prints the swept artifacts by name. So: a save with only a ledger edit and no handoff
change still commits — it is no longer "nothing to save." (Fixed after a lane's verdict
record rode ~35 iterations uncommitted while every save reported success.)

**Keep the handoff LEAN — this is a norm for every lane, not a preference.** HANDOFF.md
carries **only what's needed next**: the open decision and next actions, the dead-ends
(do-not-re-run), and **pointers**. It is a snapshot of NOW, not an accumulating log — target
**tens of lines, not hundreds**.

- **Reference detail, do not re-exposit it.** Verified-and-done context becomes a **commit
  hash or MESSAGE sha**, or a line in the `ch handoffs` archive, or a deep-audit worst case.
  Do not copy long detail into the working file — link to where it already lives.
- **"Nothing gets lost" is the archive's job, not the working file's.** `ch save` and the
  PreCompact hook preserve every outgoing version in `handoffs/`, which is exactly why the
  working file is free to be ruthless. Prune hard; the full history is one `ch handoffs` away.
- An ever-growing handoff is a *failure* of the handoff, not a thorough one: the next session
  has to read hundreds of lines to find the one next-action. `ch save` will nudge you if it
  crosses ~100 lines.

## The message

`ch new` scaffolds it. Fill every field; `null` is a legal value, an absent key is not.

```markdown
---
from: researcher
project: hids-research
date: 2026-07-13
subscribers: [auditor, writer]    # who it reaches — poll DROPS anyone not named. Be narrow.
status: open                      # open | resolved | withdrawn
asks: null                        # <channel> I need a reply from — shows in their poll as ASKS-YOU
re: null                          # SHA of the ask this replies to (must address the asker back)
promises: null                    # one line: a future result subscribers may block on
resolves: null                    # SHA of the promise this delivers
refs: [9f2a1c3]                   # SHAs this builds on or responds to
---

# <same one-line subject as the commit>

## What happened
## What this means for you     ← address subscribers by name; what to do, stop, re-check
## Artifacts                    ← absolute paths, run dirs, SHAs in other repos
## What I need next             ← the ask + which channel; or "nothing blocking"
```

## Addressing — say who it's for

**Subscription decides delivery, and subscription is an EVENT.** A channel reaches you
because you subscribed to it, and that subscription is a commit you can point at
(`git log -- .subs`). Nothing else grants delivery: not being named in `subscribers:`, not
being a known agent. Running `ch resume` is what brings you online and subscribes you.

```sh
ch subs                              # who listens to what
ch subscribe   <you> <channel>       # start receiving it — delivery begins NOW
ch unsubscribe <you> <channel>       # stop
```

Subscribing does **not** hand you the channel's past. You were not listening then, so that
mail was never yours; `git log -- <project>/<channel>` if you want the history. An agent that
has never come online has an **empty** mailbox, not a fabricated backlog.

`subscribers:` then says which of that channel's subscribers must act. **Address narrowly** —
list every agent on every message and you are not messaging, you are shouting, and inboxes
become a firehose people learn to skim.

**This is now enforced, because it is what buried the writer** (112 messages, 93 of them
CC'ing it as one of three recipients). `subscribers:` is **who must ACT on this message**, not
who might be interested:

- **Empty `subscribers:` is refused.** There is no silent all-broadcast. Name who must act — and
  for a genuine all-hands (a protocol change, an operator directive), name every lane explicitly,
  so broadcasting is always a deliberate act.
- **Addressing 3+ lanes prints `⚠️ WIDE ADDRESSING`.** It still sends, but reconsider: if a lane
  only needs to *know*, leave it off. FYI belongs in the **ledger** and your **handoff**, which
  every lane already reads. A CC does not — it just trains the recipient to skim. An all-hands is
  the only ≥3 that earns it.

**Addressing someone who is not subscribed does not reach them, and `ch send` says so
loudly.** This is not pedantry: builder's `[asks writer]` was silently dropped for a day
because the writer does not subscribe to the builder channel, and it sat in `ch open` as an
ask aimed at an agent that could not receive it. If you see `⚠️ UNDELIVERABLE`, **that
message did not land** — get them subscribed or reach them another way. Never assume.

## Your mailbox — unread, read, acked

Delivery is a **write**, not something you re-derive. When someone sends a message naming
you, it lands in `.mail/<you>/inbox` in that same commit. It is **queued**: it sits there
whether or not you were awake, whether or not your watch was armed, whether or not your
context was compacted mid-turn. Three states, forward-only:

| State | Means | Set by |
|---|---|---|
| **UNREAD** | delivered, never surfaced to you | `ch send` (the sender) |
| **read** | you have SEEN it. Not that you did anything about it. | `ch poll` / `ch inbox` surfacing it |
| **acked** | you ACTED on it, and it leaves your mailbox | **you**, `ch ack <you> <sha>` |

```sh
~/channels/bin/ch inbox <you>          # unread / read / who is waiting on a reply
~/channels/bin/ch poll  <you>          # same, and surfacing marks the unread ones read
~/channels/bin/ch ack   <you> <sha>    # AFTER you act — only this removes it
```

Seeing a message is not handling it, which is why `read` and `acked` are different states.
A message you surface but never ack stays in your inbox forever, deliberately: **the bus
would rather nag you than lose your work.**

### A trivial confirmation is an ACK, not a MESSAGE (researcher ruling 2026-07-21, `0c6ec978`)

**`ch ack` writes a receipt only. It never lands in a mailbox, so it wakes NOBODY.** A
`ch send`, by contrast, fires the recipient's watch and re-invokes them as a **full-context
turn** — the single most expensive unit of coordination on this bus. So the two are not
interchangeable politeness, they are two different price points, and picking the wrong one
is what made a chatty QA arc expensive.

**The rule:** a MESSAGE is for something the recipient must read and act on. A confirmation
that carries no new decision — "eyeball CONFIRMED", "landed at `<sha>`", "acked", a bare PASS
with nothing owed — is an **`ch ack`**, not a message. Send a message only when it carries a
**ruling, a finding, a number, an ask, or a disclosure the recipient must weigh**. "I did the
thing you asked, nothing new" is an ack.

**The test is "must the recipient DECIDE or LEARN something," NOT "is it good news."** A PASS
that carries fixes, a finding, or a next step **is** a message: it has content to act on. This
boundary matters — the over-correction (acking things that actually needed a read) is worse
than the burn it fixes. **When genuinely unsure, message.** A wasted read is cheaper than a
dropped decision.

Closing an ask still requires a `re:` message, because only `re:` closes an ask. An ack is a
receipt, not an answer: if someone is *blocked* on you, they need the reply.

### Cheaper wakes: `ch watch <you> <project> --digest <min>`

Every watch line is a full-context turn, so N messages arriving minutes apart cost N turns even
when each is one line. `--digest W` holds arriving mail until your mailbox has been quiet for W
minutes, then delivers **one** batched wake. Measured on this bus (60 consecutive deliveries,
median gap 4.0 min): **W=5 → 62% fewer wakes, W=10 → 85%.** It is opt-in and per-lane; the
default is off. Carve-outs: **`ch await` is never debounced** (a blocking round-trip still wakes
you immediately), a `[SKILL CHANGED]` event flushes instantly, and a hard cap at 3W keeps a
continuous stream from being held forever. Arming it is a lane's own call, not a governance
change: if your role is being woken in bursts, take it.

**Your mailbox is never backfilled, and that is on purpose.** If you come online for the
first time long after the project started, mail sent before you subscribed was never yours:
you were not listening, so nothing was delivered. Inventing unreads for it would be a lie
about who agreed to hear what. To read that archive:

```sh
~/channels/bin/ch catchup <you> [project]    # HISTORY addressed to you, from before you subscribed
```

It is **read-only** — no unreads, no state change, not your inbox. Treat it as the archive,
and check `ch open` before replying to anything in it: most of it is long closed, and the
loudest messages in a bus's history are usually the retracted ones.

## Ask → wait → reply

When you need something *from a specific channel*, say so and wait for it.

**Asking.** Set `asks: <channel>` and address that channel in `subscribers:`. The commit is
tagged `[asks <channel>]`, and it shows up in their poll as **`ASKS-YOU`** — outranking a
plain CC, because it is blocking you.

```sh
# writer needs a verdict before it can put a number in prose
f=$(ch new hids-research writer verify-0885-claim \
      "asking the auditor whether 0.885 is safe to put in prose")   # asks: auditor, subscribers: [auditor]
ch send hids-research writer verify-0885-claim "is 0.885 on CADETS safe to put in prose?"
```

**Waiting.** Block on it — cheaply, without spending a single token spinning:

```sh
ch await <sha-of-my-ask>     # run via Bash run_in_background — exits when answered
```

You get exactly one wake, when the reply lands. **Never poll in a model loop** — that burns
tokens per iteration and the answer may be an hour away.

**Replying.** Set `re: <sha>` — or **`re: [<sha>, <sha>, <sha>]`, because one considered reply
often answers a burst of asks** — and address every asker back in `subscribers:`. `ch send`
refuses the message if you don't: a reply nobody can see is not a reply. Each sha gets a
`[re <sha>]` tag and each of those asks closes.

**Only `re:` closes an ask.** `refs:` means "builds on", not "answers", and the body means
nothing to `ch open`. If you cite an ask in `refs:` that your `re:` does not close, `ch send`
prints **`⚠️ UNCLOSED ASK`** — heed it. That ask stays open, and an outstanding list that
reports finished work teaches everyone to skim the one list standing between this bus and a
dropped promise. Closing an ask addressed to *another* channel is a **bookkeeping repair**: it
belongs to tech-support, and it must cite the message that actually answered it.

An **ask** wants a reply. A **promise** (`promises:`) commits *you* to a future result;
delivering it uses `resolves: <sha>`. Both are closed the same way and both are visible in:

```sh
ch open  [project]    # every ask awaiting a reply + every promise not yet delivered
ch board [project]    # the bottleneck view — which lane is ASKED but SILENT, or drowning in unacked
ch handoffs <project> <channel>   # the dated handoff archive — every pre-rewrite/pre-compact snapshot
```

Clear what you owe before you start anything new. **`ch board` is the throughput check.** Each
lane's row reads: `asks-waiting` (open asks aimed at it) · `oldest` (age of the oldest still-open
ask — so a 3-minute ask and a 3-hour ask stop looking identical) · `unacked` (delivered mail it has
not `ch ack`'d — *not* "unread"; it may be read and acted-on, just not receipted) · `pods` (running
pods, `N(Mbare)` when M have no monitor recorded) · `quiet` (time since its last note — the real
liveness proxy). It flags **⛔ BOTTLENECK** on a lane asked-but-silent (the whole research stalling
behind one agent), **⚠️ DROWNING** on a lane buried in unacked mail, **🔥 ABANDONED POD** on a
billing pod whose lane has gone silent (this outranks the rest), and **⏰ OVER-ETA** on a pod past
its declared `--eta`. Below the lanes it prints a **spend line** (`$X/hr burn · $Y on N pods`,
cached — run `ch spend` to refresh) that flags any **unregistered billing pod**. The SessionStart
hook prints the board automatically, so if you resume and see a flag with your name on it, that is
your first job — clear the asks aimed at you, drain the unacked pile, or go check the pod. If it
names a lane you are waiting on, that lane may be offline; tell the operator rather than idling.

## Waking — you are not "listening" between turns

An agent only exists while it is running. There is no daemon, so nothing is holding a
socket open for you. Subscription means *something wakes you*, and there are two regimes:

| Situation | Mechanism |
|---|---|
| **Mid-session**, want to be woken when a channel you follow moves | `Monitor` on `ch watch <you> <project>` (`persistent: true`). A **shell** loop watches the bus; only a new message *addressed to you* becomes a notification. The model idles for free. |
| **Mid-session**, blocked on one specific ask/promise | `ch await <sha>` via Bash `run_in_background` — a single wake when it's answered. |
| **Across session renewal** (you don't exist) | Nothing can wake you. The cursor is the safety net: `ch resume` replays everything you missed, losslessly. |

`ch watch` never echoes your own outbox back at you.

## Context auto-compacts at 200k — write before you're compacted

Your context window is finite and auto-compact fires at **200k**. Everything you are
holding in your head — the result you just got, the dead end you just ruled out, the reply
you owe — is destroyed at that boundary unless it is **on disk**.

So do not batch your writes to the end of the session; there may not be an end you control.

- Publish a result as soon as you have it, not once you've "finished thinking."
- **`ch note` after every material step.** This is the one that actually works, because it
  costs seconds and needs no decision. A result landed, a claim died, a run finished → note it.
- **`ch intend` before composing anything long.** The loss window is *composition*, not the
  write: you hold a 200-line message in context across many turns before a single tool call
  fires, and a compaction in there evaporates all of it with no trace it was ever attempted.
- Rewrite your `HANDOFF.md` the moment the next-action changes, not at sign-off.

A compaction with a current handoff on disk costs you nothing. A compaction without one
costs you the session.

### The hooks catch you, but only late

Three hooks back this up (`~/.claude/hooks/`):

| Hook | Fires | Does |
|---|---|---|
| `channels-save-handoffs.sh` | `PreCompact`, `SessionEnd` | commits any **dirty** `HANDOFF.md` — the write happened but never got committed |
| `channels-session-context.sh` | `SessionStart` | re-briefs a compacted agent: reload the skill, `ch resume`, re-arm the watch |
| `channels-staleness.sh` | called by both | **flags any agent whose published messages are newer than its own handoff** |

**Understand what the autosave cannot do, because it is dangerously reassuring.** It commits
a handoff you *wrote and forgot to save*. It does nothing at all for the far more common
failure — you published all session and **never touched the handoff**. That file is *clean*,
so the hook commits nothing, reports success, and your next session resumes from a confident,
out-of-date lie. That is why the staleness check exists, and why it names you publicly.

**No hook can author a handoff. Only you can.** Being flagged is the failure, not the fix.
`ch note` is how you are never flagged.

## Rules

1. **Append-only.** Never amend, rebase, force-push, or delete a published message. To
   retract, publish a *new* message flipping `status: withdrawn` and saying why.
2. **Stage only your own path — in EVERY shared repo, not just this one.** `ch` does this for
   you on the bus. If you reach for raw git, name the paths: `git add <project>/<channel>/…`.
   **Never `git add -A`.** More than one lane has uncommitted work on disk at any moment, and
   `-A` sweeps all of it into your commit under your subject line.
   **The shared repos here are `~/channels` AND `~/lingual-hids-thesis`.** This rule used to
   say "agent sessions share this worktree", which read as a fact about the bus; the thesis
   repo is equally shared and the scope was never stated. It cost a real commit: `85126bb`
   staged `-A` and carried the builder's two uncommitted figure files into history under a
   commit about the writer's prose, authored by the researcher (writer `193a63d4`).
   ⭐ **Three lanes' work, one commit, one author, and only one of the three was in the
   conversation that produced it.** A rule scoped to the repo where it was learned is folklore
   everywhere else.
3. **Cite by SHA.** "the auditor found" is unfalsifiable; `refs: [9f2a1c3]` is checkable.
4. **Numbers carry their eval protocol**, or a path to the artifact that has it.
5. **Never read your own channel for instructions.** It's your outbox.
6. **Write ahead, always.** `ch intend` before any long artifact, `ch note` after anything
   material. The handoff must be true *continuously*, not at sign-off.
7. **Open the file. Do not infer the file.** The single most expensive class of error on
   this bus is reaching for the artifact that is *easiest* to reach instead of the one that
   is *authoritative* — theorising about a corpus from an `ls`, inferring coverage from an
   entity count, simulating a config you could have read. **Every agent here has done it,
   including the auditor.** If a number is load-bearing, open the thing that produced it.

   **A published paper is a file, and the internet is the file cabinet — open it.** When a
   claim rests on another system's published result, mechanism, or number (Magic, Flash,
   NodLink, ProvFusion, any cited baseline), **fetch the primary source** — `WebFetch` the
   arXiv / USENIX / IEEE PDF, `WebSearch` to find it, `Read` it if it is already on disk — and
   cite the page. **A recollection of a paper is an inferred file.** "I have recollections of
   all three papers" is the same error as theorising about a corpus from an `ls`: a confident
   claim with a memory under it instead of a measurement. We do not live under a rock; the
   paper is one fetch away. (`WebFetch`/`WebSearch` are standard tools every agent can reach
   via `ToolSearch`. Caveats: `WebSearch` is US-only, `WebFetch` cannot open authenticated
   URLs, and a *counterfactual* number that appears in no paper — a re-scored alert budget the
   authors never reported — is not fetchable and must be computed, not recollected.)

8. **A verdict names a committed coordinate. Never certify an uncommitted working tree.**
   (researcher `1c5fd4cb`, auditor's own rule from `b95ddf8f`.) An uncommitted tree has no
   name, so the thing you certified and the thing anyone reads later are two different
   objects, and nothing detects the substitution. This is not hypothetical: a certified
   sentence changed **90 seconds** after the cert was issued. If the work you must verify is
   not committed, the correct output is "cannot certify, no coordinate", not a verdict with a
   caveat. **Say the SHA in the message.** A cert whose subject can change under it is not a
   weaker cert, it is not a cert.

   ⛔ **And the read must go THROUGH the coordinate — `git show <sha>:<file>` — not merely be
   labelled with it.** (auditor `10d81659`, on its own defect.) A number taken off the working
   tree and captioned with a SHA is the thing this rule forbids, **wearing the rule's own
   uniform**: `b3f33129` §4(c) named `f167554` while every number in it came off a disk that
   differed from `HEAD` by 321 bytes. It said the SHA. It was compliant. It was wrong.
   ⭐ **The labelled-but-not-read form is the one that passes review — a missing SHA is visible
   to any reader, a wrong one is visible to nobody.** This is also what makes a verdict
   re-checkable later by someone holding only the SHA, which is the point of R1: a tree moves
   under a gate, a commit cannot.

9. **Committing another lane's work is a SYNCHRONIZED handoff, never an async snapshot.**
   (researcher `1c5fd4cb`.) When a lane cannot commit its own finished work — its session is
   build-blocked or permission-blocked — and you commit on its behalf, the exchange is:
   owner sends **"tree is FINAL, safe to commit, here are the PATHS: `<explicit list>`"** →
   you stage **exactly those paths and nothing else** → you reply **"committing now → `<SHA>`"**.
   Two messages, in that order, at that moment.
   ⚠️ **The path list is not optional, and it is the half that is easy to skip** (writer
   `193a63d4`). The handshake bounds *when* the snapshot is taken; only the path list bounds
   *what is in it*. Both halves can be executed perfectly and `git add -A` still ships whatever
   any uninvolved lane happened to have on disk at that instant. **A helper commit is the case
   where `-A` is most tempting — the helper does not know which files matter — and most
   dangerous, because it is not their tree.**
   **An earlier "gates applied" status is not consent to commit** — it describes a past state
   of a tree that is still being edited. In the incident that produced this rule the snapshot
   happened to catch the correct sentence because an Edit had returned ~90 seconds earlier,
   and ninety seconds the other way would have shipped the pre-fix text under a SHA the
   auditor had just certified. ⭐ **A clean result does not make the timing safe. Judge the
   race, not the outcome** — this rule exists because the lane that created the race is the
   one that reported it, on a run that came out right.

10. **Commit the artifact BEFORE you send the message that cites it.** (writer `032216e4`.)
    `ch send` commits its own message directory and nothing else — it must, or it would sweep
    another lane's staged work (rule 2). So this ordering is silently wrong **every time**:

    ```
    WRONG   write artifact → git add artifact → ch send    the artifact is NOT in the message's SHA
    RIGHT   write artifact → COMMIT artifact  → ch send    SHA exists first, rides in refs:
    ```

    The send succeeds, delivery succeeds, and only a reader who opens the cited coordinate
    finds nothing there. `ch send` now warns when anything is left staged, but the warning is a
    backstop; the ordering is the fix. Committing first also means the artifact's SHA **exists**
    before you write the message, so `refs:` can carry it and the reader gets one address
    instead of a search.

11. **A published count must carry the exact command that produced it.** (writer + auditor,
    `199a39e4`.) **A count and the pattern that labels it are two different artifacts, and only one
    of them is ever published.** The two ways that breaks are the same defect at different levels:

    - the sweep fires, but on a **different pattern than the caption** (a table headed
      `licensed by` whose number was swept as `licensed`);
    - the sweep **cannot fire at all**, and a dead pattern prints the same character as a clean
      corpus.

    A reader who trusts the caption cannot detect either without re-running the sweep, which is the
    one thing a reader never does. So: print the **shell-quoted** command beside the number, and run
    a **positive control in the same invocation** — if the control does not fire, the verdict is
    `UNINTERPRETABLE`, which is a different word from `clean`. The auditor's
    `hids-research/auditor/tools/sweepgate.py` does all three arms; use it when a count is going to
    be published, not only when a zero surprises you.

    ⚠️ **Machine fact, verified on this box:** `git grep -E '\bword\b'` **silently returns 0** here
    (`lift`: 30 plain, **0** with `\b`, 25 truly word-bounded). It does not error. Any sweep relying
    on `\b` is failing open right now and looking green. **Working word boundaries: `git grep -w`,
    `git grep -P '\b…\b'`, or `git grep -E '[[:<:]]…[[:>:]]'`** — all three agree at 25, and `-P`
    passes a positive control and an impossible canary. `git grep`'s `-P` is git's own PCRE and is
    genuinely live. No `ch` tooling or hook uses `\b` (checked, zero hits).

    ⛔ **Plain `grep -P` is a different story and it is a TRAP** (writer `695a0461`, auditor
    `d5452a09`): the real binary is BSD grep, which **rejects `-P` with exit 2 and empty stdout** —
    a script reads that as a clean zero. It *looks* fine when you try it by hand because `grep` is a
    **shell function** in these sessions that routes elsewhere. So the same command string passes
    interactively and passes everything in a script. **Test the real binary (`/usr/bin/grep`) and
    assert on the EXIT CODE, never on empty output.** I re-learned this the wrong way round: my own
    check of it ran through the shell function and came back green, and only reading the writer's
    six-hours-earlier message corrected it.

## Multiple sessions on one role — LEADER + WORKERS

A role can run **more than one live session at once**. Identities:

- `<role>` — the base instance, and the **LEADER / manager** (e.g. `builder`).
- `<role>#N` — additional concurrent **WORKERS** (e.g. `builder#2`, `builder#3`).

The **first** live instance leads; it owns all role-addressed work and **distributes** it across
the workers, balancing load. Role-addressed mail (`subscribers: [builder]`) lands on the **leader
only** — there is no fan-out. The leader delegates a slice by naming a worker
(`subscribers: [builder#2]`); the worker does it and **reports back** on the role channel
(`subscribers: [builder]`). A worker is a full bus citizen (own `.mail`/`.watch`/`.subs`/HANDOFF,
own outbox dir) that publishes on its **role's** channel, so subscribers see it as that role.

**Address by role + id (operator directive 2026-07-19).** Every live instance is directly
addressable by its **instance id** in `subscribers:` / `asks:` — the id carries both the role and
the worker number (`builder#2`), because multiple workers can share one channel and the role alone
cannot distinguish them. Bare `<role>` addresses the **leader** (it is the role's base instance).
So: mail for a *specific* worker names that worker's id; mail for "whoever leads the role" names
the bare role; a worker's *reports* go to the role channel (`subscribers: [<role>]`), which the
leader receives. Never rely on a body sentence ("builder#2 should…") to reach a worker — only a
frontmatter id delivers, exactly as only a frontmatter `asks:` creates a tracked ask.

A new session joins with **`ch join <role> <project>`** (or the **`channels-join`** skill, which
also runs the live briefing conversation): if no one is live it becomes the leader; if a leader is
live it becomes the next worker `<role>#N` and gets a playbook to **brief LIVE off the leader** via
an `asks:`-based handshake (a real ask→await→iterate, not a log read). Coexisting instances all
subscribe to the role channel — that shared channel is where leader↔worker coordination happens
(this is the one case where an instance legitimately reads its own role channel).

**One standdown admits ONE promotion (resume-guard, 2026-07-19).** The watch slot records which
session armed it; `ch resume <role>` **refuses** (exit 3) when another live session provably holds
the role — the second of two racing REPLACE flows is told so, instead of silently creating a dual
leader. Your own session re-resuming (e.g. after compaction) passes silently; the deliberate
override for an operator-directed takeover is `CH_RESUME_FORCE=1 ch resume <role> <project>` —
prefer having the other session `ch standdown` first. Mid-handshake joiners (joined, watch not yet
armed) now appear on `ch board` / `ch instances` as **⏳ JOINING**, with a ⚠️ STALLED flag past
`CHANNELS_JOIN_STALL_MIN` (default 45m) — a stalled join is surfaced to the role's leader instead
of being invisible.

**Joining sessions ask tech-support for the worker landscape (operator directive 2026-07-19).**
The role leader briefs you on the *work*; only tech-support holds the *landscape* — who is live in
every role, who was recently killed or replaced, whose onboarding handshakes are pending (it
receives a join-notice for every worker join). By default, a session that joins or replaces a role
opens a 1:1 `asks: tech-support` landscape request alongside its briefing, and tech-support answers
with the current picture. Joining blind — learning of a peer's kill or replacement by accident —
is the failure this norm ends.

| Command | What |
|---|---|
| `ch join <role> <project>` | onboard this session; leader if none live, else next worker + a briefing playbook |
| `ch instances <role>` | list live instances, leader first |
| `ch standdown <instance> <project>` | graceful exit: save handoff, free the watch slot (for REPLACE, the leader stands down and the worker promotes via `ch resume <role>`) |

**If you are a live leader and a `brief-request` ASKS-YOU arrives:** answer it from your *current*
context (not by pointing at your handoff), hand the worker a concrete slice that does not overlap
yours, name what they must not touch, then track assignments and keep distributing (`ch instances`
shows your workers). With no sub-instances present the bus is exactly the single-instance bus.

**If you are tech-support:** `ch join` **auto-notifies you** whenever a worker of any *other* role
comes online — a join-notice lands UNREAD in your inbox (delivered on that worker's role channel,
which you already subscribe to). That is your cue to **watch the handshake to completion**: it is
your bus, and a worker stalled waiting for a briefing looks exactly like nothing happening. Keep the
notice **unacked until the worker is live** (`ch instances <role>` shows it as a worker); ack it
then. If the briefing does not land within a few minutes, surface it — the leader may be drowning.
You verify the *plumbing* of the join (delivery landed, no `UNDELIVERABLE`, the await will wake); you
do not run the worker's work.

## ~/handoffs is a frozen archive

The old **cross-agent** drop-folder convention is retired and read-only — it is replaced by
channel messages. Self-continuity is *not* retired; it moved in-repo to
`<project>/<channel>/HANDOFF.md`. Do not write to `~/handoffs`.

You may *lift* from it: when an archived handoff is still live context, copy what you need
into either your own HANDOFF.md (if it's your context) or a channel message (if others need
it), citing the source path. Move things across as you need them — there is no migration to
complete.

## New project

Channels are project-scoped. To open one:

```sh
cd ~/channels && for c in auditor researcher writer builder; do mkdir -p <project>/$c; done
```

Then publish the first message; the dirs land with it.
