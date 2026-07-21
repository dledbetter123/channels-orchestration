# Protocol: messages, asks, and promises

## The message

`ch new <project> <channel> <slug> "<expectation>"` scaffolds a message directory; `ch
send` commits it. The fourth argument (a one-line statement of what the message WILL say)
is required and is written to the sender's handoff in its own commit **before composition
starts**, so if the session dies mid-draft, the next session knows the message was
attempted and why. Sending clears the marker.

Every field must be present; `null` is a legal value, an absent key is not.

```markdown
---
from: researcher
project: hids-research
date: 2026-07-13
subscribers: [auditor, writer]    # who must ACT. Delivery only reaches actual subscribers.
status: open                      # open | resolved | withdrawn
asks: null                        # <channel> I need a reply from; shows in their poll as ASKS-YOU
re: null                          # SHA of the ask this replies to (must address the asker back)
promises: null                    # one line: a future result subscribers may block on
resolves: null                    # SHA of the promise this delivers
refs: [9f2a1c3]                   # SHAs this builds on or responds to
---

# <same one-line subject as the commit>

## What happened
## What this means for you     <- address subscribers by name; what to do, stop, re-check
## Artifacts                   <- absolute paths, run dirs, SHAs in other repos
## What I need next            <- the ask and which channel, or "nothing blocking"
```

One message = one result, claim, verdict, or ask. The commit subject mirrors the message
subject, and the CLI auto-tags commits `[asks <channel>]`, `[re <sha>]`, `[promises]`,
`[resolves <sha>]` from the frontmatter, which is what makes the history greppable.

## Addressing: narrow, enforced

`subscribers:` means "who must act on this", not "who might be interested":

- **Empty `subscribers:` is refused.** There is no silent broadcast. A genuine all-hands
  (protocol change, operator directive) names every lane explicitly, so broadcasting is
  always deliberate.
- **Addressing 3 or more lanes prints a WIDE ADDRESSING warning.** It still sends, but the
  norm is: if a lane only needs to know, leave it off. FYI belongs in ledgers and
  handoffs, which every lane already reads. This rule exists because one agent was buried
  by 93 CC's out of 112 messages and learned to skim its own inbox.
- **Every live instance is addressable by id** (`builder`, `builder#2`). Bare role names
  address the role's leader. A body sentence like "builder#2 should..." delivers nothing;
  only frontmatter delivers.

## Ask, wait, reply

The ask/promise machinery is what makes cross-agent work trackable rather than
conversational:

- **Ask:** set `asks: <channel>` and address that channel. The commit is tagged and shows
  in the recipient's poll as **ASKS-YOU**, outranking plain mail because it is blocking
  someone.
- **Wait:** `ch await <sha>` in a background process. One wake, when answered. No token
  is spent while waiting.
- **Reply:** set `re: <sha>` (or a list: one considered reply may close a burst of asks)
  and address every asker back. The send is refused otherwise: a reply nobody can see is
  not a reply.
- **Only `re:` closes an ask.** `refs:` means "builds on", not "answers". Citing an ask in
  `refs:` without closing it prints an UNCLOSED ASK warning, because an outstanding-work
  list that reports finished work trains everyone to ignore the one list standing between
  the bus and a dropped promise.
- **Promise:** `promises:` commits the sender to a future result; delivering it uses
  `resolves: <sha>`. Both closed the same way, both visible in the shared views.

## A trivial confirmation is an ack, not a message

`ch ack` writes a receipt and lands in no mailbox, so it wakes nobody. `ch send` fires the
recipient's watch and buys them a **full-context turn**, the most expensive unit of
coordination on the bus. The two are not interchangeable politeness; they are two price
points, and choosing wrong is what makes a chatty review phase expensive.

The rule: a message is for something the recipient must read and act on. A confirmation
carrying no new decision ("confirmed", "landed at `<sha>`", a bare PASS with nothing owed)
is an ack. Send a message only when it carries a ruling, a finding, a number, an ask, or a
disclosure the recipient must weigh.

The boundary matters as much as the rule, because the over-correction (acking something
that needed a read) is worse than the burn it fixes. The test is **"must the recipient
decide or learn something,"** not "is it good news": a PASS that carries fixes or a next
step is a message. **When genuinely unsure, message** — a wasted read is cheaper than a
dropped decision. An ack never closes an ask; only `re:` does, so a lane blocked on you
gets a reply, not a receipt.

## The shared views

```
ch open  [project]    # every ask awaiting a reply + every promise not yet delivered
ch board [project]    # the bottleneck view (below)
ch pods / ch spend    # billing hardware and burn (see operations.md)
```

`ch board` prints one row per lane: open asks aimed at it, the age of the oldest, unacked
mail, running pods, and time since its last note (the real liveness proxy). It raises
named flags:

- **BOTTLENECK**: a lane is asked-but-silent (the whole pipeline is stalling behind it)
- **DROWNING**: a lane buried in unacked mail
- **ABANDONED POD**: a billing pod whose lane has gone quiet (outranks everything)
- **OVER-ETA**: a pod billing past its declared runtime envelope

The session-start hook prints the board automatically. The standing norm: if you resume
and see a flag with your name on it, that is your first job. Clear what you owe before
starting anything new.

## Protocol versioning

The protocol itself is versioned and its changes are delivered as events. Only
tech-support bumps it:

- A **major** bump re-stales every lane and fires a mandatory `[SKILL CHANGED]` event:
  stop, reload the protocol, then `ch skill-ack` to clear your stale flag.
- A **minor** bump (typo, threshold nudge) records the change without re-staling anyone;
  lanes pick it up at their next natural resume.

Severity exists because before it, every trivial edit cried wolf and lanes learned to
skim the one warning that mattered. Companion rule: a bus norm that lives only in one
agent's memory or in an old message "is not a norm, it is folklore"; every persistent rule
must live in the shared, versioned protocol document.
