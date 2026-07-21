# Multiple sessions on one role: leaders, workers, and takeovers

A role can run more than one live session at once. This is how the pipeline scales a lane
horizontally (two builder sessions grinding parallel slices) and how a role is handed from
one session to another without a gap or a collision.

## Identities

- `<role>` is the base instance and the **leader** (e.g. `builder`).
- `<role>#N` are additional concurrent **workers** (e.g. `builder#2`, `builder#3`).

The first live instance leads. Role-addressed mail (`subscribers: [builder]`) lands on the
leader only; there is no fan-out. The leader delegates a slice by naming a worker in
frontmatter (`subscribers: [builder#2]`); the worker does it and reports back on the role
channel, which the leader receives. Every live instance is a full bus citizen (own mailbox,
watch slot, handoff) that publishes on its role's channel, so the rest of the bus sees it
as that role.

Addressing is by role plus id: bare `<role>` reaches whoever leads; a specific worker's id
reaches that worker. With no workers present, the bus degenerates exactly to the
single-instance bus.

## Joining: a live briefing, not a log read

A new session joins with `ch join <role> <project>`:

- **No live incumbent:** the joiner becomes the leader, arms its watch, and runs the role.
- **Leader live:** the joiner becomes the next worker and gets a playbook whose core is a
  real ask-and-await handshake, not a document read. The worker opens a `brief-request`
  ask to the leader and blocks on the reply. The leader answers **from its current
  context** (what is mid-flight right now, what slice the worker should take, what the
  worker must not touch, landmines already hit) and the worker iterates with follow-ups
  until it can say "briefed, taking X". A worker guessing its slice collides with the
  leader, which is the failure this handshake prevents.

Two visibility mechanisms wrap the join:

- **The joining marker.** `ch join` drops a marker that arming the watch clears. The shared
  board shows mid-handshake joiners as `JOINING <age>` and escalates to `STALLED` past a
  threshold (default 45 minutes), so a joiner that briefs and then dies is loud instead of
  invisible.
- **The landscape ask.** The role leader briefs on the *work*; only tech-support holds the
  *landscape* (who is live in every role, who was recently replaced, which handshakes are
  pending; it is auto-notified of every worker join). A joining session opens a 1:1 ask to
  tech-support for the current picture alongside its briefing. Joining blind, and learning
  of a peer's replacement by accident, is the failure this norm ends. tech-support keeps
  each join-notice unacked until the worker is live, and verifies the plumbing of the join
  (delivery landed, the await will wake); it does not run the worker's work.

## Standdown and replacement

Graceful exit is `ch standdown <instance> <project>`: it saves the instance's handoff
(which becomes the successor's inherited context) and frees the watch slot. A REPLACE flow
is: the incumbent stands down, then the successor promotes with `ch resume <role>` and
arms the leader watch.

## The resume guard: one standdown admits one promotion

The failure this exists for: two sessions racing one vacancy, both promoting, and the role
ending up with two leaders who each believe they are sole. It happened once; the fix is
session-identity awareness in the watch slot:

- Arming a watch records the arming session's id next to the pid
  (`.watch/<agent>.sid`).
- `ch resume <role>` **refuses** (distinct exit code) when another live session provably
  holds the role: the second of two racing REPLACE flows is told so instead of silently
  creating a dual leader.
- Your own session re-resuming (e.g. after a compaction) passes silently, and a
  same-session re-arm reaps its own stale watcher and takes the slot back.
- A deliberate operator-directed takeover uses an explicit force flag, with the stated
  preference that the incumbent stand down first.
- Legacy watches armed before the guard existed fall back to warn-only until their next
  re-arm, so an upgrade never locks anyone out.

One boundary was deliberately left open: a genuinely **vacant** slot (the prior watch
died) is claimable by anyone, because a vacancy that only one blessed session could claim
would block operator-intended takeovers and make promotion impossible after a crash. The
guard stops races on one vacancy; it does not (and should not) encode operator intent
about who deserves the role. When two claims conflict anyway, the operator rules, and the
record is corrected on the bus rather than relitigated.
